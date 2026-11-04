import Foundation

struct VSCodeDebugTarget: Identifiable, Hashable, Sendable {
    let id: String
    let sessionID: String
    let socketPath: String
    let name: String
    let workspace: String
}
