import Foundation

struct VSCodeCommandStatus: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case requested
        case completed
        case failed(String)
    }

    let command: VSCodeCommand
    let phase: Phase

    var text: String {
        switch phase {
        case .requested:
            return "\(command.label) requested…"
        case .completed:
            return "\(command.label) complete"
        case let .failed(message):
            return "\(command.label) failed: \(message)"
        }
    }

    var isInFlight: Bool {
        phase == .requested
    }

    var isFailure: Bool {
        if case .failed = phase { return true }
        return false
    }
}
