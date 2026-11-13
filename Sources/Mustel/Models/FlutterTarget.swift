import Foundation

enum FlutterSessionMode: Hashable, Sendable {
    case attach
    case attachURL
    case run
}

struct FlutterTarget: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Working directory used to start `flutter run` or `flutter attach`.
    let projectPath: String
    let deviceID: String
    let targetPath: String?
    let vmServiceURL: String?
    let mode: FlutterSessionMode
    /// Flutter app package used for the display name and icon. In a pub
    /// workspace this can differ from `projectPath`, which may be the
    /// workspace root.
    let appPath: String

    init(
        id: String,
        name: String,
        projectPath: String,
        deviceID: String,
        targetPath: String?,
        vmServiceURL: String?,
        mode: FlutterSessionMode,
        appPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.projectPath = projectPath
        self.deviceID = deviceID
        self.targetPath = targetPath
        self.vmServiceURL = vmServiceURL
        self.mode = mode
        self.appPath = appPath ?? projectPath
    }
}
