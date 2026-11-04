import XCTest
@testable import Mustel

@MainActor
final class LaunchFormViewModelTests: XCTestCase {
    private let device = FlutterDeviceInfo(
        id: "device-1",
        name: "Pixel",
        targetPlatform: "android-arm64",
        isSupported: true
    )

    func testChooseProjectUsesPicker() {
        let form = LaunchFormViewModel(projectPicker: FakeProjectPicker(path: "/tmp/App"))

        form.chooseProject()

        XCTAssertEqual(form.projectPath, "/tmp/App")
        XCTAssertNil(form.error)
    }

    func testToggleClearsErrorAndDismissResetsEntrypoint() {
        let form = LaunchFormViewModel(projectPicker: FakeProjectPicker(path: nil))

        form.toggle()
        XCTAssertTrue(form.isPresented)

        form.setError("boom")
        form.toggle()
        XCTAssertFalse(form.isPresented)
        XCTAssertNil(form.error)

        form.isPresented = true
        form.targetPath = "lib/main_dev.dart"
        form.dismiss()
        XCTAssertFalse(form.isPresented)
        XCTAssertEqual(form.targetPath, "")
    }

    func testValidateRequiresPubspec() throws {
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }
        try FileManager.default.removeItem(at: project.appendingPathComponent("pubspec.yaml"))

        let form = LaunchFormViewModel(projectPicker: FakeProjectPicker(path: nil))
        form.projectPath = project.path
        form.selectedDeviceID = device.id

        XCTAssertEqual(
            form.validate(devices: [device]),
            "Choose a Flutter project folder containing pubspec.yaml."
        )
    }

    func testValidateRequiresSupportedDevice() throws {
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let form = LaunchFormViewModel(projectPicker: FakeProjectPicker(path: nil))
        form.projectPath = project.path
        form.selectedDeviceID = "missing"

        XCTAssertEqual(form.validate(devices: [device]), "Choose an available Flutter device.")
    }

    func testMakeTargetTrimsEmptyEntrypoint() throws {
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let form = LaunchFormViewModel(projectPicker: FakeProjectPicker(path: nil))
        form.projectPath = project.path
        form.selectedDeviceID = device.id
        form.targetPath = "   "

        let target = form.makeTarget(devices: [device])

        XCTAssertEqual(target?.mode, .run)
        XCTAssertEqual(target?.projectPath, project.path)
        XCTAssertEqual(target?.deviceID, device.id)
        XCTAssertNil(target?.targetPath)
        XCTAssertEqual(target?.name, "\(project.lastPathComponent) · Pixel")
    }

    func testMakeTargetKeepsCustomEntrypoint() throws {
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let form = LaunchFormViewModel(projectPicker: FakeProjectPicker(path: nil))
        form.projectPath = project.path
        form.selectedDeviceID = device.id
        form.targetPath = " lib/main_dev.dart "

        let target = form.makeTarget(devices: [device])

        XCTAssertEqual(target?.targetPath, "lib/main_dev.dart")
    }
}
