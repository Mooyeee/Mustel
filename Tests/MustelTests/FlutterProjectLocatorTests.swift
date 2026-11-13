import Foundation
import XCTest
@testable import Mustel

final class FlutterProjectLocatorTests: XCTestCase {
    func testResolvesUniqueAppInPubWorkspace() throws {
        let workspace = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try writePubspec(
            to: workspace,
            contents: """
            name: my_workspace
            environment:
              sdk: ^3.6.0
            workspace:
              - apps/my_app
              - packages/shared
            """
        )
        let app = workspace.appendingPathComponent("apps/my_app")
        try createFlutterApp(at: app, name: "my_app")
        try createPackage(at: workspace.appendingPathComponent("packages/shared"), name: "shared")

        XCTAssertEqual(
            FlutterProjectLocator.resolveAppPath(workspace.path),
            app.standardizedFileURL.path
        )
        XCTAssertEqual(FlutterProjectLocator.appName(for: workspace.path), "my_app")
    }

    func testTargetPathChoosesBetweenWorkspaceMembers() throws {
        let workspace = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try writePubspec(
            to: workspace,
            contents: """
            name: my_workspace
            workspace:
              - apps/first
              - apps/second
            """
        )
        try createFlutterApp(at: workspace.appendingPathComponent("apps/first"), name: "first")
        try createFlutterApp(at: workspace.appendingPathComponent("apps/second"), name: "second")

        XCTAssertNil(FlutterProjectLocator.resolveAppPath(workspace.path))
        XCTAssertNil(FlutterProjectLocator.appName(for: workspace.path))
        XCTAssertEqual(
            FlutterProjectLocator.resolveAppPath(
                workspace.path,
                targetPath: "apps/second/lib/main.dart"
            ),
            workspace.appendingPathComponent("apps/second").standardizedFileURL.path
        )
        XCTAssertEqual(
            FlutterProjectLocator.appName(for: workspace.path, targetPath: "apps/first/lib/main.dart"),
            "first"
        )
    }

    func testWorkspaceRootCanAlsoBeTheApp() throws {
        let workspace = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try writePubspec(
            to: workspace,
            contents: """
            name: root_app
            workspace:
              - packages/shared
            """
        )
        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent("macos"),
            withIntermediateDirectories: true
        )
        try createPackage(at: workspace.appendingPathComponent("packages/shared"), name: "shared")

        XCTAssertEqual(
            FlutterProjectLocator.resolveAppPath(workspace.path),
            workspace.standardizedFileURL.path
        )
        XCTAssertEqual(FlutterProjectLocator.appName(for: workspace.path), "root_app")
    }

    func testParsesQuotedMembersAndComments() throws {
        let workspace = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try writePubspec(
            to: workspace,
            contents: """
            name: "my_workspace" # the workspace package
            workspace:
              - "apps/my_app" # the app
              - 'packages/shared'
            """
        )
        let app = workspace.appendingPathComponent("apps/my_app")
        try createFlutterApp(at: app, name: "my_app")
        try createPackage(at: workspace.appendingPathComponent("packages/shared"), name: "shared")

        XCTAssertEqual(FlutterProjectLocator.appName(for: workspace.path), "my_app")
    }

    func testIgnoresPluginPackagesInWorkspace() throws {
        let workspace = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try writePubspec(
            to: workspace,
            contents: """
            name: my_workspace
            workspace:
              - apps/my_app
              - packages/my_plugin
            """
        )
        let app = workspace.appendingPathComponent("apps/my_app")
        try createFlutterApp(at: app, name: "my_app")
        try writePubspec(
            to: workspace.appendingPathComponent("packages/my_plugin"),
            contents: """
            name: my_plugin
            resolution: workspace
            dependencies:
              flutter:
                sdk: flutter
            flutter:
              plugin:
                platforms:
                  ios:
                    pluginClass: MyPlugin
            """
        )

        XCTAssertEqual(FlutterProjectLocator.appName(for: workspace.path), "my_app")
    }

    func testNormalProjectResolvesToItself() throws {
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }

        XCTAssertEqual(
            FlutterProjectLocator.resolveAppPath(project.path),
            project.standardizedFileURL.path
        )
        XCTAssertEqual(FlutterProjectLocator.appName(for: project.path), "test")
    }

    private func writePubspec(to directory: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: directory.appendingPathComponent("pubspec.yaml"))
    }

    private func createFlutterApp(at directory: URL, name: String) throws {
        try writePubspec(
            to: directory,
            contents: """
            name: \(name)
            resolution: workspace
            dependencies:
              flutter:
                sdk: flutter
            """
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("web"),
            withIntermediateDirectories: true
        )
    }

    private func createPackage(at directory: URL, name: String) throws {
        try writePubspec(
            to: directory,
            contents: """
            name: \(name)
            resolution: workspace
            """
        )
    }
}
