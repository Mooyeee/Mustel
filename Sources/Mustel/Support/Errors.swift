import Foundation

enum DiscoveryError: LocalizedError {
    case invalidDeviceList
    case commandFailed(String, Int32, String)
    case workingDirectoryUnavailable(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidDeviceList:
            return "Flutter returned an invalid device list."
        case let .commandFailed(command, status, output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(command) exited with status \(status)."
                : "\(command) exited with status \(status): \(detail)"
        case let .workingDirectoryUnavailable(pid):
            return "Could not read the working directory for Flutter process \(pid)."
        }
    }
}

enum BridgeError: LocalizedError {
    case invalidSocketPath
    case invalidResponse(String)
    case commandFailed(String)
    case socketOperation(String)

    var errorDescription: String? {
        switch self {
        case .invalidSocketPath:
            return "The VS Code bridge descriptor contains an invalid socket path."
        case let .invalidResponse(message):
            return message
        case let .commandFailed(message):
            return message
        case let .socketOperation(message):
            return message
        }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case appBundleRequired

    var errorDescription: String? {
        "Launch at login is available after installing Mustel as a macOS app."
    }
}
