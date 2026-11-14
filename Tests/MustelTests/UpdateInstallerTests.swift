import XCTest
@testable import Mustel

final class UpdateInstallerTests: XCTestCase {
    private var workDirectory: URL!

    override func setUp() {
        super.setUp()
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MustelInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDirectory)
        workDirectory = nil
        super.tearDown()
    }

    func testRejectsAPathThatIsNotAnAppBundle() async {
        let installer = UpdateInstaller(bundleURL: workDirectory.appendingPathComponent("not-an-app"))

        do {
            try await installer.install(archiveURL: workDirectory, release: makeRelease())
            XCTFail("Expected notAppBundle")
        } catch let error as UpdateError {
            XCTAssertEqual(error, .notAppBundle)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsArchiveWithoutAnApp() async throws {
        let installedApp = try makeInstalledApp()
        let staging = workDirectory.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("not an app".utf8).write(to: staging.appendingPathComponent("readme.txt"))
        let archive = try zip(staging)

        let installer = UpdateInstaller(bundleURL: installedApp)

        do {
            try await installer.install(archiveURL: archive, release: makeRelease())
            XCTFail("Expected invalidBundle")
        } catch let error as UpdateError {
            XCTAssertEqual(error, .invalidBundle)
        }
    }

    func testRejectsBundleIdentifierMismatch() async throws {
        let installedApp = try makeInstalledApp()
        let download = try makeDownloadedApp(bundleIdentifier: "com.example.other", version: "0.1.7")
        let archive = try zip(download)
        let installer = UpdateInstaller(bundleURL: installedApp)

        do {
            try await installer.install(archiveURL: archive, release: makeRelease())
            XCTFail("Expected invalidBundle")
        } catch let error as UpdateError {
            XCTAssertEqual(error, .invalidBundle)
        }
    }

    func testRejectsVersionMismatch() async throws {
        let installedApp = try makeInstalledApp()
        let download = try makeDownloadedApp(version: "0.1.6")
        let archive = try zip(download)
        let installer = UpdateInstaller(bundleURL: installedApp)

        do {
            try await installer.install(archiveURL: archive, release: makeRelease())
            XCTFail("Expected versionMismatch")
        } catch let error as UpdateError {
            XCTAssertEqual(error, .versionMismatch(expected: "0.1.7", actual: "0.1.6"))
        }
    }

    func testRejectsUnsignedBundle() async throws {
        let installedApp = try makeInstalledApp()
        let download = try makeDownloadedApp()
        let archive = try zip(download)
        let installer = UpdateInstaller(bundleURL: installedApp)

        do {
            try await installer.install(archiveURL: archive, release: makeRelease())
            XCTFail("Expected invalidSignature")
        } catch let error as UpdateError {
            guard case .invalidSignature = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeInstalledApp() throws -> URL {
        let app = workDirectory.appendingPathComponent("Installed.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        return app
    }

    private func makeDownloadedApp(
        bundleIdentifier: String = AppIdentity.bundleIdentifier,
        version: String = "0.1.7"
    ) throws -> URL {
        let app = workDirectory.appendingPathComponent("Downloaded.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleShortVersionString": version
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    private func zip(_ item: URL) throws -> URL {
        let archive = workDirectory.appendingPathComponent("update-\(UUID().uuidString).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", item.path, archive.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return archive
    }

    private func makeRelease() -> UpdateRelease {
        UpdateRelease(
            version: AppVersion("0.1.7")!,
            tagName: "v0.1.7",
            name: "Mustel 0.1.7",
            notes: "",
            pageURL: URL(string: "https://github.com/Mooyeee/mustel/releases/tag/v0.1.7")!,
            assetURL: URL(string: "https://example.com/Mustel.zip"),
            assetName: "Mustel.zip",
            assetSize: 1
        )
    }
}
