import SwiftUI

struct SessionStatusView: View {
    let status: VSCodeCommandStatus?
    let defaultText: String
    let isReady: Bool

    var body: some View {
        Group {
            if let status {
                switch status.phase {
                case .requested:
                    indicator(status.text, color: .green, glow: true, pulsing: true)
                case .completed:
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        indicator(status.completionText(at: context.date), color: .green, glow: true)
                    }
                case .failed:
                    indicator(status.text, color: .red)
                }
            } else {
                indicator(defaultText, color: isReady ? .green : .secondary, glow: isReady)
            }
        }
        .font(.caption2)
        .lineLimit(2)
    }

    @ViewBuilder
    private func indicator(_ text: String, color: Color, glow: Bool = false, pulsing: Bool = false) -> some View {
        if glow {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                StatusLED(color: color, pulsing: pulsing)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    .accessibilityHidden(true)
                Text(text)
            }
            .foregroundStyle(color)
        } else {
            Label(text, systemImage: "circle.fill")
                .foregroundStyle(color)
        }
    }

    private struct StatusLED: View {
        let color: Color
        let pulsing: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var dimmed = false

        var body: some View {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .opacity(dimmed ? 0 : 1)
                .shadow(color: color.opacity(dimmed ? 0 : 0.65), radius: 3)
                .task(id: pulsing && !reduceMotion) {
                    withAnimation(nil) {
                        dimmed = false
                    }
                    if pulsing && !reduceMotion {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            dimmed = true
                        }
                    }
                }
        }
    }
}
