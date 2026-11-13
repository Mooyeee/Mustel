import Foundation

final class SettingsStore {
    private enum Key: String, CaseIterable {
        case flutterExecutable
        case discoveryInterval
        case alwaysAnimateLogo
        case animationsEnabled
    }

    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults?

    init(
        defaults: UserDefaults = .standard,
        legacyDefaults: UserDefaults? = nil
    ) {
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults ?? (
            defaults === UserDefaults.standard
                ? UserDefaults(suiteName: AppIdentity.legacyBundleIdentifier)
                : nil
        )
        migrateLegacyValuesIfNeeded()
    }

    var flutterExecutable: String? {
        get { defaults.string(forKey: Key.flutterExecutable.rawValue) }
        set { defaults.set(newValue, forKey: Key.flutterExecutable.rawValue) }
    }

    var discoveryInterval: Int? {
        get {
            guard defaults.object(forKey: Key.discoveryInterval.rawValue) != nil else { return nil }
            return defaults.integer(forKey: Key.discoveryInterval.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.discoveryInterval.rawValue) }
    }

    var alwaysAnimateLogo: Bool {
        get { defaults.bool(forKey: Key.alwaysAnimateLogo.rawValue) }
        set { defaults.set(newValue, forKey: Key.alwaysAnimateLogo.rawValue) }
    }

    var animationsEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.animationsEnabled.rawValue) != nil else { return true }
            return defaults.bool(forKey: Key.animationsEnabled.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.animationsEnabled.rawValue) }
    }

    private func migrateLegacyValuesIfNeeded() {
        guard let legacyDefaults else { return }
        for key in Key.allCases {
            guard defaults.object(forKey: key.rawValue) == nil,
                  let value = legacyDefaults.object(forKey: key.rawValue) else {
                continue
            }
            defaults.set(value, forKey: key.rawValue)
        }
    }
}
