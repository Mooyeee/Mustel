import Foundation
import XCTest
@testable import Mustel

enum TestError: LocalizedError {
    case failed(String)
    case missingResponse(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message), let .missingResponse(message):
            return message
        }
    }
}

struct FakeProcessRunner: ProcessRunning {
    var outputs: [String: String] = [:]
    var failures: [String: String] = [:]

    func run(executable: String, arguments: [String]) throws -> String {
        let key = ([executable] + arguments).joined(separator: " ")
        if let failure = failures[key] {
            throw TestError.failed(failure)
        }
        guard let output = outputs[key] else {
            throw TestError.missingResponse("No fake response for: \(key)")
        }
        return output
    }
}

final class FakeSessionService: FlutterSessionServicing {
    var onEvent: ((FlutterSessionEvent) -> Void)?
    private(set) var isStarted = false
    private(set) var isStopped = false
    private(set) var sentPayloads: [[String: Any]] = []
    var startError: Error?
    var sendError: Error?

    func start() throws {
        if let startError { throw startError }
        isStarted = true
    }

    func stop() {
        isStopped = true
    }

    func send(_ payload: [String: Any]) throws {
        if let sendError { throw sendError }
        sentPayloads.append(payload)
    }

    func emit(_ event: FlutterSessionEvent) {
        onEvent?(event)
    }
}

final class FakeLaunchAtLogin: LaunchAtLoginControlling {
    var canConfigure = true
    var isEnabled = false
    var message: String?
    var error: Error?

    func setEnabled(_ enabled: Bool) throws {
        if let error { throw error }
        isEnabled = enabled
    }
}

@MainActor
struct FakeProjectPicker: ProjectPicking {
    let path: String?

    func chooseProject() -> String? {
        path
    }
}

struct FakeDiscoveryService: FlutterDiscovering {
    var snapshot: DiscoverySnapshot

    func discover(flutterExecutable: String) throws -> DiscoverySnapshot {
        snapshot
    }
}

struct FakeBridge: VSCodeBridging {
    var discovery = VSCodeBridgeDiscovery(targets: [], status: "IDE bridge connected.")
    var performError: Error?

    func discover() -> VSCodeBridgeDiscovery {
        discovery
    }

    func perform(_ command: VSCodeCommand, on target: VSCodeDebugTarget) throws {
        if let performError { throw performError }
    }
}

struct FakeIDEBridgeProbe: IDEBridgeProbing {
    var installed = false

    func isInstalled() -> Bool {
        installed
    }
}

func makeTemporaryProject() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MustelTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data("name: test\n".utf8).write(to: url.appendingPathComponent("pubspec.yaml"))
    return url
}

func makeTarget(
    mode: FlutterSessionMode = .attach,
    projectPath: String = "/tmp/App",
    deviceID: String = "device-1"
) -> FlutterTarget {
    FlutterTarget(
        id: "target-1",
        name: "App · Device",
        projectPath: projectPath,
        deviceID: deviceID,
        targetPath: nil,
        vmServiceURL: nil,
        mode: mode
    )
}

@MainActor
func settle() async {
    await Task.yield()
    await Task.yield()
}
