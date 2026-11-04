import Foundation
import ServiceManagement

protocol LaunchAtLoginControlling {
    var canConfigure: Bool { get }
    var isEnabled: Bool { get }
    var message: String? { get }
    func setEnabled(_ enabled: Bool) throws
}

struct LaunchAtLoginService: LaunchAtLoginControlling {
    var canConfigure: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.bundleIdentifier == "com.ionutdanielfagadau.Mustel"
    }

    var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    var message: String? {
        switch SMAppService.mainApp.status {
        case .enabled, .notRegistered:
            return nil
        case .requiresApproval:
            return "Enable Mustel in System Settings > General > Login Items."
        case .notFound:
            return "Install the app bundle before enabling launch at login."
        @unknown default:
            return "Could not determine launch-at-login status."
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        guard canConfigure else {
            throw LaunchAtLoginError.appBundleRequired
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
