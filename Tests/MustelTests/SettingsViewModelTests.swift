import XCTest
@testable import Mustel

@MainActor
final class SettingsViewModelTests: XCTestCase {
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

    func testLoadsStoredValues() {
        let store = SettingsStore(defaults: defaults)
        store.flutterExecutable = "/custom/flutter"
        store.discoveryInterval = 30

        let settings = SettingsViewModel(store: store, launchAtLogin: FakeLaunchAtLogin())

        XCTAssertEqual(settings.flutterExecutable, "/custom/flutter")
        XCTAssertEqual(settings.discoveryInterval, 30)
    }

    func testInvalidStoredIntervalFallsBackToDefault() {
        let store = SettingsStore(defaults: defaults)
        store.discoveryInterval = 7

        let settings = SettingsViewModel(store: store, launchAtLogin: FakeLaunchAtLogin())

        XCTAssertEqual(settings.discoveryInterval, 5)
    }

    func testPersistsValuesAndNotifiesOnIntervalChange() {
        let store = SettingsStore(defaults: defaults)
        let settings = SettingsViewModel(store: store, launchAtLogin: FakeLaunchAtLogin())
        var notifications = 0
        settings.onDiscoveryIntervalChanged = { notifications += 1 }

        settings.flutterExecutable = "/new/flutter"
        settings.discoveryInterval = 60

        XCTAssertEqual(store.flutterExecutable, "/new/flutter")
        XCTAssertEqual(store.discoveryInterval, 60)
        XCTAssertEqual(notifications, 1)

        settings.discoveryInterval = 60
        XCTAssertEqual(notifications, 1)
    }

    func testLaunchAtLoginTogglesService() {
        let service = FakeLaunchAtLogin()
        let settings = SettingsViewModel(store: SettingsStore(defaults: defaults), launchAtLogin: service)

        XCTAssertFalse(settings.launchAtLoginEnabled)

        settings.setLaunchAtLogin(true)

        XCTAssertTrue(service.isEnabled)
        XCTAssertTrue(settings.launchAtLoginEnabled)
        XCTAssertNil(settings.launchAtLoginError)
    }

    func testLaunchAtLoginFailureIsReported() {
        let service = FakeLaunchAtLogin()
        service.error = TestError.failed("denied")
        let settings = SettingsViewModel(store: SettingsStore(defaults: defaults), launchAtLogin: service)

        settings.setLaunchAtLogin(true)

        XCTAssertEqual(settings.launchAtLoginError, "denied")
    }

    func testPersistsAlwaysAnimateLogo() {
        let store = SettingsStore(defaults: defaults)
        let settings = SettingsViewModel(store: store, launchAtLogin: FakeLaunchAtLogin())
        var notifications: [Bool] = []
        settings.onAlwaysAnimateLogoChanged = { notifications.append($0) }

        settings.alwaysAnimateLogo = true

        XCTAssertTrue(store.alwaysAnimateLogo)
        XCTAssertEqual(notifications, [true])

        settings.alwaysAnimateLogo = true
        XCTAssertEqual(notifications, [true])
    }

    func testLoadsStoredAlwaysAnimateLogo() {
        let store = SettingsStore(defaults: defaults)
        store.alwaysAnimateLogo = true

        let settings = SettingsViewModel(store: store, launchAtLogin: FakeLaunchAtLogin())

        XCTAssertTrue(settings.alwaysAnimateLogo)
    }

    func testIntervalLabels() {
        XCTAssertEqual(SettingsViewModel.discoveryIntervalLabel(for: 5), "Every 5 seconds")
        XCTAssertEqual(SettingsViewModel.discoveryIntervalLabel(for: 60), "Every minute")
        XCTAssertEqual(SettingsViewModel.discoveryIntervalLabel(for: 300), "Every 5 minutes")
    }
}
