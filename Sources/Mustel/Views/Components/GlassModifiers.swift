import SwiftUI

extension View {
    @ViewBuilder
    func glassButtonStyleIfAvailable() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            self
        }
        #else
        self
        #endif
    }

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

    func squareIconButtonStyle(isExpanded: Bool = false) -> some View {
        buttonStyle(SquareIconButtonStyle(isExpanded: isExpanded))
    }
}

private struct SquareIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isExpanded: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .padding(.horizontal, isExpanded ? 8 : 0)
            .frame(minWidth: 32, minHeight: 32)
            .fixedSize()
            .contentShape(Rectangle())
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            label
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 7))
                .opacity(isEnabled ? 1 : 0.5)
        } else {
            label
                .background(
                    Color.secondary.opacity(configuration.isPressed ? 0.22 : 0.1),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .opacity(isEnabled ? 1 : 0.5)
        }
        #else
        label
            .background(
                Color.secondary.opacity(configuration.isPressed ? 0.22 : 0.1),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .opacity(isEnabled ? 1 : 0.5)
        #endif
    }
}
