import Foundation

struct FlutterDeviceInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let targetPlatform: String
    let isSupported: Bool

    var supportsAttachDiscovery: Bool {
        targetPlatform.hasPrefix("android-") || targetPlatform.hasPrefix("ios-")
    }
}
