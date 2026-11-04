import SwiftUI

extension View {
    @ViewBuilder
    func glassButtonStyleIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            self
        }
    }

    @ViewBuilder
    func glassPlateIfAvailable(cornerRadius: CGFloat = 8, padding: CGFloat = 5) -> some View {
        if #available(macOS 26.0, *) {
            self
                .padding(padding)
                .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self
        }
    }
}
