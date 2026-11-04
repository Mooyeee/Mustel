import Foundation

enum FlutterSessionMode: Hashable, Sendable {
    case attach
    case attachURL
    case run
}

struct FlutterTarget: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let projectPath: String
    let deviceID: String
    let targetPath: String?
    let vmServiceURL: String?
    let mode: FlutterSessionMode
}
