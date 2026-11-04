import Foundation
import Observation

@Observable
@MainActor
final class SessionViewModel: Identifiable {
    let id: String
    let target: FlutterTarget

    private(set) var state: SessionState = .connecting
    private(set) var activity: String?
    private(set) var isRunning = false
    private(set) var diagnostics: [String] = []

    @ObservationIgnored private let service: FlutterSessionServicing
    @ObservationIgnored private var nextRequestID = 1
    @ObservationIgnored private var pendingRequests: [String: String] = [:]
    @ObservationIgnored private var wasStoppedByUser = false
    @ObservationIgnored private var lastErrorLine: String?

    init(
        target: FlutterTarget,
        flutterExecutable: String,
        service: FlutterSessionServicing? = nil
    ) {
        id = target.id
        self.target = target
        let service = service ?? FlutterSessionService(target: target, flutterExecutable: flutterExecutable)
        self.service = service
        service.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        connect()
    }

    var isReady: Bool { state.isReady }
    var appID: String? { state.appID }
    var statusText: String { activity ?? state.defaultText }

    func connect() {
        do {
            try service.start()
            isRunning = true
            state = .attaching
            activity = nil
        } catch {
            state = .failed("Could not start Flutter: \(error.localizedDescription)")
        }
    }

    func stop() {
        wasStoppedByUser = true
        state = .stopped("Disconnected")
        activity = nil
        isRunning = false
        service.stop()
    }

    func hotReload() {
        sendRestart(full: false)
    }

    func hotRestart() {
        sendRestart(full: true)
    }

    private func sendRestart(full: Bool) {
        guard isReady, let appID else {
            activity = "Waiting for the Flutter app…"
            return
        }

        let requestID = nextRequestID
        nextRequestID += 1
        let label = full ? "Hot restart" : "Hot reload"
        pendingRequests[String(requestID)] = label
        do {
            try service.send([
                "id": requestID,
                "method": "app.restart",
                "params": ["appId": appID, "fullRestart": full]
            ])
            activity = "\(label) requested"
        } catch {
            pendingRequests.removeValue(forKey: String(requestID))
            activity = "Could not send command: \(error.localizedDescription)"
        }
    }

    private func handle(_ event: FlutterSessionEvent) {
        switch event {
        case let .machine(messages):
            for message in messages {
                handle(message)
            }
        case let .stderr(line):
            guard !line.isEmpty else { return }
            lastErrorLine = line
            appendDiagnostic(line)
            activity = brief(line)
        case let .exited(code):
            handleProcessExit(code: code)
        }
    }

    private func handle(_ message: MachineOutput) {
        switch message {
        case let .event(name, appID, error, trace):
            switch name {
            case "app.start":
                state = .starting(appID: appID)
                activity = nil
            case "app.started":
                if let appID = state.appID {
                    state = .ready(appID: appID)
                    activity = nil
                }
            case "app.stop":
                if let error {
                    state = .failed("Attach failed: \(brief(error))")
                    activity = nil
                    appendDiagnostic("Attach failed: \(error)")
                    if let trace {
                        appendDiagnostic(trace)
                    }
                } else {
                    state = .stopped("Flutter app stopped")
                    activity = nil
                }
            default:
                break
            }
        case let .response(id, error):
            guard let label = pendingRequests.removeValue(forKey: id) else {
                if let error {
                    appendDiagnostic("Flutter error: \(error)")
                    if !isReady {
                        activity = brief(error)
                    }
                }
                return
            }
            if let error {
                activity = "\(label) failed: \(brief(error))"
                appendDiagnostic("\(label) failed: \(error)")
            } else {
                activity = "\(label) complete"
            }
        }
    }

    private func handleProcessExit(code: Int32) {
        isRunning = false
        guard !wasStoppedByUser else { return }
        let processName = target.mode == .run ? "Flutter run" : "Flutter attach"
        state = .stopped(lastErrorLine ?? "\(processName) exited (code \(code))")
        activity = nil
    }

    private func appendDiagnostic(_ line: String) {
        diagnostics.append(line)
        if diagnostics.count > 6 {
            diagnostics.removeFirst(diagnostics.count - 6)
        }
    }

    private func brief(_ message: String) -> String {
        let oneLine = message.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard oneLine.count > 140 else { return oneLine }
        return "\(oneLine.prefix(137))…"
    }
}
