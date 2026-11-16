import AppKit
import SwiftUI

struct ScanningButtonLabel: View {
    let isScanning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var fontSize = NSFont.preferredFont(forTextStyle: .caption1).pointSize

    private let scanningText = "Scanning active Flutter runs…"

    private var expandedWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        return ceil((scanningText as NSString).size(withAttributes: [.font: font]).width) + 38
    }

    var body: some View {
        ZStack {
            Image(systemName: "arrow.clockwise")
                .frame(width: 16, height: 16)
                .opacity(isScanning ? 0 : 1)
                .animation(
                    reduceMotion ? nil : .easeIn(duration: 0.12).delay(isScanning ? 0 : 0.08),
                    value: isScanning
                )

            HStack(spacing: 6) {
                Group {
                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 16, height: 16)
                Text(scanningText)
                    .font(.system(size: fontSize))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .fixedSize()
            .opacity(isScanning ? 1 : 0)
            .animation(
                reduceMotion ? nil : .easeIn(duration: 0.12).delay(isScanning ? 0.08 : 0),
                value: isScanning
            )
        }
        .frame(width: isScanning ? max(32, expandedWidth) : 32, height: 32)
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isScanning)
    }
}
