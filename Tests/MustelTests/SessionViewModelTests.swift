import XCTest
@testable import Mustel

@MainActor
final class SessionViewModelTests: XCTestCase {
    func testConnectsAndBecomesReady() async {
        let service = FakeSessionService()
        let session = SessionViewModel(
            target: makeTarget(),
            flutterExecutable: "/custom/flutter",
            service: service
        )

        XCTAssertTrue(service.isStarted)
        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.state, .attaching)

        service.emit(.machine([.event(name: "app.start", appID: "app-1", error: nil, trace: nil)]))
        await settle()
        XCTAssertEqual(session.state, .starting(appID: "app-1"))
        XCTAssertEqual(session.appID, "app-1")
        XCTAssertFalse(session.isReady)

        service.emit(.machine([.event(name: "app.started", appID: nil, error: nil, trace: nil)]))
        await settle()
        XCTAssertEqual(session.state, .ready(appID: "app-1"))
        XCTAssertTrue(session.isReady)
        XCTAssertEqual(session.statusText, "Connected")
    }

    func testHotReloadSendsRequestAndCompletes() async {
        let (service, session) = await makeReadySession()

        session.hotReload()

        XCTAssertEqual(service.sentPayloads.count, 1)
        let payload = service.sentPayloads[0]
        XCTAssertEqual(payload["method"] as? String, "app.restart")
        XCTAssertEqual((payload["params"] as? [String: Any])?["fullRestart"] as? Bool, false)
        XCTAssertEqual(session.activity, "Hot reload requested")
        XCTAssertTrue(session.isReloading)
        XCTAssertTrue(session.isCommandInFlight)

        let requestID = payload["id"] as! Int
        service.emit(.machine([.response(id: String(requestID), error: nil)]))
        await settle()
        XCTAssertEqual(session.activity, "Hot reload complete")
        XCTAssertFalse(session.isReloading)
        XCTAssertTrue(session.reloadCompleted)
        XCTAssertFalse(session.isCommandInFlight)
    }

    func testHotRestartSendsFullRestart() async {
        let (service, session) = await makeReadySession()

        session.hotRestart()

        let payload = service.sentPayloads[0]
        XCTAssertEqual((payload["params"] as? [String: Any])?["fullRestart"] as? Bool, true)
        XCTAssertEqual(session.activity, "Hot restart requested")
        XCTAssertTrue(session.isRestarting)
        XCTAssertTrue(session.isCommandInFlight)
    }

    func testHotReloadBeforeReadyWaits() {
        let service = FakeSessionService()
        let session = SessionViewModel(
            target: makeTarget(),
            flutterExecutable: "/custom/flutter",
            service: service
        )

        session.hotReload()

        XCTAssertTrue(service.sentPayloads.isEmpty)
        XCTAssertEqual(session.activity, "Waiting for the Flutter app…")
    }

    func testSendFailureIsReported() async {
        let (service, session) = await makeReadySession()
        service.sendError = TestError.failed("write failed")

        session.hotReload()

        XCTAssertTrue(service.sentPayloads.isEmpty)
        XCTAssertEqual(session.activity, "Could not send command: write failed")
        XCTAssertEqual(session.commandPhase, .failed(.hotReload))
        XCTAssertFalse(session.isCommandInFlight)
    }

    func testResponseErrorIsReportedAndKeepsSessionReady() async {
        let (service, session) = await makeReadySession()

        session.hotReload()
        let requestID = service.sentPayloads[0]["id"] as! Int
        service.emit(.machine([.response(id: String(requestID), error: "reload failed")]))
        await settle()

        XCTAssertEqual(session.activity, "Hot reload failed: reload failed")
        XCTAssertTrue(session.isReady)
        XCTAssertEqual(session.diagnostics, ["Hot reload failed: reload failed"])
        XCTAssertEqual(session.commandPhase, .failed(.hotReload))
        XCTAssertFalse(session.isCommandInFlight)
    }

    func testAppStopFailureIsReported() async {
        let (service, session) = await makeReadySession()

        service.emit(.machine([.event(name: "app.stop", appID: nil, error: "attach boom", trace: "trace")]))
        await settle()

        XCTAssertEqual(session.state, .failed("Attach failed: attach boom"))
        XCTAssertFalse(session.isReady)
        XCTAssertEqual(session.diagnostics, ["Attach failed: attach boom", "trace"])
    }

    func testStandardErrorBecomesActivityAndDiagnostic() async {
        let (service, session) = await makeReadySession()

        service.emit(.stderr("stderr line"))
        await settle()

        XCTAssertEqual(session.diagnostics, ["stderr line"])
        XCTAssertEqual(session.activity, "stderr line")
    }

    func testProcessExitStopsSession() async {
        let (service, session) = await makeReadySession()

        service.emit(.exited(1))
        await settle()

        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.state, .stopped("Flutter attach exited (code 1)"))
    }

    func testProcessExitUsesRunLabelForOwnedSessions() async {
        let (service, session) = await makeReadySession(mode: .run)

        service.emit(.exited(2))
        await settle()

        XCTAssertEqual(session.state, .stopped("Flutter run exited (code 2)"))
    }

    func testStopMarksSessionDisconnected() async {
        let (service, session) = await makeReadySession()

        session.stop()

        XCTAssertTrue(service.isStopped)
        XCTAssertEqual(session.state, .stopped("Disconnected"))
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.commandPhase, .idle)
    }

    func testStartFailureIsReported() {
        let service = FakeSessionService()
        service.startError = TestError.failed("no flutter")

        let session = SessionViewModel(
            target: makeTarget(),
            flutterExecutable: "/custom/flutter",
            service: service
        )

        XCTAssertEqual(session.state, .failed("Could not start Flutter: no flutter"))
        XCTAssertFalse(session.isRunning)
    }

    func testDiagnosticsAreCapped() async {
        let (service, session) = await makeReadySession()

        for index in 0..<10 {
            service.emit(.stderr("line \(index)"))
            await settle()
        }

        XCTAssertEqual(session.diagnostics.count, 6)
        XCTAssertEqual(session.diagnostics.first, "line 4")
        XCTAssertEqual(session.diagnostics.last, "line 9")
    }

    private func makeReadySession(mode: FlutterSessionMode = .attach) async -> (FakeSessionService, SessionViewModel) {
        let service = FakeSessionService()
        let session = SessionViewModel(
            target: makeTarget(mode: mode),
            flutterExecutable: "/custom/flutter",
            service: service
        )
        service.emit(.machine([.event(name: "app.start", appID: "app-1", error: nil, trace: nil)]))
        await settle()
        service.emit(.machine([.event(name: "app.started", appID: nil, error: nil, trace: nil)]))
        await settle()
        return (service, session)
    }
}
