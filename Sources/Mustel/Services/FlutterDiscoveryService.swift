import Foundation

protocol FlutterDiscovering: Sendable {
    func discover(flutterExecutable: String) throws -> DiscoverySnapshot
}

struct FlutterDiscoveryService: FlutterDiscovering {
    private let processRunner: ProcessRunning

    init(processRunner: ProcessRunning = SystemProcessRunner()) {
        self.processRunner = processRunner
    }

    func discover(flutterExecutable: String) throws -> DiscoverySnapshot {
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

        let processList = try processRunner.run(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,command="]
        )
        var targetsByID: [String: FlutterTarget] = [:]
        var skippedRuns = 0
        var unsupportedRuns = 0
        var ideManagedRuns = 0

        for line in processList.split(whereSeparator: \.isNewline) {
            guard let process = Self.parseProcess(String(line)),
                  Self.isFlutterRun(process.command) else {
                continue
            }
            guard !Self.isMachineMode(process.command) else {
                ideManagedRuns += 1
                continue
            }

            let requestedDeviceID = Self.deviceID(in: process.command)
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

            let customTargetPath = Self.targetPath(in: process.command)
            let targetID = "\(projectPath)|\(selectedDevice.id)|\(customTargetPath ?? "lib/main.dart")"
                + "|\(Self.serviceInfoPath(in: process.command) ?? "")"
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

    private func runFlutter(_ executable: String, arguments: [String]) throws -> String {
        let resolvedExecutable = FlutterExecutableLocator.resolve(executable)
        return try processRunner.run(executable: "/usr/bin/env", arguments: [resolvedExecutable] + arguments)
    }

    static func parseProcess(_ line: String) -> (pid: Int32, command: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.firstIndex(where: \.isWhitespace),
              let pid = Int32(trimmed[..<separator].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let command = trimmed[separator...].trimmingCharacters(in: .whitespaces)
        return (pid, command)
    }

    static func isFlutterRun(_ command: String) -> Bool {
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

    static func isMachineMode(_ command: String) -> Bool {
        command.split(whereSeparator: \.isWhitespace).contains {
            $0 == "--machine" || $0.hasPrefix("--machine=")
        }
    }

    static func deviceID(in command: String) -> String? {
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

    static func targetPath(in command: String) -> String? {
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

    static func serviceInfoPath(in command: String) -> String? {
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

    func vmServiceURL(in command: String, pid: Int32, projectPath: String) -> String? {
        guard let configuredPath = Self.serviceInfoPath(in: command) else { return nil }
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

    func processStartDate(pid: Int32) -> Date? {
        guard let output = try? processRunner.run(
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

    func workingDirectory(of pid: Int32) throws -> String {
        let output = try processRunner.run(
            executable: "/usr/sbin/lsof",
            arguments: ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]
        )
        guard let pathLine = output.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("n") }) else {
            throw DiscoveryError.workingDirectoryUnavailable(pid)
        }
        return String(pathLine.dropFirst())
    }
}
