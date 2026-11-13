import Darwin
import Foundation

protocol VSCodeBridging: Sendable {
    func discover() -> VSCodeBridgeDiscovery
    func perform(_ command: VSCodeCommand, on target: VSCodeDebugTarget) throws
}

struct VSCodeBridgeClient: VSCodeBridging {
    private struct Descriptor: Decodable {
        let socketPath: String
        let pid: Int32
    }

    func discover() -> VSCodeBridgeDiscovery {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mustel/Bridge", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return VSCodeBridgeDiscovery(
                targets: [],
                status: "Install and enable the Mustel bridge for VS Code or IntelliJ to control IDE sessions."
            )
        }
        let descriptorURLs: [URL]
        do {
            descriptorURLs = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }
        } catch {
            return VSCodeBridgeDiscovery(
                targets: [],
                status: "Could not read the IDE bridge directory: \(error.localizedDescription)"
            )
        }

        guard !descriptorURLs.isEmpty else {
            return VSCodeBridgeDiscovery(
                targets: [],
                status: "Install and enable the Mustel bridge for VS Code or IntelliJ to control IDE sessions."
            )
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
                    let projectPath = session["projectPath"] as? String
                    targets.append(VSCodeDebugTarget(
                        id: "\(descriptor.socketPath)|\(sessionID)",
                        sessionID: sessionID,
                        socketPath: descriptor.socketPath,
                        name: name,
                        workspace: workspace,
                        projectPath: projectPath
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
            return VSCodeBridgeDiscovery(
                targets: sortedTargets,
                status: "IDE bridge error: \(errors.joined(separator: " "))"
            )
        }
        return VSCodeBridgeDiscovery(
            targets: sortedTargets,
            status: sortedTargets.isEmpty
                ? "IDE bridge connected; no Flutter run sessions are active."
                : "\(sortedTargets.count) IDE run session(s) available."
        )
    }

    func perform(_ command: VSCodeCommand, on target: VSCodeDebugTarget) throws {
        let response = try send(
            ["type": "command", "sessionId": target.sessionID, "command": command.rawValue],
            to: target.socketPath,
            timeout: 120
        )
        guard response["ok"] as? Bool == true else {
            throw BridgeError.commandFailed(response["error"] as? String ?? "The IDE bridge rejected the command.")
        }
    }

    private func send(
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
            throw BridgeError.socketOperation("Could not connect to the IDE bridge.")
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
                    throw BridgeError.socketOperation("Could not send a request to the IDE bridge.")
                }
                sent += count
            }
        }

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while responseData.count < 65_536 {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            guard count > 0 else {
                throw BridgeError.socketOperation("The IDE bridge returned no response.")
            }
            responseData.append(contentsOf: buffer.prefix(count))
            if responseData.contains(10) {
                break
            }
        }
        guard let newline = responseData.firstIndex(of: 10),
              let response = try JSONSerialization.jsonObject(with: responseData[..<newline]) as? [String: Any] else {
            throw BridgeError.invalidResponse("The IDE bridge returned invalid data.")
        }
        return response
    }
}
