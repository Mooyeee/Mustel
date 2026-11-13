import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class UpdateViewModel {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case noReleases
        case available(UpdateRelease)
        case downloading(Double)
        case installing
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastCheckedAt: Date?
    private(set) var latestRelease: UpdateRelease?
    private(set) var installedIDEVersions = IDEBridgeVersions()

    let currentVersion: AppVersion?

    @ObservationIgnored private let service: UpdateServicing
    @ObservationIgnored private let installer: UpdateInstalling
    @ObservationIgnored private let terminate: @MainActor () -> Void
    @ObservationIgnored private var didCheckAutomatically = false

    init(
        currentVersion: AppVersion? = AppIdentity.version,
        service: UpdateServicing = GitHubUpdateService(),
        installer: UpdateInstalling = UpdateInstaller(),
        terminate: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.currentVersion = currentVersion
        self.service = service
        self.installer = installer
        self.terminate = terminate
    }

    var currentVersionText: String {
        currentVersion.map { "v\($0)" } ?? "Development build"
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing:
            return true
        case .idle, .upToDate, .noReleases, .available, .failed:
            return false
        }
    }

    var availableRelease: UpdateRelease? {
        if case let .available(release) = state { return release }
        return nil
    }

    var visualStudioCodeUpdate: UpdateAsset? {
        guard let release = latestRelease,
              let asset = release.visualStudioCodeAsset,
              let installedVersion = installedIDEVersions.visualStudioCode else {
            return nil
        }
        let availableVersion = asset.version ?? release.version
        return availableVersion > installedVersion ? asset : nil
    }

    var intellijUpdate: UpdateAsset? {
        guard let release = latestRelease,
              let asset = release.intellijAsset,
              let installedVersion = installedIDEVersions.intellij else {
            return nil
        }
        let availableVersion = asset.version ?? release.version
        return availableVersion > installedVersion ? asset : nil
    }

    func updateInstalledIDEVersions(_ versions: IDEBridgeVersions) {
        guard installedIDEVersions != versions else { return }
        installedIDEVersions = versions
    }

    func checkForUpdatesIfNeeded() {
        guard !didCheckAutomatically else { return }
        didCheckAutomatically = true
        checkForUpdates()
    }

    func checkForUpdates() {
        guard !isBusy else { return }
        guard let currentVersion else {
            state = .failed("Updates are available only when Mustel runs from the installed app.")
            return
        }

        state = .checking
        let service = service
        Task {
            do {
                let release = try await service.latestRelease()
                guard let release else {
                    latestRelease = nil
                    state = .noReleases
                    lastCheckedAt = Date()
                    return
                }
                latestRelease = release
                if release.version > currentVersion {
                    guard release.assetURL != nil else {
                        state = .failed(UpdateError.missingAsset.localizedDescription)
                        lastCheckedAt = Date()
                        return
                    }
                    state = .available(release)
                } else {
                    state = .upToDate
                }
                lastCheckedAt = Date()
            } catch {
                state = .failed(error.localizedDescription)
                lastCheckedAt = Date()
            }
        }
    }

    func installAvailableUpdate() {
        guard case let .available(release) = state, !isBusy else { return }
        state = .downloading(0)

        let service = service
        let installer = installer
        Task {
            do {
                let archiveURL = try await service.download(release) { progress in
                    Task { @MainActor in
                        guard case .downloading = self.state else { return }
                        self.state = .downloading(min(max(progress, 0), 1))
                    }
                }
                state = .installing
                try await installer.install(archiveURL: archiveURL, release: release)
                terminate()
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
