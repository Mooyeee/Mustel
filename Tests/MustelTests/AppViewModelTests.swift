import XCTest
@testable import Mustel

@MainActor
final class AppViewModelTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MustelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testApplyDiscoveryUpdatesDevicesSessionsAndStatus() {
        let model = makeModel()
        let device = makeDevice()
        let target = makeTarget(id: "attach-1", deviceID: device.id)
        let snapshot = DiscoverySnapshot(
            devices: [device],
            targets: [target],
            skippedRuns: 1,
            unsupportedRuns: 0,
            ideManagedRuns: 0
        )

        model.applyDiscovery(snapshot)

        XCTAssertEqual(model.devices.map(\.id), [device.id])
        XCTAssertEqual(model.launchForm.selectedDeviceID, device.id)
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions.first?.target.id, target.id)
        XCTAssertEqual(
            model.discoveryStatus,
            "1 existing Flutter target(s) detected. 1 run(s) skipped; use `flutter run -d <device>` if the device is ambiguous."
        )
    }

    func testApplyDiscoveryReusesMatchingAttachSession() {
        let model = makeModel()
        let target = makeTarget(id: "attach-1")
        let snapshot = DiscoverySnapshot(
            devices: [],
            targets: [target],
            skippedRuns: 0,
            unsupportedRuns: 0,
            ideManagedRuns: 0
        )

        model.applyDiscovery(snapshot)
        let first = model.sessions.first
        model.applyDiscovery(snapshot)

        XCTAssertTrue(model.sessions.first === first)
    }

    func testApplyDiscoveryReplacesAttachURLSessionWhenServiceURLChanges() {
        let model = makeModel()
        let original = makeTarget(id: "attach-url-1", mode: .attachURL, vmServiceURL: "ws://127.0.0.1:1111/ws")
        let updated = makeTarget(id: "attach-url-1", mode: .attachURL, vmServiceURL: "ws://127.0.0.1:2222/ws")

        model.applyDiscovery(snapshot(targets: [original]))
        let first = model.sessions.first
        model.applyDiscovery(snapshot(targets: [updated]))

        XCTAssertFalse(model.sessions.first === first)
        XCTAssertEqual(first?.state, .stopped("Disconnected"))
    }

    func testLaunchAddsOwnedSessionAndDismissesForm() throws {
        let model = makeModel()
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let device = makeDevice()
        model.applyDiscovery(snapshot(devices: [device]))

        model.launchForm.projectPath = project.path
        model.launchForm.selectedDeviceID = device.id
        model.launchForm.targetPath = "lib/main_dev.dart"
        model.launchForm.isPresented = true

        model.launch()

        XCTAssertNil(model.launchForm.error)
        XCTAssertFalse(model.launchForm.isPresented)
        XCTAssertEqual(model.launchForm.targetPath, "")
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions.first?.target.mode, .run)
        XCTAssertEqual(model.sessions.first?.target.targetPath, "lib/main_dev.dart")
    }

    func testLaunchReportsValidationErrors() {
        let model = makeModel()
        model.launchForm.projectPath = "/definitely/not/a/flutter/project"

        model.launch()

        XCTAssertEqual(
            model.launchForm.error,
            "Choose a Flutter project folder containing pubspec.yaml."
        )
        XCTAssertTrue(model.sessions.isEmpty)
    }

    func testReconnectReplacesSession() {
        let model = makeModel()
        model.applyDiscovery(snapshot(targets: [makeTarget(id: "attach-1")]))
        guard let original = model.sessions.first else {
            return XCTFail("Expected a discovered session")
        }

        model.reconnect(original)

        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertFalse(model.sessions.first === original)
        XCTAssertEqual(original.state, .stopped("Disconnected"))
    }

    func testRemoveStopsAndRemovesSession() {
        let model = makeModel()
        model.applyDiscovery(snapshot(targets: [makeTarget(id: "attach-1")]))
        guard let session = model.sessions.first else {
            return XCTFail("Expected a discovered session")
        }

        model.remove(session)

        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertEqual(session.state, .stopped("Disconnected"))
    }

    func testBridgeInstallationStatusIsKnownAfterRefresh() async throws {
        let model = makeModel(bridgeInstalled: true)
        XCTAssertFalse(model.hasCheckedIDEBridge)

        model.refreshIDESessions()
        for _ in 0..<100 where !model.hasCheckedIDEBridge {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(model.hasCheckedIDEBridge)
        XCTAssertTrue(model.ideBridgeInstalled)
    }

    private func makeModel(bridgeInstalled: Bool = false) -> AppViewModel {
        let store = SettingsStore(defaults: defaults)
        return AppViewModel(
            settingsStore: store,
            discoveryService: FakeDiscoveryService(snapshot: snapshot()),
            bridge: FakeBridge(),
            ideBridgeProbe: FakeIDEBridgeProbe(installed: bridgeInstalled),
            launchAtLogin: FakeLaunchAtLogin(),
            launchForm: LaunchFormViewModel(projectPicker: FakeProjectPicker(path: nil)),
            makeSession: { target, _ in
                SessionViewModel(
                    target: target,
                    flutterExecutable: "/custom/flutter",
                    service: FakeSessionService()
                )
            }
        )
    }

    private func makeDevice() -> FlutterDeviceInfo {
        FlutterDeviceInfo(
            id: "device-1",
            name: "Pixel",
            targetPlatform: "android-arm64",
            isSupported: true
        )
    }

    private func makeTarget(
        id: String,
        deviceID: String = "device-1",
        mode: FlutterSessionMode = .attach,
        vmServiceURL: String? = nil
    ) -> FlutterTarget {
        FlutterTarget(
            id: id,
            name: "App · Pixel",
            projectPath: "/tmp/App",
            deviceID: deviceID,
            targetPath: nil,
            vmServiceURL: vmServiceURL,
            mode: mode
        )
    }

    private func snapshot(
        devices: [FlutterDeviceInfo] = [],
        targets: [FlutterTarget] = []
    ) -> DiscoverySnapshot {
        DiscoverySnapshot(
            devices: devices,
            targets: targets,
            skippedRuns: 0,
            unsupportedRuns: 0,
            ideManagedRuns: 0
        )
    }
}
