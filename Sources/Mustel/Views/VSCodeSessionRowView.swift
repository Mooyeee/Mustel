import SwiftUI

struct VSCodeSessionRow: View {
    let target: VSCodeDebugTarget
    let status: VSCodeCommandStatus?
    let onHotReload: () -> Void
    let onHotRestart: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(target.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(target.workspace.isEmpty
                     ? "Dart debug session"
                     : URL(fileURLWithPath: target.workspace).path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let status {
                    Text(status.text)
                        .font(.caption2)
                        .foregroundStyle(status.isFailure ? Color.red : Color.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Button(action: onHotReload) {
                Image(systemName: "bolt.fill")
                    .frame(width: 16, height: 16)
            }
            .help("Hot reload in VS Code")
            .disabled(status?.isInFlight == true)
            .glassButtonStyleIfAvailable()
            Button(action: onHotRestart) {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 16, height: 16)
            }
            .help("Hot restart in VS Code")
            .disabled(status?.isInFlight == true)
            .glassButtonStyleIfAvailable()
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
