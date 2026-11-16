import SwiftUI

extension View {
    @ViewBuilder
    func glassPlateIfAvailable(cornerRadius: CGFloat = 8, padding: CGFloat = 5) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self
                .padding(padding)
                .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self
        }
        #else
        self
        #endif
    }

    func roundIconButtonStyle() -> some View {
        buttonStyle(RoundIconButtonStyle())
    }
}

private struct RoundIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .frame(minWidth: 32, minHeight: 32)
            .fixedSize()
            .contentShape(Capsule())
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            label
                .glassEffect(.regular.interactive(), in: Capsule())
                .opacity(isEnabled ? 1 : 0.5)
        } else {
            label
                .background(
                    Color.secondary.opacity(configuration.isPressed ? 0.22 : 0.1),
                    in: Capsule()
                )
                .opacity(isEnabled ? 1 : 0.5)
        }
        #else
        label
            .background(
                Color.secondary.opacity(configuration.isPressed ? 0.22 : 0.1),
                in: Capsule()
            )
            .opacity(isEnabled ? 1 : 0.5)
        #endif
    }
}
