import XCTest
@testable import Mustel

final class SupportTests: XCTestCase {
    func testLineBufferAccumulatesChunks() {
        let buffer = LineBuffer()

        XCTAssertEqual(buffer.append(Data("hello".utf8)), [])
        XCTAssertEqual(buffer.append(Data(" world\nsecond".utf8)), ["hello world"])
        XCTAssertEqual(buffer.append(Data(" line\n\nthird".utf8)), ["second line", ""])
        XCTAssertEqual(buffer.append(Data("\n".utf8)), ["third"])
    }

    func testLineBufferIgnoresInvalidUTF8() {
        let buffer = LineBuffer()
        let invalid = Data([0xFF, 0x0A])

        XCTAssertEqual(buffer.append(invalid), [])
        XCTAssertEqual(buffer.append(Data("ok\n".utf8)), ["ok"])
    }

    func testDiscoveryErrorDescriptions() {
        XCTAssertEqual(
            DiscoveryError.invalidDeviceList.errorDescription,
            "Flutter returned an invalid device list."
        )
        XCTAssertEqual(
            DiscoveryError.commandFailed("flutter devices", 1, "  boom  ").errorDescription,
            "flutter devices exited with status 1: boom"
        )
        XCTAssertEqual(
            DiscoveryError.commandFailed("flutter devices", 1, " \n").errorDescription,
            "flutter devices exited with status 1."
        )
        XCTAssertEqual(
            DiscoveryError.workingDirectoryUnavailable(42).errorDescription,
            "Could not read the working directory for Flutter process 42."
        )
    }

    func testBridgeErrorDescriptions() {
        XCTAssertEqual(
            BridgeError.invalidSocketPath.errorDescription,
            "The IDE bridge descriptor contains an invalid socket path."
        )
        XCTAssertEqual(BridgeError.invalidResponse("bad").errorDescription, "bad")
        XCTAssertEqual(BridgeError.commandFailed("failed").errorDescription, "failed")
        XCTAssertEqual(BridgeError.socketOperation("closed").errorDescription, "closed")
    }

    func testLaunchAtLoginErrorDescription() {
        XCTAssertEqual(
            LaunchAtLoginError.appBundleRequired.errorDescription,
            "Launch at login is available after installing Mustel as a macOS app."
        )
    }
}
