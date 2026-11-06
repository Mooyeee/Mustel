import Foundation
import Observation

@Observable
@MainActor
final class AppViewModel {
    typealias SessionFactory = @MainActor (FlutterTarget, String) -> SessionViewModel

    private(set) var sessions: [SessionViewModel] = []
    private(set) var vscodeSessions: [VSCodeDebugTarget] = []
    private(set) var devices: [FlutterDeviceInfo] = []
    private(set) var discoveryStatus = "Looking for Flutter runs…"
    private(set) var isDiscovering = false {
        didSet {
            guard isDiscovering != oldValue else { return }
            logoAnimator.setScanning(isDiscovering)
        }
    }
    private(set) var vscodeBridgeStatus = "Connecting to the VS Code bridge…"
    private(set) var vscodeExtensionInstalled = false
    private(set) var vscodeCommandStatuses: [String: VSCodeCommandStatus] = [:]

    let settings: SettingsViewModel
    let launchForm: LaunchFormViewModel
    let logoAnimator: LogoAnimator

    @ObservationIgnored private let discoveryService: FlutterDiscovering
    @ObservationIgnored private let bridge: VSCodeBridging
    @ObservationIgnored private let extensionProbe: VSCodeExtensionProbing
    @ObservationIgnored private let makeSession: SessionFactory
    @ObservationIgnored private var discoveryTimer: Timer?
    @ObservationIgnored private var vscodeBridgeTimer: Timer?
    @ObservationIgnored private var isRefreshingVSCodeSessions = false
    @ObservationIgnored private var started = false

    init(
        settingsStore: SettingsStore = SettingsStore(),
        discoveryService: FlutterDiscovering = FlutterDiscoveryService(),
        bridge: VSCodeBridging = VSCodeBridgeClient(),
        extensionProbe: VSCodeExtensionProbing = VSCodeExtensionProbe(),
        launchAtLogin: LaunchAtLoginControlling = LaunchAtLoginService(),
        launchForm: LaunchFormViewModel? = nil,
        makeSession: @escaping SessionFactory = { target, executable in
            SessionViewModel(target: target, flutterExecutable: executable)
        }
    ) {
        let logoAnimator = LogoAnimator()
        self.discoveryService = discoveryService
        self.bridge = bridge
        self.extensionProbe = extensionProbe
        self.makeSession = makeSession
        self.logoAnimator = logoAnimator
        self.settings = SettingsViewModel(store: settingsStore, launchAtLogin: launchAtLogin)
        self.launchForm = launchForm ?? LaunchFormViewModel()
        settings.onDiscoveryIntervalChanged = { [weak self] in
            self?.scheduleDiscoveryTimer()
        }
        settings.onAlwaysAnimateLogoChanged = { [weak logoAnimator] enabled in
            logoAnimator?.setAlwaysAnimate(enabled)
        }
        logoAnimator.setAlwaysAnimate(settings.alwaysAnimateLogo)
    }

    func start() {
        guard !started else { return }
        started = true
        refreshDiscovery()
        refreshVSCodeSessions()
        scheduleDiscoveryTimer()
        vscodeBridgeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshVSCodeSessions() }
        }
    }

    func refreshDiscovery() {
        guard !isDiscovering else { return }
        isDiscovering = true
        let executable = settings.flutterExecutable
        let service = discoveryService

        Task {
            let outcome: (DiscoverySnapshot?, String?) = await Task.detached(priority: .utility) {
                do {
                    return (try service.discover(flutterExecutable: executable), nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            finishDiscovery(snapshot: outcome.0, errorMessage: outcome.1)
        }
    }

    func reconnect(_ session: SessionViewModel) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].stop()
        sessions[index] = makeSession(session.target, settings.flutterExecutable)
    }

    func launch() {
        if let error = launchForm.validate(devices: devices) {
            launchForm.setError(error)
            return
        }
        guard let target = launchForm.makeTarget(devices: devices) else { return }
        sessions.append(makeSession(target, settings.flutterExecutable))
        launchForm.dismiss()
    }

    func stop(_ session: SessionViewModel) {
        session.stop()
    }

    func remove(_ session: SessionViewModel) {
        session.stop()
        sessions.removeAll { $0.id == session.id }
    }

    func runVSCodeCommand(_ command: VSCodeCommand, on target: VSCodeDebugTarget) {
        vscodeCommandStatuses[target.id] = VSCodeCommandStatus(command: command, phase: .requested)
        let bridge = bridge
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try bridge.perform(command, on: target)
                }.value
                vscodeCommandStatuses[target.id] = VSCodeCommandStatus(command: command, phase: .completed)
            } catch {
                vscodeCommandStatuses[target.id] = VSCodeCommandStatus(
                    command: command,
                    phase: .failed(error.localizedDescription)
                )
            }
        }
    }

    func shutdown() {
        discoveryTimer?.invalidate()
        vscodeBridgeTimer?.invalidate()
        logoAnimator.stop()
        sessions.forEach { $0.stop() }
    }

    func refreshVSCodeSessions() {
        guard !isRefreshingVSCodeSessions else { return }
        isRefreshingVSCodeSessions = true
        let bridge = bridge
        let probe = extensionProbe
        Task {
            let result = await Task.detached(priority: .utility) {
                let discovered = bridge.discover()
                return VSCodeBridgeSnapshot(
                    targets: discovered.targets,
                    status: discovered.status,
                    extensionInstalled: probe.isInstalled()
                )
            }.value
            isRefreshingVSCodeSessions = false
            vscodeSessions = result.targets
            vscodeBridgeStatus = result.status
            vscodeExtensionInstalled = result.extensionInstalled
            let activeIDs = Set(result.targets.map(\.id))
            vscodeCommandStatuses = vscodeCommandStatuses.filter { activeIDs.contains($0.key) }
        }
    }

    func applyDiscovery(_ snapshot: DiscoverySnapshot) {
        devices = snapshot.devices.filter(\.isSupported).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if !devices.contains(where: { $0.id == launchForm.selectedDeviceID }) {
            launchForm.selectedDeviceID = devices.first?.id ?? ""
        }

        let managedSessions = sessions.filter { $0.target.mode == .run }
        let discoveredTargets = snapshot.targets.filter { target in
            !managedSessions.contains {
                $0.target.projectPath == target.projectPath
                    && $0.target.deviceID == target.deviceID
                    && $0.target.targetPath == target.targetPath
            }
        }
        let existingAttachSessions = Dictionary(
            uniqueKeysWithValues: sessions
                .filter { $0.target.mode == .attach || $0.target.mode == .attachURL }
                .map { ($0.id, $0) }
        )
        let reusableAttachIDs = Set(discoveredTargets.compactMap { target -> String? in
            guard let existing = existingAttachSessions[target.id],
                  existing.target.vmServiceURL == target.vmServiceURL else {
                return nil
            }
            return target.id
        })
        for session in sessions where (session.target.mode == .attach || session.target.mode == .attachURL)
            && !reusableAttachIDs.contains(session.id) {
            session.stop()
        }
        sessions = managedSessions + discoveredTargets.map { target in
            existingAttachSessions[target.id].flatMap {
                reusableAttachIDs.contains(target.id) ? $0 : nil
            } ?? makeSession(target, settings.flutterExecutable)
        }

        discoveryStatus = DiscoverySummary(
            discoveredTargetCount: discoveredTargets.count,
            skippedRuns: snapshot.skippedRuns,
            unsupportedRuns: snapshot.unsupportedRuns,
            ideManagedRuns: snapshot.ideManagedRuns
        ).statusText
    }

    private func finishDiscovery(snapshot: DiscoverySnapshot?, errorMessage: String?) {
        isDiscovering = false
        guard let snapshot else {
            discoveryStatus = "Discovery failed: \(errorMessage ?? "Unknown error")"
            return
        }
        applyDiscovery(snapshot)
    }

    private func scheduleDiscoveryTimer() {
        discoveryTimer?.invalidate()
        discoveryTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(settings.discoveryInterval),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshDiscovery() }
        }
    }
}
