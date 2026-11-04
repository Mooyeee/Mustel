import SwiftUI

struct VSCodeSectionView: View {
    let sessions: [VSCodeDebugTarget]
    let status: String
    let commandStatuses: [String: VSCodeCommandStatus]
    let onRefresh: () -> Void
    let onCommand: (VSCodeCommand, VSCodeDebugTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("VS Code")
                    .font(.headline)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh VS Code sessions")
                .glassButtonStyleIfAvailable()
            }
            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if !sessions.isEmpty {
                ScrollViewIfNeeded(maxHeight: 174) {
                    VStack(spacing: 6) {
                        ForEach(sessions) { target in
                            VSCodeSessionRow(
                                target: target,
                                status: commandStatuses[target.id],
                                onHotReload: { onCommand(.hotReload, target) },
                                onHotRestart: { onCommand(.hotRestart, target) }
                            )
                        }
                    }
                }
            }
        }
    }
}
