import Foundation

struct DiscoverySnapshot: Sendable {
    let devices: [FlutterDeviceInfo]
    let targets: [FlutterTarget]
    let skippedRuns: Int
    let unsupportedRuns: Int
    let ideManagedRuns: Int
}
