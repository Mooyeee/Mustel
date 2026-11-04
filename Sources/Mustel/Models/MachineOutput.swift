import Foundation

enum MachineOutput: Equatable, Sendable {
    case event(name: String, appID: String?, error: String?, trace: String?)
    case response(id: String, error: String?)
}
