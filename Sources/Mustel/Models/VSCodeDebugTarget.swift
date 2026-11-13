import Foundation

struct VSCodeDebugTarget: Identifiable, Hashable, Sendable {
    let id: String
    let sessionID: String
    let socketPath: String
    let name: String
    let workspace: String
    /// Flutter app package reported by the IDE bridge. Older bridge versions
    /// only send `workspace`, so it falls back to that.
    let projectPath: String

    init(
        id: String,
        sessionID: String,
        socketPath: String,
        name: String,
        workspace: String,
        projectPath: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.socketPath = socketPath
        self.name = name
        self.workspace = workspace
        self.projectPath = projectPath ?? workspace
    }
}
