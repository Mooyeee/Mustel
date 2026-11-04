import Foundation

enum SessionState: Equatable, Sendable {
    case connecting
    case attaching
    case starting(appID: String?)
    case ready(appID: String)
    case stopped(String)
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var appID: String? {
        switch self {
        case let .starting(appID):
            return appID
        case let .ready(appID):
            return appID
        case .connecting, .attaching, .stopped, .failed:
            return nil
        }
    }

    var defaultText: String {
        switch self {
        case .connecting:
            return "Connecting…"
        case .attaching:
            return "Attaching…"
        case let .starting(appID):
            return appID == nil ? "Flutter did not provide an app ID" : "Starting connection…"
        case .ready:
            return "Connected"
        case let .stopped(message), let .failed(message):
            return message
        }
    }
}
