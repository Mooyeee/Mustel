import XCTest
@testable import Mustel

final class IDEBridgeProbeTests: XCTestCase {
    private var home: URL!

    override func setUp() {
        super.setUp()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("MustelIDEProbe-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
        home = nil
        super.tearDown()
    }

    func testDetectsVisualStudioCodeVersionFromPackageJSON() throws {
        let extensionDirectory = home
            .appendingPathComponent(".vscode/extensions/local.mustel-vscode-0.1.0")
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        try Data(#"{"name":"mustel-vscode","version":"0.1.1"}"#.utf8)
            .write(to: extensionDirectory.appendingPathComponent("package.json"))

        let versions = IDEBridgeProbe(homeDirectory: home).installedVersions()

        XCTAssertTrue(versions.isInstalled)
        XCTAssertEqual(versions.visualStudioCode, AppVersion("0.1.1"))
        XCTAssertNil(versions.intellij)
    }

    func testFallsBackToVisualStudioCodeFolderVersion() throws {
        let extensionDirectory = home
            .appendingPathComponent(".vscode-insiders/extensions/local.mustel-vscode-0.2.0")
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)

        let versions = IDEBridgeProbe(homeDirectory: home).installedVersions()

        XCTAssertEqual(versions.visualStudioCode, AppVersion("0.2.0"))
    }

    func testDetectsIntelliJPluginVersionFromJarName() throws {
        let lib = home
            .appendingPathComponent(
                "Library/Application Support/JetBrains/IntelliJIdea2024.1/plugins/mustel-intellij/lib"
            )
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        try Data().write(to: lib.appendingPathComponent("mustel-intellij-0.1.1.jar"))

        let versions = IDEBridgeProbe(homeDirectory: home).installedVersions()

        XCTAssertTrue(versions.isInstalled)
        XCTAssertEqual(versions.intellij, AppVersion("0.1.1"))
        XCTAssertNil(versions.visualStudioCode)
    }

    func testReportsNothingWhenNoBridgeIsInstalled() {
        let versions = IDEBridgeProbe(homeDirectory: home).installedVersions()

        XCTAssertFalse(versions.isInstalled)
        XCTAssertNil(versions.visualStudioCode)
        XCTAssertNil(versions.intellij)
    }
}
