import Foundation

struct VSCodeBridgeDiscovery: Sendable {
    let targets: [VSCodeDebugTarget]
    let status: String
}

struct VSCodeBridgeSnapshot: Sendable {
    let targets: [VSCodeDebugTarget]
    let status: String
    let bridgeVersions: IDEBridgeVersions
}
