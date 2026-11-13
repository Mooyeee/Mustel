import XCTest
@testable import Mustel

@MainActor
final class UpdateViewModelTests: XCTestCase {
    func testNewerReleaseIsAvailable() async {
        let release = makeRelease("0.2.0")
        let model = makeModel(release: release)

        model.checkForUpdates()

        await waitUntil { model.state == .available(release) }
        XCTAssertEqual(model.availableRelease, release)
    }

    func testCurrentVersionIsUpToDate() async {
        let model = makeModel(release: makeRelease("0.1.6"))

        model.checkForUpdates()

        await waitUntil { model.state == .upToDate }
    }

    func testNoPublishedReleases() async {
        let model = makeModel(release: nil)

        model.checkForUpdates()

        await waitUntil { model.state == .noReleases }
    }

    func testFailedCheckShowsError() async {
        let model = makeModel(error: .httpStatus(500))

        model.checkForUpdates()

        await waitUntil {
            if case .failed = model.state { return true }
            return false
        }
        guard case let .failed(message) = model.state else {
            return XCTFail("Expected a failure")
        }
        XCTAssertEqual(message, "GitHub returned HTTP 500.")
    }

    func testInstallDownloadsAndInstallsUpdate() async {
        let release = makeRelease("0.2.0")
        let installer = FakeUpdateInstaller()
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mustel-\(UUID().uuidString).zip")
        let model = makeModel(
            release: release,
            archiveURL: archiveURL,
            installer: installer
        )

        model.checkForUpdates()
        await waitUntil { model.state == .available(release) }

        model.installAvailableUpdate()
        await waitUntil { await installer.didInstall() }

        let installedArchiveURL = await installer.installedArchiveURL
        let installedRelease = await installer.installedRelease
        XCTAssertEqual(installedArchiveURL, archiveURL)
        XCTAssertEqual(installedRelease, release)
    }

    func testInstallFailureIsReported() async {
        let release = makeRelease("0.2.0")
        let installer = FakeUpdateInstaller(error: .installFailed("denied"))
        let model = makeModel(
            release: release,
            archiveURL: FileManager.default.temporaryDirectory.appendingPathComponent("update.zip"),
            installer: installer
        )

        model.checkForUpdates()
        await waitUntil { model.state == .available(release) }

        model.installAvailableUpdate()
        await waitUntil {
            if case .failed = model.state { return true }
            return false
        }
        guard case let .failed(message) = model.state else {
            return XCTFail("Expected a failure")
        }
        XCTAssertEqual(message, "Could not install the update: denied")
    }

    func testCheckRunsOnlyOnceAutomatically() async {
        let model = makeModel(release: makeRelease("0.2.0"))

        model.checkForUpdatesIfNeeded()
        await waitUntil { model.state == .available(makeRelease("0.2.0")) }

        model.checkForUpdatesIfNeeded()
        XCTAssertEqual(model.state, .available(makeRelease("0.2.0")))
    }

    func testDetectsIDEBridgeUpdatesFromReleaseAssets() async {
        let release = makeRelease(
            "0.1.6",
            vscodeVersion: "0.2.0",
            intellijVersion: "0.2.1"
        )
        let model = makeModel(release: release)
        model.updateInstalledIDEVersions(
            IDEBridgeVersions(
                isInstalled: true,
                visualStudioCode: AppVersion("0.1.0"),
                intellij: AppVersion("0.1.0")
            )
        )

        model.checkForUpdates()
        await waitUntil { model.state == .upToDate }

        XCTAssertEqual(model.visualStudioCodeUpdate?.version, AppVersion("0.2.0"))
        XCTAssertEqual(model.intellijUpdate?.version, AppVersion("0.2.1"))
    }

    func testDoesNotReportIDEUpdatesWhenInstalledVersionIsCurrent() async {
        let release = makeRelease(
            "0.1.6",
            vscodeVersion: "0.2.0",
            intellijVersion: "0.2.0"
        )
        let model = makeModel(release: release)
        model.updateInstalledIDEVersions(
            IDEBridgeVersions(
                isInstalled: true,
                visualStudioCode: AppVersion("0.2.0"),
                intellij: AppVersion("0.2.0")
            )
        )

        model.checkForUpdates()
        await waitUntil { model.state == .upToDate }

        XCTAssertNil(model.visualStudioCodeUpdate)
        XCTAssertNil(model.intellijUpdate)
    }

    private func makeModel(
        release: UpdateRelease? = nil,
        archiveURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent("update.zip"),
        installer: UpdateInstalling = FakeUpdateInstaller(),
        error: UpdateError? = nil
    ) -> UpdateViewModel {
        UpdateViewModel(
            currentVersion: AppVersion("0.1.6"),
            service: FakeUpdateService(release: release, archiveURL: archiveURL, error: error),
            installer: installer,
            terminate: {}
        )
    }

    private func makeRelease(
        _ version: String,
        vscodeVersion: String? = nil,
        intellijVersion: String? = nil
    ) -> UpdateRelease {
        let base = URL(string: "https://github.com/Mooyeee/mustel/releases/tag/v\(version)")!
        return UpdateRelease(
            version: AppVersion(version)!,
            tagName: "v\(version)",
            name: "Mustel \(version)",
            notes: "",
            pageURL: base,
            assetURL: URL(string: "https://example.com/Mustel.zip"),
            assetName: "Mustel.zip",
            assetSize: 1_000,
            visualStudioCodeAsset: vscodeVersion.flatMap { version in
                UpdateAsset(
                    name: "mustel-vscode-\(version).vsix",
                    url: URL(string: "https://example.com/mustel-vscode-\(version).vsix")!,
                    size: 100
                )
            },
            intellijAsset: intellijVersion.flatMap { version in
                UpdateAsset(
                    name: "mustel-intellij-\(version).zip",
                    url: URL(string: "https://example.com/mustel-intellij-\(version).zip")!,
                    size: 100
                )
            }
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for update state")
    }
}

private struct FakeUpdateService: UpdateServicing {
    let release: UpdateRelease?
    let archiveURL: URL
    let error: UpdateError?

    init(release: UpdateRelease?, archiveURL: URL, error: UpdateError? = nil) {
        self.release = release
        self.archiveURL = archiveURL
        self.error = error
    }

    func latestRelease() async throws -> UpdateRelease? {
        if let error { throw error }
        return release
    }

    func download(
        _ release: UpdateRelease,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        if let error { throw error }
        progress(0.5)
        progress(1)
        return archiveURL
    }
}

private actor FakeUpdateInstaller: UpdateInstalling {
    private(set) var installedArchiveURL: URL?
    private(set) var installedRelease: UpdateRelease?
    private let error: UpdateError?

    init(error: UpdateError? = nil) {
        self.error = error
    }

    func install(archiveURL: URL, release: UpdateRelease) async throws {
        if let error { throw error }
        installedArchiveURL = archiveURL
        installedRelease = release
    }

    func didInstall() -> Bool {
        installedArchiveURL != nil
    }
}
