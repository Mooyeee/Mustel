import SwiftUI

struct CommandIcon: View {
    enum Command {
        case reload
        case restart
    }

    let command: Command
    let isRunning: Bool
    let completed: Bool

    @ViewBuilder
    var body: some View {
        switch command {
        case .reload:
            Image(systemName: "bolt.fill")
                .symbolEffect(.pulse, options: .repeating, isActive: isRunning)
                .symbolEffect(.bounce, value: completed)
        case .restart:
            SpinningSymbol(isSpinning: isRunning, completed: completed)
        }
    }
}

private struct SpinningSymbol: View {
    let isSpinning: Bool
    let completed: Bool

    @State private var angle: Double = 0

    var body: some View {
        Image(systemName: "arrow.counterclockwise")
            .rotationEffect(.degrees(angle))
            .symbolEffect(.bounce, value: completed)
            .onAppear(perform: updateRotation)
            .onChange(of: isSpinning) { _, _ in
                updateRotation()
            }
    }

    private func updateRotation() {
        if isSpinning {
            angle = 0
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                angle = -360
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                angle = 0
            }
        }
    }
}
