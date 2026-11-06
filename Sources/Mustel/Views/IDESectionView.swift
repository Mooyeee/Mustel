import SwiftUI

struct IDESectionView: View {
    let sessions: [VSCodeDebugTarget]
    let status: String
    let commandStatuses: [String: VSCodeCommandStatus]
    let onRefresh: () -> Void
    let onCommand: (VSCodeCommand, VSCodeDebugTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("IDE")
                    .font(.headline)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh IDE sessions")
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
                            IDESessionRow(
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
