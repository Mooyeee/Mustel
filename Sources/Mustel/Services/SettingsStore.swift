import Foundation

final class SettingsStore {
    private enum Key: String {
        case flutterExecutable
        case discoveryInterval
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
}
