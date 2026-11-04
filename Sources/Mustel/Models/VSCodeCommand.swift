import Foundation

enum VSCodeCommand: String, Sendable {
    case hotReload
    case hotRestart

    var label: String {
        switch self {
        case .hotReload:
            return "Hot reload"
        case .hotRestart:
            return "Hot restart"
        }
    }
}
