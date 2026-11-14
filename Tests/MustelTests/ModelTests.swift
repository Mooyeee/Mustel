import XCTest
@testable import Mustel

final class ModelTests: XCTestCase {
    func testVSCodeDebugTargetFallsBackToWorkspace() {
        let target = VSCodeDebugTarget(
            id: "id",
            sessionID: "session",
            socketPath: "/tmp/socket",
            name: "DEV",
            workspace: "/workspace"
        )

        XCTAssertEqual(target.projectPath, "/workspace")
    }

    func testVSCodeDebugTargetKeepsExplicitProjectPath() {
        let target = VSCodeDebugTarget(
            id: "id",
            sessionID: "session",
            socketPath: "/tmp/socket",
            name: "DEV",
            workspace: "/workspace",
            projectPath: "/workspace/apps/app"
        )

        XCTAssertEqual(target.projectPath, "/workspace/apps/app")
    }

    func testUpdateReleaseDisplayVersion() {
        let release = UpdateRelease(
            version: AppVersion("0.1.7")!,
            tagName: "v0.1.7",
            name: "Mustel",
            notes: "",
            pageURL: URL(string: "https://example.com")!,
            assetURL: nil,
            assetName: nil,
            assetSize: nil
        )

        XCTAssertEqual(release.displayVersion, "v0.1.7")
    }

    func testUpdateAssetParsesVersionFromName() {
        let asset = UpdateAsset(
            name: "mustel-vscode-0.1.1.vsix",
            url: URL(string: "https://example.com/mustel-vscode-0.1.1.vsix")!,
            size: 1
        )

        XCTAssertEqual(asset.version, AppVersion("0.1.1"))
    }
}
