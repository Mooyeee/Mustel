import SwiftUI

struct SessionRow: View {
    let session: SessionViewModel
    let onReconnect: () -> Void
    let onStop: () -> Void
    let onRemove: () -> Void
    @State private var showsDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.target.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if session.target.mode == .run, session.isRunning {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                    }
                    .help("Stop app")
                    .glassButtonStyleIfAvailable()
                } else if session.target.mode == .run {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                    }
                    .help("Remove finished run")
                    .glassButtonStyleIfAvailable()
                } else if !session.isRunning {
                    Button(action: onReconnect) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reconnect")
                    .glassButtonStyleIfAvailable()
                }
                Button(action: session.hotReload) {
                    Image(systemName: "bolt.fill")
                        .frame(width: 16, height: 16)
                }
                .help("Hot reload")
                .disabled(!session.isReady)
                .glassButtonStyleIfAvailable()

                Button(action: session.hotRestart) {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 16, height: 16)
                }
                .help("Hot restart")
                .disabled(!session.isReady)
                .glassButtonStyleIfAvailable()
            }
            Text(session.target.mode == .run ? "Started by Mustel" : "Discovered existing run")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(session.statusText)
                .font(.caption)
                .foregroundStyle(session.isReady ? Color.green : Color.secondary)
                .lineLimit(2)
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
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
