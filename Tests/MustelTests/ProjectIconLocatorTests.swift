import AppKit
import Foundation
import XCTest
@testable import Mustel

final class ProjectIconLocatorTests: XCTestCase {
    func testUsesLargestAvailableDefaultAssetForPlatform() throws {
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let assets = project.appendingPathComponent("ios/Runner/Assets.xcassets/AppIcon.appiconset")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("""
        {"images": [
          {"size": "20x20", "scale": "2x", "filename": "small.png"},
          {"size": "1024x1024", "scale": "1x", "filename": "missing.png"},
          {"size": "60x60", "scale": "3x", "filename": "large.png"},
          {"size": "1024x1024", "scale": "1x", "filename": "dark.png",
           "appearances": [{"appearance": "luminosity", "value": "dark"}]}
        ]}
        """.utf8).write(to: assets.appendingPathComponent("Contents.json"))
        for name in ["small.png", "large.png", "dark.png"] {
            try Data().write(to: assets.appendingPathComponent(name))
        }

        XCTAssertEqual(
            ProjectIconLocator.locate(projectPath: project.path, platformHint: "iPhone"),
            assets.appendingPathComponent("large.png")
        )
    }

    func testPrefersMatchingPlatformAndFallsBackWhenAbsent() throws {
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let android = project.appendingPathComponent("android/app/src/main/res/mipmap-xhdpi")
        let web = project.appendingPathComponent("web/icons")
        try FileManager.default.createDirectory(at: android, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
        let androidIcon = android.appendingPathComponent("ic_launcher.png")
        let webIcon = web.appendingPathComponent("Icon-512.png")
        try Data().write(to: androidIcon)
        try Data().write(to: webIcon)

        XCTAssertEqual(ProjectIconLocator.locate(projectPath: project.path, platformHint: "Chrome"), webIcon)
        XCTAssertEqual(
            ProjectIconLocator.locate(projectPath: project.path, platformHint: "Android")?.resolvingSymlinksInPath(),
            androidIcon.resolvingSymlinksInPath()
        )
        try FileManager.default.removeItem(at: androidIcon)
        XCTAssertNil(ProjectIconLocator.locate(projectPath: project.path, platformHint: "Android"))
        XCTAssertNil(ProjectIconLocator.locate(projectPath: "", platformHint: ""))
    }

    func testFindsUniqueAppInsideWorkspace() throws {
        let workspace = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let app = workspace.appendingPathComponent("packages/app")
        let icon = app.appendingPathComponent("web/icons/Icon-512.png")
        try FileManager.default.createDirectory(at: icon.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("name: app\n".utf8).write(to: app.appendingPathComponent("pubspec.yaml"))
        try Data().write(to: icon)

        XCTAssertEqual(
            ProjectIconLocator.locate(projectPath: workspace.path, platformHint: "Chrome")?.resolvingSymlinksInPath(),
            icon.resolvingSymlinksInPath()
        )
    }

    func testDoesNotChooseBetweenMultipleAppsInWorkspace() throws {
        let workspace = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: workspace) }
        for name in ["first", "second"] {
            let app = workspace.appendingPathComponent(name)
            let icon = app.appendingPathComponent("web/icons/Icon-512.png")
            try FileManager.default.createDirectory(at: icon.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("name: app\n".utf8).write(to: app.appendingPathComponent("pubspec.yaml"))
            try Data().write(to: icon)
        }

        XCTAssertNil(ProjectIconLocator.locate(projectPath: workspace.path, platformHint: "Chrome"))
    }

    func testPrefersMatchingPlatformOverOtherAppsInWorkspace() throws {
        let workspace = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let app = workspace.appendingPathComponent("app")
        let assets = app.appendingPathComponent("macos/Runner/Assets.xcassets/AppIcon.appiconset")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("name: app\n".utf8).write(to: app.appendingPathComponent("pubspec.yaml"))
        try Data("{\"images\":[{\"filename\":\"icon.png\"}]}".utf8)
            .write(to: assets.appendingPathComponent("Contents.json"))
        let icon = assets.appendingPathComponent("icon.png")
        try Data().write(to: icon)

        let example = workspace.appendingPathComponent("plugins/example")
        let web = example.appendingPathComponent("web/icons")
        try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
        try Data("name: example\n".utf8).write(to: example.appendingPathComponent("pubspec.yaml"))
        try Data().write(to: web.appendingPathComponent("Icon-512.png"))

        XCTAssertEqual(
            ProjectIconLocator.locate(projectPath: workspace.path, platformHint: "DEV (macOS)")?
                .resolvingSymlinksInPath(),
            icon.resolvingSymlinksInPath()
        )
    }

    func testFindsAndroidManifestIconInFlavorResources() throws {
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let main = project.appendingPathComponent("android/app/src/main")
        let resources = project.appendingPathComponent("android/app/src/dev/res/mipmap-xhdpi")
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data("""
        <manifest xmlns:android="http://schemas.android.com/apk/res/android">
          <application android:icon="@mipmap/brand_icon"/>
        </manifest>
        """.utf8).write(to: main.appendingPathComponent("AndroidManifest.xml"))
        let icon = resources.appendingPathComponent("brand_icon.png")
        try Data().write(to: icon)

        XCTAssertEqual(
            ProjectIconLocator.locate(projectPath: project.path, platformHint: "Android")?.resolvingSymlinksInPath(),
            icon.resolvingSymlinksInPath()
        )
    }

    func testFindsWebManifestIconWithCustomName() throws {
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let web = project.appendingPathComponent("web")
        try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
        try Data("""
        {"icons":[{"src":"logo.png","sizes":"512x512"}]}
        """.utf8).write(to: web.appendingPathComponent("manifest.json"))
        let icon = web.appendingPathComponent("logo.png")
        try Data().write(to: icon)

        XCTAssertEqual(ProjectIconLocator.locate(projectPath: project.path, platformHint: "Chrome"), icon)
    }

    func testFindsAlternativeAppleIconSet() throws {
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let assets = project.appendingPathComponent("ios/Runner/Assets.xcassets/AppIconDev.appiconset")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("{\"images\":[{\"filename\":\"brand.png\"}]}".utf8)
            .write(to: assets.appendingPathComponent("Contents.json"))
        let icon = assets.appendingPathComponent("brand.png")
        try Data().write(to: icon)

        XCTAssertEqual(
            ProjectIconLocator.locate(projectPath: project.path, platformHint: "iPhone")?.resolvingSymlinksInPath(),
            icon.resolvingSymlinksInPath()
        )
    }

    func testBundledFlutterFallbackIsDecodable() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "FlutterDefaultIcon", withExtension: "png"))
        XCTAssertNotNil(NSImage(contentsOf: url))
    }
}
