import Darwin
import Foundation
import XCTest
@testable import Mustel

final class VSCodeBridgeClientTests: XCTestCase {
    private var bridgeDirectory: URL!
    private var server: UnixSocketServer?

    private var socketPath: String {
        "/tmp/mustel-\(getuid())-\(ProcessInfo.processInfo.processIdentifier).sock"
    }

    override func setUp() {
        super.setUp()
        bridgeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MustelBridgeClient-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: bridgeDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        server?.stop()
        server = nil
        try? FileManager.default.removeItem(at: bridgeDirectory)
        bridgeDirectory = nil
        super.tearDown()
    }

    func testDiscoversSessions() throws {
        server = try UnixSocketServer(
            path: socketPath,
            response: #"{"ok":true,"sessions":[{"id":"s1","name":"DEV","workspace":"/workspace","projectPath":"/workspace/apps/app","type":"dart"}]}"#
        )
        try writeDescriptor(pid: ProcessInfo.processInfo.processIdentifier)

        let discovery = client.discover()

        XCTAssertEqual(discovery.targets.count, 1)
        XCTAssertEqual(discovery.targets.first?.sessionID, "s1")
        XCTAssertEqual(discovery.targets.first?.name, "DEV")
        XCTAssertEqual(discovery.targets.first?.workspace, "/workspace")
        XCTAssertEqual(discovery.targets.first?.projectPath, "/workspace/apps/app")
        XCTAssertEqual(discovery.status, "1 IDE run session(s) available.")
    }

    func testPerformsCommand() throws {
        server = try UnixSocketServer(path: socketPath, response: #"{"ok":true}"#)
        try writeDescriptor(pid: ProcessInfo.processInfo.processIdentifier)
        let target = VSCodeDebugTarget(
            id: "id",
            sessionID: "s1",
            socketPath: socketPath,
            name: "DEV",
            workspace: "/workspace"
        )

        XCTAssertNoThrow(try client.perform(.hotReload, on: target))
    }

    func testReportsBridgeCommandFailure() throws {
        server = try UnixSocketServer(path: socketPath, response: #"{"ok":false,"error":"nope"}"#)
        try writeDescriptor(pid: ProcessInfo.processInfo.processIdentifier)
        let target = VSCodeDebugTarget(
            id: "id",
            sessionID: "s1",
            socketPath: socketPath,
            name: "DEV",
            workspace: "/workspace"
        )

        XCTAssertThrowsError(try client.perform(.hotRestart, on: target)) { error in
            guard let bridgeError = error as? BridgeError,
                  case let .commandFailed(message) = bridgeError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "nope")
        }
    }

    func testRejectsUnexpectedSocketPath() throws {
        try writeDescriptor(
            pid: ProcessInfo.processInfo.processIdentifier,
            socketPath: "/tmp/not-the-expected.sock"
        )

        let discovery = client.discover()

        XCTAssertTrue(discovery.targets.isEmpty)
        XCTAssertTrue(discovery.status.contains("invalid socket path"))
    }

    func testRemovesStaleDescriptor() throws {
        let stalePID: Int32 = 2_000_000_000
        try writeDescriptor(pid: stalePID)
        let descriptor = bridgeDirectory.appendingPathComponent("extension-\(stalePID).json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: descriptor.path))

        let discovery = client.discover()

        XCTAssertTrue(discovery.targets.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: descriptor.path))
    }

    func testReportsMissingBridgeDirectory() {
        try? FileManager.default.removeItem(at: bridgeDirectory)

        let discovery = client.discover()

        XCTAssertTrue(discovery.targets.isEmpty)
        XCTAssertTrue(discovery.status.contains("Install and enable"))
    }

    private var client: VSCodeBridgeClient {
        VSCodeBridgeClient(bridgeDirectory: bridgeDirectory)
    }

    private func writeDescriptor(
        pid: Int32,
        socketPath: String? = nil
    ) throws {
        let descriptor = [
            "socketPath": socketPath ?? self.socketPath,
            "pid": pid
        ] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: descriptor)
        try data.write(to: bridgeDirectory.appendingPathComponent("extension-\(pid).json"))
    }
}

private final class UnixSocketServer {
    private let descriptor: Int32
    private let path: String
    private let response: String
    private let queue = DispatchQueue(label: "Mustel.UnixSocketServer")

    init(path: String, response: String) throws {
        self.path = path
        self.response = response
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw TestError.failed("Could not create test socket")
        }

        unlink(path)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { storage in
            storage.initializeMemory(as: UInt8.self, repeating: 0)
            storage.copyBytes(from: bytes)
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0, listen(descriptor, 1) == 0 else {
            close(descriptor)
            throw TestError.failed("Could not bind test socket")
        }

        let serverDescriptor = descriptor
        let reply = response
        queue.async {
            let connection = accept(serverDescriptor, nil, nil)
            guard connection >= 0 else { return }
            defer { close(connection) }

            var buffer = [UInt8](repeating: 0, count: 4096)
            _ = recv(connection, &buffer, buffer.count, 0)
            let data = Data((reply + "\n").utf8)
            data.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                _ = send(connection, baseAddress, bytes.count, 0)
            }
        }
    }

    func stop() {
        close(descriptor)
        unlink(path)
    }
}
