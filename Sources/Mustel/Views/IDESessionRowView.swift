import SwiftUI

struct IDESessionRow: View {
    let target: VSCodeDebugTarget
    let status: VSCodeCommandStatus?
    let onHotReload: () -> Void
    let onHotRestart: () -> Void

    private var isReloading: Bool {
        status?.isInFlight == true && status?.command == .hotReload
    }

    private var isRestarting: Bool {
        status?.isInFlight == true && status?.command == .hotRestart
    }

    private var reloadCompleted: Bool {
        status?.command == .hotReload && status?.phase == .completed
    }

    private var restartCompleted: Bool {
        status?.command == .hotRestart && status?.phase == .completed
    }

    private var projectPath: String {
        FlutterProjectLocator.resolveAppPath(target.projectPath) ?? target.projectPath
    }

    private var appName: String? {
        if let name = FlutterProjectLocator.appName(for: target.projectPath) {
            return name
        }
        let folder = URL(fileURLWithPath: projectPath).lastPathComponent
        return folder.isEmpty ? nil : folder
    }

    var body: some View {
        HStack(spacing: 8) {
            ProjectIconView(projectPath: projectPath, platformHint: target.name)
            VStack(alignment: .leading, spacing: 3) {
                Text(appName.map { "\($0) - \(target.name)" } ?? target.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(projectPath.isEmpty
                     ? "Flutter run session"
                     : URL(fileURLWithPath: projectPath).path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                SessionStatusView(status: status, defaultText: "Running", isReady: true)
            }
            Spacer(minLength: 4)
            Button(action: onHotReload) {
                CommandIcon(command: .reload, isRunning: isReloading, completed: reloadCompleted)
                    .frame(width: 16, height: 16)
            }
            .help("Hot reload in IDE")
            .disabled(status?.isInFlight == true)
            .squareIconButtonStyle()
            Button(action: onHotRestart) {
                CommandIcon(command: .restart, isRunning: isRestarting, completed: restartCompleted)
                    .frame(width: 16, height: 16)
            }
            .help("Hot restart in IDE")
            .disabled(status?.isInFlight == true)
            .squareIconButtonStyle()
        }
        .padding(.vertical, 4)
    }
}
