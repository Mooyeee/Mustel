import Foundation
import Observation

@Observable
@MainActor
final class SettingsViewModel {
    var flutterExecutable: String {
        didSet {
            store.flutterExecutable = flutterExecutable
        }
    }

    var discoveryInterval: Int {
        didSet {
            guard discoveryInterval != oldValue else { return }
            store.discoveryInterval = discoveryInterval
            onDiscoveryIntervalChanged?()
        }
    }

    var alwaysAnimateLogo: Bool {
        didSet {
            guard alwaysAnimateLogo != oldValue else { return }
            store.alwaysAnimateLogo = alwaysAnimateLogo
            onAlwaysAnimateLogoChanged?(alwaysAnimateLogo)
        }
    }

    var animationsEnabled: Bool {
        didSet {
            guard animationsEnabled != oldValue else { return }
            store.animationsEnabled = animationsEnabled
            onAnimationsEnabledChanged?(animationsEnabled)
        }
    }

    private(set) var launchAtLoginEnabled = false
    private(set) var launchAtLoginMessage: String?
    private(set) var launchAtLoginError: String?

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let launchAtLogin: LaunchAtLoginControlling
    @ObservationIgnored var onDiscoveryIntervalChanged: (() -> Void)?
    @ObservationIgnored var onAlwaysAnimateLogoChanged: ((Bool) -> Void)?
    @ObservationIgnored var onAnimationsEnabledChanged: ((Bool) -> Void)?

    static let discoveryIntervalOptions = [5, 10, 30, 60, 300]

    init(
        store: SettingsStore = SettingsStore(),
        launchAtLogin: LaunchAtLoginControlling = LaunchAtLoginService()
    ) {
        self.store = store
        self.launchAtLogin = launchAtLogin
        flutterExecutable = store.flutterExecutable ?? FlutterExecutableLocator.resolve("flutter")
        let storedInterval = store.discoveryInterval ?? 0
        discoveryInterval = Self.discoveryIntervalOptions.contains(storedInterval) ? storedInterval : 5
        alwaysAnimateLogo = store.alwaysAnimateLogo
        animationsEnabled = store.animationsEnabled
        refreshLaunchAtLoginState()
    }

    var canConfigureLaunchAtLogin: Bool {
        launchAtLogin.canConfigure
    }

    static func discoveryIntervalLabel(for interval: Int) -> String {
        switch interval {
        case 60:
            return "Every minute"
        case 300:
            return "Every 5 minutes"
        default:
            return "Every \(interval) seconds"
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLoginState()
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginEnabled = launchAtLogin.isEnabled
        launchAtLoginMessage = launchAtLogin.message
    }
}
