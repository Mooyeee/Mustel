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

    var discoveryInterval: DiscoveryInterval {
        didSet {
            guard discoveryInterval != oldValue else { return }
            store.discoveryInterval = discoveryInterval.rawValue
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

    init(
        store: SettingsStore = SettingsStore(),
        launchAtLogin: LaunchAtLoginControlling = LaunchAtLoginService()
    ) {
        self.store = store
        self.launchAtLogin = launchAtLogin
        flutterExecutable = store.flutterExecutable ?? FlutterExecutableLocator.resolve("flutter")
        discoveryInterval = store.discoveryInterval.flatMap(DiscoveryInterval.init(rawValue:)) ?? .default
        alwaysAnimateLogo = store.alwaysAnimateLogo
        animationsEnabled = store.animationsEnabled
        refreshLaunchAtLoginState()
    }

    var canConfigureLaunchAtLogin: Bool {
        launchAtLogin.canConfigure
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
