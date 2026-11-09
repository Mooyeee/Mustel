import Foundation

struct VSCodeCommandStatus: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case requested
        case completed
        case failed(String)
    }

    let command: VSCodeCommand
    let phase: Phase
    let completedAt: Date?

    init(command: VSCodeCommand, phase: Phase, completedAt: Date? = nil) {
        self.command = command
        self.phase = phase
        self.completedAt = phase == .completed ? (completedAt ?? Date()) : nil
    }

    var text: String {
        switch phase {
        case .requested:
            return "Requesting \(command.label.lowercased())…"
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

    func completionText(at now: Date) -> String {
        guard let completedAt else { return "\(command.label) complete" }
        let seconds = max(0, Int(now.timeIntervalSince(completedAt)))
        if seconds >= 60 {
            if command == .hotRestart {
                return "\(command.completedLabel) > 1m ago"
            }
            return "\(command.completedLabel) more than one minute ago"
        }
        return "\(command.completedLabel) \(seconds)s ago"
    }
}
