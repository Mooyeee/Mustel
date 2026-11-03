import AppKit
import Darwin
import Foundation
import ServiceManagement
import SwiftUI

enum FlutterSessionMode: Hashable, Sendable {
    case attach
    case attachURL
    case run
}

struct FlutterDeviceInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let targetPlatform: String
    let isSupported: Bool

    var supportsAttachDiscovery: Bool {
        targetPlatform.hasPrefix("android-") || targetPlatform.hasPrefix("ios-")
    }
}

struct FlutterTarget: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let projectPath: String
    let deviceID: String
    let targetPath: String?
    let vmServiceURL: String?
    let mode: FlutterSessionMode
}

private enum FlutterExecutableLocator {
    static func resolve(_ configuredPath: String, projectPath: String? = nil) -> String {
        let configuredPath = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configuredPath.isEmpty, !configuredPath.contains("/") else {
            return configuredPath
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates: [String] = []
        if let projectPath {
            candidates.append("\(projectPath)/.fvm/flutter_sdk/bin/\(configuredPath)")
        }
        candidates.append(contentsOf: (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/\(configuredPath)" })
        candidates.append(contentsOf: [
            "\(home)/development/flutter/bin/\(configuredPath)",
            "\(home)/flutter/bin/\(configuredPath)",
            "\(home)/fvm/default/bin/\(configuredPath)",
            "\(home)/.fvm/default/bin/\(configuredPath)",
            "/opt/homebrew/bin/\(configuredPath)",
            "/usr/local/bin/\(configuredPath)"
        ])

        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)) ?? configuredPath
    }
}

private struct DiscoverySnapshot: Sendable {
    let devices: [FlutterDeviceInfo]
    let targets: [FlutterTarget]
    let skippedRuns: Int
    let unsupportedRuns: Int
    let ideManagedRuns: Int
}

private enum FlutterRunDiscovery {
    static func discover(flutterExecutable: String) throws -> DiscoverySnapshot {
        let deviceOutput = try runFlutter(
            flutterExecutable,
            arguments: ["devices", "--machine"]
        )
        guard let deviceData = deviceOutput.data(using: .utf8),
              let rawDevices = try JSONSerialization.jsonObject(with: deviceData) as? [[String: Any]] else {
            throw DiscoveryError.invalidDeviceList
        }

        let devices = rawDevices.compactMap { device -> FlutterDeviceInfo? in
            guard let id = device["id"] as? String,
                  let name = device["name"] as? String,
                  let platform = device["targetPlatform"] as? String else {
                return nil
            }
            return FlutterDeviceInfo(
                id: id,
                name: name,
                targetPlatform: platform,
                isSupported: device["isSupported"] as? Bool ?? false
            )
        }
        let supportedDevices = devices.filter(\.isSupported)

        let processList = try run(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,command="]
        )
        var targetsByID: [String: FlutterTarget] = [:]
        var skippedRuns = 0
        var unsupportedRuns = 0
        var ideManagedRuns = 0

        for line in processList.split(whereSeparator: \.isNewline) {
            guard let process = parseProcess(String(line)),
                  isFlutterRun(process.command) else {
                continue
            }
            guard !isMachineMode(process.command) else {
                ideManagedRuns += 1
                continue
            }

            let requestedDeviceID = deviceID(in: process.command)
            let selectedDevice: FlutterDeviceInfo?
            if let requestedDeviceID {
                selectedDevice = supportedDevices.first { $0.id == requestedDeviceID }
                if selectedDevice == nil {
                    skippedRuns += 1
                }
            } else if supportedDevices.count == 1 {
                selectedDevice = supportedDevices.first
            } else {
                selectedDevice = nil
                skippedRuns += 1
            }

            guard let selectedDevice else { continue }
            let projectPath: String
            do {
                projectPath = try workingDirectory(of: process.pid)
            } catch {
                skippedRuns += 1
                continue
            }
            guard FileManager.default.fileExists(atPath: "\(projectPath)/pubspec.yaml") else {
                skippedRuns += 1
                continue
            }

            let serviceURL = vmServiceURL(in: process.command, pid: process.pid, projectPath: projectPath)
            let canDiscoverByAttach = selectedDevice.supportsAttachDiscovery
            guard canDiscoverByAttach || serviceURL != nil else {
                unsupportedRuns += 1
                continue
            }

            let customTargetPath = targetPath(in: process.command)
            let targetID = "\(projectPath)|\(selectedDevice.id)|\(customTargetPath ?? "lib/main.dart")"
                + "|\(serviceInfoPath(in: process.command) ?? "")"
            targetsByID[targetID] = FlutterTarget(
                id: targetID,
                name: "\(URL(fileURLWithPath: projectPath).lastPathComponent) · \(selectedDevice.name)",
                projectPath: projectPath,
                deviceID: selectedDevice.id,
                targetPath: customTargetPath,
                vmServiceURL: serviceURL,
                mode: canDiscoverByAttach ? .attach : .attachURL
            )
        }

        return DiscoverySnapshot(
            devices: devices,
            targets: targetsByID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            skippedRuns: skippedRuns,
            unsupportedRuns: unsupportedRuns,
            ideManagedRuns: ideManagedRuns
        )
    }

    private static func runFlutter(_ executable: String, arguments: [String]) throws -> String {
        let resolvedExecutable = FlutterExecutableLocator.resolve(executable)
        return try run(executable: "/usr/bin/env", arguments: [resolvedExecutable] + arguments)
    }

    private static func run(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()

        let readGroup = DispatchGroup()
        let outputLock = NSLock()
        var outputData = Data()
        var errorData = Data()
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
            outputLock.lock()
            outputData = data
            outputLock.unlock()
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = standardError.fileHandleForReading.readDataToEndOfFile()
            outputLock.lock()
            errorData = data
            outputLock.unlock()
            readGroup.leave()
        }

        process.waitUntilExit()
        readGroup.wait()
        guard process.terminationStatus == 0 else {
            outputLock.lock()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? ""
            outputLock.unlock()
            throw DiscoveryError.commandFailed(executable, process.terminationStatus, errorMessage)
        }
        outputLock.lock()
        let result = String(data: outputData, encoding: .utf8) ?? ""
        outputLock.unlock()
        return result
    }

    private static func parseProcess(_ line: String) -> (pid: Int32, command: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.firstIndex(where: \.isWhitespace),
              let pid = Int32(trimmed[..<separator].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let command = trimmed[separator...].trimmingCharacters(in: .whitespaces)
        return (pid, command)
    }

    private static func isFlutterRun(_ command: String) -> Bool {
        let arguments = command.split(whereSeparator: \.isWhitespace).map(String.init)
        let toolIndex = arguments.firstIndex {
            URL(fileURLWithPath: $0).lastPathComponent == "flutter_tools.snapshot"
        } ?? arguments.firstIndex {
            URL(fileURLWithPath: $0).lastPathComponent == "flutter"
        }
        guard let toolIndex else { return false }
        let subcommandIndex = arguments.index(after: toolIndex)
        return subcommandIndex < arguments.endIndex && arguments[subcommandIndex] == "run"
    }

    private static func isMachineMode(_ command: String) -> Bool {
        command.split(whereSeparator: \.isWhitespace).contains {
            $0 == "--machine" || $0.hasPrefix("--machine=")
        }
    }

    private static func deviceID(in command: String) -> String? {
        let arguments = command.split(whereSeparator: \.isWhitespace).map(String.init)
        for index in arguments.indices {
            if arguments[index] == "-d" || arguments[index] == "--device-id" {
                let nextIndex = arguments.index(after: index)
                if nextIndex < arguments.endIndex { return arguments[nextIndex] }
            }
            if arguments[index].hasPrefix("--device-id=") {
                return String(arguments[index].dropFirst("--device-id=".count))
            }
        }
        return nil
    }

    private static func targetPath(in command: String) -> String? {
        let arguments = command.split(whereSeparator: \.isWhitespace).map(String.init)
        for index in arguments.indices {
            if arguments[index] == "-t" || arguments[index] == "--target" {
                let nextIndex = arguments.index(after: index)
                if nextIndex < arguments.endIndex { return arguments[nextIndex] }
            }
            if arguments[index].hasPrefix("--target=") {
                return String(arguments[index].dropFirst("--target=".count))
            }
            if arguments[index].hasPrefix("-t"), arguments[index].count > 2 {
                return String(arguments[index].dropFirst(2))
            }
        }
        return nil
    }

    private static func serviceInfoPath(in command: String) -> String? {
        let arguments = command.split(whereSeparator: \.isWhitespace).map(String.init)

        for index in arguments.indices {
            if arguments[index] == "--vmservice-out-file" {
                let nextIndex = arguments.index(after: index)
                if nextIndex < arguments.endIndex {
                    return arguments[nextIndex]
                }
            }
            if arguments[index].hasPrefix("--vmservice-out-file=") {
                return String(arguments[index].dropFirst("--vmservice-out-file=".count))
            }
        }
        return nil
    }

    private static func vmServiceURL(in command: String, pid: Int32, projectPath: String) -> String? {
        guard let configuredPath = serviceInfoPath(in: command) else { return nil }
        let serviceInfoURL = URL(fileURLWithPath: configuredPath, relativeTo: URL(fileURLWithPath: projectPath))
            .standardizedFileURL

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: serviceInfoURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              let startedAt = processStartDate(pid: pid),
              modifiedAt >= startedAt.addingTimeInterval(-5),
              let contents = try? String(contentsOf: serviceInfoURL, encoding: .utf8) else {
            return nil
        }

        let rawURL: String
        if let json = contents.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
           let uri = object["uri"] as? String {
            rawURL = uri
        } else {
            rawURL = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let url = URL(string: rawURL),
              ["ws", "wss", "http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil,
              url.port != nil else {
            return nil
        }
        return rawURL
    }

    private static func processStartDate(pid: Int32) -> Date? {
        guard let output = try? run(
            executable: "/bin/ps",
            arguments: ["-o", "lstart=", "-p", String(pid)]
        ) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter.date(from: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func workingDirectory(of pid: Int32) throws -> String {
        let output = try run(
            executable: "/usr/sbin/lsof",
            arguments: ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]
        )
        guard let pathLine = output.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("n") }) else {
            throw DiscoveryError.workingDirectoryUnavailable(pid)
        }
        return String(pathLine.dropFirst())
    }
}

private enum DiscoveryError: LocalizedError {
    case invalidDeviceList
    case commandFailed(String, Int32, String)
    case workingDirectoryUnavailable(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidDeviceList:
            return "Flutter returned an invalid device list."
        case let .commandFailed(command, status, output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(command) exited with status \(status)."
                : "\(command) exited with status \(status): \(detail)"
        case let .workingDirectoryUnavailable(pid):
            return "Could not read the working directory for Flutter process \(pid)."
        }
    }
}

struct VSCodeDebugTarget: Identifiable, Hashable, Sendable {
    let id: String
    let sessionID: String
    let socketPath: String
    let name: String
    let workspace: String
}

private struct VSCodeBridgeSnapshot: Sendable {
    let targets: [VSCodeDebugTarget]
    let status: String
}

private enum VSCodeBridge {
    private struct Descriptor: Decodable {
        let socketPath: String
        let pid: Int32
    }

    static func discover() -> (targets: [VSCodeDebugTarget], status: String) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mustel/Bridge", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return ([], "Install and enable the VS Code bridge extension to control IDE sessions.")
        }
        let descriptorURLs: [URL]
        do {
            descriptorURLs = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }
        } catch {
            return ([], "Could not read the VS Code bridge directory: \(error.localizedDescription)")
        }

        guard !descriptorURLs.isEmpty else {
            return ([], "Install and enable the VS Code bridge extension to control IDE sessions.")
        }

        var targets: [VSCodeDebugTarget] = []
        var errors: [String] = []
        for descriptorURL in descriptorURLs {
            do {
                let descriptorData = try Data(contentsOf: descriptorURL)
                let descriptor = try JSONDecoder().decode(Descriptor.self, from: descriptorData)
                let expectedSocketPath = "/tmp/mustel-\(getuid())-\(descriptor.pid).sock"
                guard descriptor.socketPath == expectedSocketPath else {
                    throw BridgeError.invalidSocketPath
                }
                if kill(descriptor.pid, 0) != 0, errno == ESRCH {
                    do {
                        try FileManager.default.removeItem(at: descriptorURL)
                    } catch {
                        errors.append("Could not remove stale bridge descriptor: \(error.localizedDescription)")
                    }
                    continue
                }
                let response = try send(
                    ["type": "list"],
                    to: descriptor.socketPath,
                    timeout: 2
                )
                guard response["ok"] as? Bool == true,
                      let rawSessions = response["sessions"] as? [[String: Any]] else {
                    throw BridgeError.invalidResponse(response["error"] as? String ?? "Invalid session list.")
                }
                for session in rawSessions {
                    guard let sessionID = session["id"] as? String,
                          let name = session["name"] as? String else {
                        continue
                    }
                    let workspace = session["workspace"] as? String ?? ""
                    targets.append(VSCodeDebugTarget(
                        id: "\(descriptor.socketPath)|\(sessionID)",
                        sessionID: sessionID,
                        socketPath: descriptor.socketPath,
                        name: name,
                        workspace: workspace
                    ))
                }
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        let sortedTargets = targets.sorted {
            let left = $0.workspace + $0.name
            let right = $1.workspace + $1.name
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
        if !errors.isEmpty {
            return (sortedTargets, "VS Code bridge error: \(errors.joined(separator: " "))")
        }
        return sortedTargets.isEmpty
            ? ([], "VS Code bridge connected; no Dart/Flutter debug sessions are active.")
            : (sortedTargets, "\(sortedTargets.count) VS Code debug session(s) available.")
    }

    static func perform(_ command: String, on target: VSCodeDebugTarget) throws {
        let response = try send(
            ["type": "command", "sessionId": target.sessionID, "command": command],
            to: target.socketPath,
            timeout: 120
        )
        guard response["ok"] as? Bool == true else {
            throw BridgeError.commandFailed(response["error"] as? String ?? "VS Code rejected the command.")
        }
    }

    private static func send(
        _ object: [String: String],
        to socketPath: String,
        timeout: Int
    ) throws -> [String: Any] {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw BridgeError.socketOperation("Could not create a local bridge connection.")
        }
        defer { Darwin.close(descriptor) }

        var receiveTimeout = timeval(tv_sec: timeout, tv_usec: 0)
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &receiveTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            throw BridgeError.socketOperation("Could not configure a local bridge timeout.")
        }
        var sendTimeout = receiveTimeout
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &sendTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            throw BridgeError.socketOperation("Could not configure a local bridge timeout.")
        }
        var noSignal: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw BridgeError.socketOperation("Could not configure a local bridge connection.")
        }

        let pathBytes = Array(socketPath.utf8)
        var address = sockaddr_un()
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw BridgeError.invalidSocketPath
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { storage in
            storage.initializeMemory(as: UInt8.self, repeating: 0)
            storage.copyBytes(from: pathBytes)
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw BridgeError.socketOperation("Could not connect to the VS Code bridge.")
        }

        var requestData = try JSONSerialization.data(withJSONObject: object)
        requestData.append(10)
        try requestData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: sent),
                    bytes.count - sent,
                    0
                )
                guard count > 0 else {
                    throw BridgeError.socketOperation("Could not send a request to the VS Code bridge.")
                }
                sent += count
            }
        }

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while responseData.count < 65_536 {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            guard count > 0 else {
                throw BridgeError.socketOperation("The VS Code bridge returned no response.")
            }
            responseData.append(contentsOf: buffer.prefix(count))
            if responseData.contains(10) {
                break
            }
        }
        guard let newline = responseData.firstIndex(of: 10),
              let response = try JSONSerialization.jsonObject(with: responseData[..<newline]) as? [String: Any] else {
            throw BridgeError.invalidResponse("The VS Code bridge returned invalid data.")
        }
        return response
    }
}

private enum BridgeError: LocalizedError {
    case invalidSocketPath
    case invalidResponse(String)
    case commandFailed(String)
    case socketOperation(String)

    var errorDescription: String? {
        switch self {
        case .invalidSocketPath:
            return "The VS Code bridge descriptor contains an invalid socket path."
        case let .invalidResponse(message):
            return message
        case let .commandFailed(message):
            return message
        case let .socketOperation(message):
            return message
        }
    }
}

private final class LineBuffer {
    private let lock = NSLock()
    private var data = Data()

    func append(_ bytes: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        data.append(bytes)
        var lines: [String] = []
        while let newline = data.firstIndex(of: 10) {
            let line = data[..<newline]
            data.removeSubrange(...newline)
            if let string = String(data: line, encoding: .utf8) {
                lines.append(string)
            }
        }
        return lines
    }
}

@MainActor
final class FlutterSession: ObservableObject, Identifiable {
    nonisolated let id: String
    let target: FlutterTarget

    @Published private(set) var status = "Connecting…"
    @Published private(set) var isReady = false
    @Published private(set) var isRunning = false
    @Published private(set) var appID: String?
    @Published private(set) var diagnostics: [String] = []

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var nextRequestID = 1
    private var pendingRequests: [String: String] = [:]
    private var wasStoppedByUser = false
    private var lastErrorLine: String?

    init(target: FlutterTarget, flutterExecutable: String) {
        id = target.id
        self.target = target
        connect(using: flutterExecutable)
    }

    func connect(using flutterExecutable: String) {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var arguments = [FlutterExecutableLocator.resolve(flutterExecutable, projectPath: target.projectPath)]
        switch target.mode {
        case .attach:
            arguments.append(contentsOf: ["attach", "--machine", "--no-dds", "--device-id", target.deviceID])
        case .attachURL:
            arguments.append(contentsOf: ["attach", "--machine", "--no-dds", "--device-id", target.deviceID])
            if let vmServiceURL = target.vmServiceURL {
                arguments.append(contentsOf: ["--debug-uri", vmServiceURL])
            }
        case .run:
            arguments.append(contentsOf: ["run", "--machine", "--device-id", target.deviceID])
        }
        if let targetPath = target.targetPath {
            arguments.append(contentsOf: ["--target", targetPath])
        }
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: target.projectPath, isDirectory: true)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let stdoutBuffer = LineBuffer()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            guard !bytes.isEmpty else { return }
            for line in stdoutBuffer.append(bytes) {
                Task { @MainActor [weak self] in self?.handleProtocolLine(line) }
            }
        }

        let stderrBuffer = LineBuffer()
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            guard !bytes.isEmpty else { return }
            for line in stderrBuffer.append(bytes) {
                Task { @MainActor [weak self] in self?.handleErrorLine(line) }
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.handleProcessExit(code: process.terminationStatus)
            }
        }

        do {
            try process.run()
            isRunning = true
            status = "Attaching…"
        } catch {
            status = "Could not start Flutter: \(error.localizedDescription)"
        }
    }

    func stop() {
        wasStoppedByUser = true
        isReady = false
        status = "Disconnected"
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }

    func hotReload() {
        sendRestart(full: false)
    }

    func hotRestart() {
        sendRestart(full: true)
    }

    private func sendRestart(full: Bool) {
        guard isReady, let appID else {
            status = "Waiting for the Flutter app…"
            return
        }

        let requestID = nextRequestID
        nextRequestID += 1
        let label = full ? "Hot restart" : "Hot reload"
        pendingRequests[String(requestID)] = label
        guard send([
            "id": requestID,
            "method": "app.restart",
            "params": ["appId": appID, "fullRestart": full]
        ]) else {
            pendingRequests.removeValue(forKey: String(requestID))
            return
        }
        status = "\(label) requested"
    }

    private func send(_ object: [String: Any]) -> Bool {
        do {
            let data = try JSONSerialization.data(withJSONObject: [object])
            var line = data
            line.append(10)
            try input.fileHandleForWriting.write(contentsOf: line)
            return true
        } catch {
            status = "Could not send command: \(error.localizedDescription)"
            return false
        }
    }

    private func handleProtocolLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return
        }
        let messages: [[String: Any]]
        if let array = json as? [[String: Any]] {
            messages = array
        } else if let message = json as? [String: Any] {
            messages = [message]
        } else {
            return
        }

        for message in messages {
            if let event = message["event"] as? String {
                let params = message["params"] as? [String: Any] ?? [:]
                switch event {
                case "app.start":
                    appID = params["appId"] as? String
                    isReady = false
                    status = appID == nil ? "Flutter did not provide an app ID" : "Starting connection…"
                case "app.started":
                    if appID != nil {
                        isReady = true
                        status = "Connected"
                    }
                case "app.stop":
                    isReady = false
                    if let error = params["error"] {
                        let description = describe(error)
                        status = "Attach failed: \(brief(description))"
                        appendDiagnostic("Attach failed: \(description)")
                        if let trace = params["trace"] as? String {
                            appendDiagnostic(trace)
                        }
                    } else {
                        status = "Flutter app stopped"
                    }
                default:
                    break
                }
            } else if let rawID = message["id"] {
                let requestID = String(describing: rawID)
                guard let label = pendingRequests.removeValue(forKey: requestID) else {
                    if let error = message["error"] {
                        let description = describe(error)
                        appendDiagnostic("Flutter error: \(description)")
                        if !isReady {
                            status = brief(description)
                        }
                    }
                    continue
                }
                if let error = message["error"] {
                    let description = describe(error)
                    status = "\(label) failed: \(brief(description))"
                    appendDiagnostic("\(label) failed: \(description)")
                } else {
                    status = "\(label) complete"
                }
            }
        }
    }

    private func handleErrorLine(_ line: String) {
        guard !line.isEmpty else { return }
        lastErrorLine = line
        appendDiagnostic(line)
        status = brief(line)
    }

    private func appendDiagnostic(_ line: String) {
        diagnostics.append(line)
        if diagnostics.count > 6 {
            diagnostics.removeFirst(diagnostics.count - 6)
        }
    }

    private func describe(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return String(describing: value)
    }

    private func brief(_ message: String) -> String {
        let oneLine = message.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard oneLine.count > 140 else { return oneLine }
        return "\(oneLine.prefix(137))…"
    }

    private func handleProcessExit(code: Int32) {
        isRunning = false
        isReady = false
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        if !wasStoppedByUser {
            let processName = target.mode == .run ? "Flutter run" : "Flutter attach"
            status = lastErrorLine ?? "\(processName) exited (code \(code))"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [FlutterSession] = []
    @Published private(set) var vscodeSessions: [VSCodeDebugTarget] = []
    @Published private(set) var devices: [FlutterDeviceInfo] = []
    @Published var selectedDeviceID = ""
    @Published private(set) var discoveryStatus = "Looking for Flutter runs…"
    @Published private(set) var isDiscovering = false
    @Published private(set) var vscodeBridgeStatus = "Connecting to the VS Code bridge…"
    @Published private(set) var vscodeCommandStatuses: [String: String] = [:]
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginMessage: String?
    @Published var flutterExecutable: String {
        didSet {
            UserDefaults.standard.set(flutterExecutable, forKey: "flutterExecutable")
        }
    }

    private var discoveryTimer: Timer?
    private var vscodeBridgeTimer: Timer?
    private var isRefreshingVSCodeSessions = false

    init() {
        flutterExecutable = UserDefaults.standard.string(forKey: "flutterExecutable")
            ?? FlutterExecutableLocator.resolve("flutter")
        refreshLaunchAtLoginState()
        refreshDiscovery()
        refreshVSCodeSessions()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDiscovery() }
        }
        vscodeBridgeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshVSCodeSessions() }
        }
    }

    func refreshDiscovery() {
        guard !isDiscovering else { return }
        isDiscovering = true
        let executable = flutterExecutable

        Task {
            let outcome: (DiscoverySnapshot?, String?) = await Task.detached(priority: .utility) {
                do {
                    return (try FlutterRunDiscovery.discover(flutterExecutable: executable), nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            finishDiscovery(snapshot: outcome.0, errorMessage: outcome.1)
        }
    }

    func reconnect(_ session: FlutterSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].stop()
        sessions[index] = FlutterSession(target: session.target, flutterExecutable: flutterExecutable)
    }

    func launch(projectPath: String, deviceID: String, targetPath: String) -> String? {
        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("pubspec.yaml").path) else {
            return "Choose a Flutter project folder containing pubspec.yaml."
        }
        guard let device = devices.first(where: { $0.id == deviceID && $0.isSupported }) else {
            return "Choose an available Flutter device."
        }

        let customTarget = targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = FlutterTarget(
            id: "run:\(UUID().uuidString)",
            name: "\(projectURL.lastPathComponent) · \(device.name)",
            projectPath: projectURL.path,
            deviceID: device.id,
            targetPath: customTarget.isEmpty ? nil : customTarget,
            vmServiceURL: nil,
            mode: .run
        )
        sessions.append(FlutterSession(target: target, flutterExecutable: flutterExecutable))
        return nil
    }

    func remove(_ session: FlutterSession) {
        session.stop()
        sessions.removeAll { $0.id == session.id }
    }

    func runVSCodeCommand(_ command: String, on target: VSCodeDebugTarget) {
        let label = command == "hotRestart" ? "Hot restart" : "Hot reload"
        vscodeCommandStatuses[target.id] = "\(label) requested…"
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try VSCodeBridge.perform(command, on: target)
                }.value
                vscodeCommandStatuses[target.id] = "\(label) complete"
            } catch {
                vscodeCommandStatuses[target.id] = "\(label) failed: \(error.localizedDescription)"
            }
        }
    }

    func shutdown() {
        discoveryTimer?.invalidate()
        vscodeBridgeTimer?.invalidate()
        sessions.forEach { $0.stop() }
    }

    var canConfigureLaunchAtLogin: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.bundleIdentifier == "com.ionutdanielfagadau.Mustel"
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        guard canConfigureLaunchAtLogin else {
            throw LaunchAtLoginError.appBundleRequired
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        refreshLaunchAtLoginState()
    }

    private func refreshLaunchAtLoginState() {
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            launchAtLoginEnabled = true
            launchAtLoginMessage = nil
        case .requiresApproval:
            launchAtLoginEnabled = true
            launchAtLoginMessage = "Enable Mustel in System Settings > General > Login Items."
        case .notRegistered:
            launchAtLoginEnabled = false
            launchAtLoginMessage = nil
        case .notFound:
            launchAtLoginEnabled = false
            launchAtLoginMessage = "Install the app bundle before enabling launch at login."
        @unknown default:
            launchAtLoginEnabled = false
            launchAtLoginMessage = "Could not determine launch-at-login status."
        }
    }

    func refreshVSCodeSessions() {
        guard !isRefreshingVSCodeSessions else { return }
        isRefreshingVSCodeSessions = true
        Task {
            let result = await Task.detached(priority: .utility) {
                let discovered = VSCodeBridge.discover()
                return VSCodeBridgeSnapshot(targets: discovered.targets, status: discovered.status)
            }.value
            isRefreshingVSCodeSessions = false
            vscodeSessions = result.targets
            vscodeBridgeStatus = result.status
            let activeIDs = Set(result.targets.map(\.id))
            vscodeCommandStatuses = vscodeCommandStatuses.filter { activeIDs.contains($0.key) }
        }
    }

    private func finishDiscovery(snapshot: DiscoverySnapshot?, errorMessage: String?) {
        isDiscovering = false
        guard let snapshot else {
            discoveryStatus = "Discovery failed: \(errorMessage ?? "Unknown error")"
            return
        }

        devices = snapshot.devices.filter(\.isSupported).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if !devices.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = devices.first?.id ?? ""
        }

        let managedSessions = sessions.filter { $0.target.mode == .run }
        let discoveredTargets = snapshot.targets.filter { target in
            !managedSessions.contains {
                $0.target.projectPath == target.projectPath
                    && $0.target.deviceID == target.deviceID
                    && $0.target.targetPath == target.targetPath
            }
        }
        let existingAttachSessions = Dictionary(
            uniqueKeysWithValues: sessions
                .filter { $0.target.mode == .attach }
                .map { ($0.id, $0) }
        )
        let reusableAttachIDs = Set(discoveredTargets.compactMap { target -> String? in
            guard let existing = existingAttachSessions[target.id],
                  existing.target.vmServiceURL == target.vmServiceURL else {
                return nil
            }
            return target.id
        })
        for session in sessions where session.target.mode == .attach && !reusableAttachIDs.contains(session.id) {
            session.stop()
        }
        sessions = managedSessions + discoveredTargets.map { target in
            existingAttachSessions[target.id].flatMap {
                reusableAttachIDs.contains(target.id) ? $0 : nil
            }
                ?? FlutterSession(target: target, flutterExecutable: flutterExecutable)
        }

        if discoveredTargets.isEmpty, snapshot.ideManagedRuns > 0 {
            discoveryStatus = "\(snapshot.ideManagedRuns) IDE-managed Flutter run(s) found. They are not attached by a second Flutter tool; VS Code sessions appear in the bridge below."
        } else if discoveredTargets.isEmpty, snapshot.unsupportedRuns > 0 {
            discoveryStatus = "Existing desktop/web runs need a VM Service info file (`--vmservice-out-file`) to attach automatically."
        } else if discoveredTargets.isEmpty {
            discoveryStatus = snapshot.skippedRuns == 0
                ? "No attachable Flutter runs found."
                : "\(snapshot.skippedRuns) Flutter run session(s) could not be identified."
        } else {
            discoveryStatus = "\(discoveredTargets.count) existing Flutter target(s) detected."
        }
        if snapshot.skippedRuns > 0 {
            discoveryStatus += " \(snapshot.skippedRuns) run(s) skipped; use `flutter run -d <device>` if the device is ambiguous."
        }
        if !discoveredTargets.isEmpty, snapshot.unsupportedRuns > 0 {
            discoveryStatus += " Or launch desktop/web projects here."
        }
        if !discoveredTargets.isEmpty, snapshot.ideManagedRuns > 0 {
            discoveryStatus += " Skipped \(snapshot.ideManagedRuns) IDE-managed run(s) to avoid conflicting with their IDE."
        }
    }
}

private enum LaunchAtLoginError: LocalizedError {
    case appBundleRequired

    var errorDescription: String? {
        "Launch at login is available after installing Mustel as a macOS app."
    }
}

struct SessionRow: View {
    @ObservedObject var session: FlutterSession
    let onReconnect: () -> Void
    let onStop: () -> Void
    let onRemove: () -> Void
    @State private var showsDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.target.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if session.target.mode == .run, session.isRunning {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                    }
                    .help("Stop app")
                } else if session.target.mode == .run {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                    }
                    .help("Remove finished run")
                } else if !session.isRunning {
                    Button(action: onReconnect) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reconnect")
                }
                Button(action: session.hotReload) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .help("Hot reload")
                .disabled(!session.isReady)

                Button(action: session.hotRestart) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Hot restart")
                .disabled(!session.isReady)
            }
            Text(session.target.mode == .run ? "Started by Mustel" : "Discovered existing run")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(session.status)
                .font(.caption)
                .foregroundStyle(session.isReady ? Color.green : Color.secondary)
                .lineLimit(2)
            if let appID = session.appID {
                Text("App ID: \(appID)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !session.diagnostics.isEmpty {
                DisclosureGroup("Details (\(session.diagnostics.count))", isExpanded: $showsDiagnostics) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(session.diagnostics.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct VSCodeSessionRow: View {
    let target: VSCodeDebugTarget
    let status: String?
    let onHotReload: () -> Void
    let onHotRestart: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(target.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(target.workspace.isEmpty
                     ? "Dart debug session"
                     : URL(fileURLWithPath: target.workspace).path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let status {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(status.contains("failed") ? Color.red : Color.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Button(action: onHotReload) {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .help("Hot reload in VS Code")
            .disabled(status?.hasSuffix("requested…") == true)
            Button(action: onHotRestart) {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("Hot restart in VS Code")
            .disabled(status?.hasSuffix("requested…") == true)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var isLaunching = false
    @State private var projectPath = ""
    @State private var targetPath = ""
    @State private var launchError: String?
    @State private var launchAtLoginError: String?
    @State private var isSettingsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mustel")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    isLaunching.toggle()
                    launchError = nil
                } label: {
                    Image(systemName: isLaunching ? "xmark" : "plus")
                }
                .help(isLaunching ? "Cancel launch" : "Launch a Flutter project")
                Button(action: model.refreshDiscovery) {
                    if model.isDiscovering {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(model.isDiscovering)
                .help("Discover running Flutter apps")
            }

            Text(model.discoveryStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("VS Code")
                        .font(.headline)
                    Spacer()
                    Button(action: model.refreshVSCodeSessions) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh VS Code sessions")
                }
                Text(model.vscodeBridgeStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !model.vscodeSessions.isEmpty {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(model.vscodeSessions) { target in
                                VSCodeSessionRow(
                                    target: target,
                                    status: model.vscodeCommandStatuses[target.id],
                                    onHotReload: {
                                        model.runVSCodeCommand("hotReload", on: target)
                                    },
                                    onHotRestart: {
                                        model.runVSCodeCommand("hotRestart", on: target)
                                    }
                                )
                            }
                        }
                    }
                    .frame(height: min(CGFloat(model.vscodeSessions.count) * 58, 174))
                }
            }

            if model.sessions.count == 1, let session = model.sessions.first {
                SessionRow(
                    session: session,
                    onReconnect: { model.reconnect(session) },
                    onStop: { session.stop() },
                    onRemove: { model.remove(session) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if model.sessions.count > 1 {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.sessions) { session in
                            SessionRow(
                                session: session,
                                onReconnect: { model.reconnect(session) },
                                onStop: { session.stop() },
                                onRemove: { model.remove(session) }
                            )
                        }
                    }
                }
                .frame(height: min(CGFloat(model.sessions.count) * 150, 300))
            } else if !model.isDiscovering && !isLaunching {
                Text("Mobile runs are discovered automatically. For existing desktop/web runs, use `--vmservice-out-file`; or launch from here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.isDiscovering && model.sessions.isEmpty && !isLaunching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning active Flutter runs…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isLaunching {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Launch Flutter app")
                        .font(.headline)
                    HStack {
                        Text(projectPath.isEmpty
                             ? "Choose a project folder…"
                             : URL(fileURLWithPath: projectPath).lastPathComponent)
                            .lineLimit(1)
                            .foregroundStyle(projectPath.isEmpty ? Color.secondary : Color.primary)
                        Spacer()
                        Button("Choose…", action: chooseProject)
                    }
                    Picker("Device", selection: $model.selectedDeviceID) {
                        ForEach(model.devices) { device in
                            Text("\(device.name) (\(device.targetPlatform))")
                                .tag(device.id)
                        }
                    }
                    .disabled(model.devices.isEmpty)
                    TextField("Entrypoint (optional, e.g. lib/main_dev.dart)", text: $targetPath)
                        .textFieldStyle(.roundedBorder)
                    if model.devices.isEmpty {
                        Text("No supported Flutter devices found yet. Refresh or check the Flutter executable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let launchError {
                        Text(launchError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Spacer()
                        Button("Run") { launchProject() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(projectPath.isEmpty || model.selectedDeviceID.isEmpty)
                    }
                }
            } else if !model.sessions.isEmpty {
                Divider()
            }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    isSettingsExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSettingsExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                        Text("Settings")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isSettingsExpanded {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Flutter executable")
                                .font(.caption.weight(.medium))
                            TextField("flutter or absolute path", text: $model.flutterExecutable)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                            Text("If Flutter is not found, enter its absolute path.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(
                                "Launch at login",
                                isOn: Binding(
                                    get: { model.launchAtLoginEnabled },
                                    set: { enabled in
                                        do {
                                            try model.setLaunchAtLogin(enabled)
                                            launchAtLoginError = nil
                                        } catch {
                                            launchAtLoginError = error.localizedDescription
                                        }
                                    }
                                )
                            )
                            .toggleStyle(.checkbox)
                            .disabled(!model.canConfigureLaunchAtLogin)
                            if let message = launchAtLoginError ?? model.launchAtLoginMessage {
                                Text(message)
                                    .font(.caption2)
                                    .foregroundStyle(launchAtLoginError == nil ? Color.secondary : Color.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Flutter project"
        panel.prompt = "Choose Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            projectPath = url.path
            launchError = nil
        }
    }

    private func launchProject() {
        if let error = model.launch(
            projectPath: projectPath,
            deviceID: model.selectedDeviceID,
            targetPath: targetPath
        ) {
            launchError = error
            return
        }
        isLaunching = false
        launchError = nil
        targetPath = ""
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = AppModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        let imageURL = Bundle.main.url(forResource: "MustelMenuBar", withExtension: "png")
            ?? Bundle.module.url(forResource: "MustelMenuBar", withExtension: "png")
        if let imageURL, let image = NSImage(contentsOf: imageURL) {
            image.size = NSSize(width: 28, height: 16)
            image.isTemplate = true
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Mustel")
        }
        button.toolTip = "Mustel"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: ContentView(model: model))
        popover.contentSize = NSSize(width: 380, height: 400)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] event in
            self?.closePopoverIfClickedOutside()
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopoverIfClickedOutside()
            }
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let quitItem = NSMenuItem(
                title: "Quit Mustel",
                action: #selector(quitApplication),
                keyEquivalent: ""
            )
            quitItem.target = self
            menu.addItem(quitItem)
            menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: button.bounds.minY), in: button)
        } else if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    func popoverWillShow(_ notification: Notification) {
        guard let button = statusItem.button,
              let statusBarWindow = button.window,
              let popoverWindow = popover.contentViewController?.view.window else {
            return
        }

        let buttonFrame = statusBarWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var popoverFrame = popoverWindow.frame
        popoverFrame.origin.x = buttonFrame.midX - popoverFrame.width / 2
        popoverFrame.origin.y = buttonFrame.minY - popoverFrame.height
        popoverWindow.setFrame(popoverFrame, display: true)
    }

    private func closePopoverIfClickedOutside() {
        guard popover.isShown else { return }
        let mouseLocation = NSEvent.mouseLocation
        if let popoverWindow = popover.contentViewController?.view.window,
           popoverWindow.frame.contains(mouseLocation) {
            return
        }
        if let button = statusItem.button,
           let buttonWindow = button.window {
            let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonFrame.contains(mouseLocation) {
                return
            }
        }
        popover.performClose(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
    }
}

@main
enum MustelApp {
    @MainActor private static var appDelegate: AppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        application.delegate = delegate
        application.run()
    }
}
