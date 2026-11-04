import XCTest
@testable import Mustel

final class FlutterSessionServiceTests: XCTestCase {
    func testAttachArguments() {
        let target = FlutterTarget(
            id: "id",
            name: "App",
            projectPath: "/tmp/App",
            deviceID: "device-1",
            targetPath: "lib/main_dev.dart",
            vmServiceURL: nil,
            mode: .attach
        )

        XCTAssertEqual(
            FlutterSessionService.arguments(for: target, flutterExecutable: "/custom/flutter"),
            [
                "/custom/flutter",
                "attach", "--machine", "--no-dds", "--device-id", "device-1",
                "--target", "lib/main_dev.dart"
            ]
        )
    }

    func testAttachURLArgumentsIncludeDebugURI() {
        let target = FlutterTarget(
            id: "id",
            name: "App",
            projectPath: "/tmp/App",
            deviceID: "macos",
            targetPath: nil,
            vmServiceURL: "ws://127.0.0.1:1234/ws",
            mode: .attachURL
        )

        XCTAssertEqual(
            FlutterSessionService.arguments(for: target, flutterExecutable: "/custom/flutter"),
            [
                "/custom/flutter",
                "attach", "--machine", "--no-dds", "--device-id", "macos",
                "--debug-uri", "ws://127.0.0.1:1234/ws"
            ]
        )
    }

    func testRunArguments() {
        let target = FlutterTarget(
            id: "id",
            name: "App",
            projectPath: "/tmp/App",
            deviceID: "macos",
            targetPath: nil,
            vmServiceURL: nil,
            mode: .run
        )

        XCTAssertEqual(
            FlutterSessionService.arguments(for: target, flutterExecutable: "/custom/flutter"),
            ["/custom/flutter", "run", "--machine", "--device-id", "macos"]
        )
    }
}
