import SwiftUI

struct DiscoveryBanner: View {
    let extensionInstalled: Bool

    private var tint: Color {
        extensionInstalled ? .green : .yellow
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: extensionInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(extensionInstalled
                     ? "IDE extension installed, all runs are discovered automatically."
                     : "IDE extension not installed, only mobile runs are discovered automatically.")
                    .foregroundStyle(.primary)
                if !extensionInstalled {
                    Text("For existing desktop/web runs, use --vmservice-out-file or launch from here.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}
