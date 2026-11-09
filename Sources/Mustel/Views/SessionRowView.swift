import SwiftUI

struct SessionRow: View {
    let session: SessionViewModel
    let platformHint: String
    let onReconnect: () -> Void
    let onStop: () -> Void
    let onRemove: () -> Void
    @State private var showsDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                ProjectIconView(
                    projectPath: session.target.projectPath,
                    platformHint: platformHint
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.target.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(session.target.projectPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    SessionStatusView(status: session.commandStatus, defaultText: session.statusText, isReady: session.isReady)
                }
                Spacer()
                if session.target.mode == .run, session.isRunning {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                    }
                    .help("Stop app")
                    .squareIconButtonStyle()
                } else if session.target.mode == .run {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                    }
                    .help("Remove finished run")
                    .squareIconButtonStyle()
                } else if !session.isRunning {
                    Button(action: onReconnect) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reconnect")
                    .squareIconButtonStyle()
                }
                Button(action: session.hotReload) {
                    CommandIcon(
                        command: .reload,
                        isRunning: session.isReloading,
                        completed: session.reloadCompleted
                    )
                    .frame(width: 16, height: 16)
                }
                .help("Hot reload")
                .disabled(!session.isReady || session.isCommandInFlight)
                .squareIconButtonStyle()

                Button(action: session.hotRestart) {
                    CommandIcon(
                        command: .restart,
                        isRunning: session.isRestarting,
                        completed: session.restartCompleted
                    )
                    .frame(width: 16, height: 16)
                }
                .help("Hot restart")
                .disabled(!session.isReady || session.isCommandInFlight)
                .squareIconButtonStyle()
            }
            Text(session.target.mode == .run ? "Started by Mustel" : "Discovered existing run")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let appID = session.appID {
                Text("App ID: \(appID)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !session.diagnostics.isEmpty {
                DisclosureGroup("Details (\(session.diagnostics.count))", isExpanded: $showsDiagnostics) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(session.diagnostics.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
