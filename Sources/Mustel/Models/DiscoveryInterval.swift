import Foundation

enum DiscoveryInterval: Int, CaseIterable, Identifiable {
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case manual = 0

    static let `default`: DiscoveryInterval = .fiveSeconds

    var id: Int { rawValue }

    /// `nil` when scans only happen on demand.
    var timeInterval: TimeInterval? {
        self == .manual ? nil : TimeInterval(rawValue)
    }

    var label: String {
        guard timeInterval != nil else { return "Manually" }
        let (value, unit) = rawValue.isMultiple(of: 60) ? (rawValue / 60, "minute") : (rawValue, "second")
        return value == 1 ? "Every \(unit)" : "Every \(value) \(unit)s"
    }
}
