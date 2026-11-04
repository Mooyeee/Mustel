import XCTest
@testable import Mustel

final class FlutterDiscoveryServiceTests: XCTestCase {
    func testDiscoversAttachTarget() throws {
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let runner = FakeProcessRunner(outputs: [
            "/usr/bin/env /custom/flutter devices --machine": #"[{"id":"emulator-5554","name":"Pixel","targetPlatform":"android-arm64","isSupported":true}]"#,
            "/bin/ps -axo pid=,command=": "123 /Users/me/flutter/bin/flutter run -d emulator-5554\n",
            "/usr/sbin/lsof -a -p 123 -d cwd -Fn": "p123\nfcwd\nn\(project.path)\n"
        ])
        let snapshot = try FlutterDiscoveryService(processRunner: runner)
            .discover(flutterExecutable: "/custom/flutter")

        XCTAssertEqual(snapshot.devices.count, 1)
        XCTAssertEqual(snapshot.targets.count, 1)
        XCTAssertEqual(snapshot.targets.first?.mode, .attach)
        XCTAssertEqual(snapshot.targets.first?.deviceID, "emulator-5554")
        XCTAssertEqual(snapshot.targets.first?.projectPath, project.path)
        XCTAssertEqual(snapshot.skippedRuns, 0)
        XCTAssertEqual(snapshot.unsupportedRuns, 0)
        XCTAssertEqual(snapshot.ideManagedRuns, 0)
    }

    func testSkipsIDEManagedRuns() throws {
        let runner = FakeProcessRunner(outputs: [
            "/usr/bin/env /custom/flutter devices --machine": "[]",
            "/bin/ps -axo pid=,command=": "123 /Users/me/flutter/bin/flutter run --machine\n"
        ])
        let snapshot = try FlutterDiscoveryService(processRunner: runner)
            .discover(flutterExecutable: "/custom/flutter")

        XCTAssertTrue(snapshot.targets.isEmpty)
        XCTAssertEqual(snapshot.ideManagedRuns, 1)
    }

    func testSkipsAmbiguousRunWithoutDeviceID() throws {
        let runner = FakeProcessRunner(outputs: [
            "/usr/bin/env /custom/flutter devices --machine": #"[{"id":"a","name":"A","targetPlatform":"android-arm64","isSupported":true},{"id":"b","name":"B","targetPlatform":"ios","isSupported":true}]"#,
            "/bin/ps -axo pid=,command=": "123 /Users/me/flutter/bin/flutter run\n"
        ])
        let snapshot = try FlutterDiscoveryService(processRunner: runner)
            .discover(flutterExecutable: "/custom/flutter")

        XCTAssertTrue(snapshot.targets.isEmpty)
        XCTAssertEqual(snapshot.skippedRuns, 1)
    }

    func testDiscoversDesktopRunFromServiceFile() throws {
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let serviceFile = project.appendingPathComponent("vmservice.json")
        try Data(#"{"uri":"ws://127.0.0.1:1234/ws"}"#.utf8).write(to: serviceFile)

        let start = processStartDateString(offset: -60)
        let runner = FakeProcessRunner(outputs: [
            "/usr/bin/env /custom/flutter devices --machine": #"[{"id":"macos","name":"macOS","targetPlatform":"darwin","isSupported":true}]"#,
            "/bin/ps -axo pid=,command=": "456 /Users/me/flutter/bin/flutter run -d macos --vmservice-out-file=\(serviceFile.path)\n",
            "/usr/sbin/lsof -a -p 456 -d cwd -Fn": "p456\nfcwd\nn\(project.path)\n",
            "/bin/ps -o lstart= -p 456": start
        ])
        let snapshot = try FlutterDiscoveryService(processRunner: runner)
            .discover(flutterExecutable: "/custom/flutter")

        XCTAssertEqual(snapshot.targets.first?.mode, .attachURL)
        XCTAssertEqual(snapshot.targets.first?.vmServiceURL, "ws://127.0.0.1:1234/ws")
        XCTAssertEqual(snapshot.unsupportedRuns, 0)
    }

    func testRejectsStaleServiceFile() throws {
        let project = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let serviceFile = project.appendingPathComponent("vmservice.json")
        try Data(#"{"uri":"ws://127.0.0.1:1234/ws"}"#.utf8).write(to: serviceFile)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-600)],
            ofItemAtPath: serviceFile.path
        )

        let start = processStartDateString(offset: -60)
        let runner = FakeProcessRunner(outputs: [
            "/usr/bin/env /custom/flutter devices --machine": #"[{"id":"macos","name":"macOS","targetPlatform":"darwin","isSupported":true}]"#,
            "/bin/ps -axo pid=,command=": "456 /Users/me/flutter/bin/flutter run -d macos --vmservice-out-file=\(serviceFile.path)\n",
            "/usr/sbin/lsof -a -p 456 -d cwd -Fn": "p456\nfcwd\nn\(project.path)\n",
            "/bin/ps -o lstart= -p 456": start
        ])
        let snapshot = try FlutterDiscoveryService(processRunner: runner)
            .discover(flutterExecutable: "/custom/flutter")

        XCTAssertTrue(snapshot.targets.isEmpty)
        XCTAssertEqual(snapshot.unsupportedRuns, 1)
    }

    func testParsesDeviceIDVariants() {
        XCTAssertEqual(FlutterDiscoveryService.deviceID(in: "flutter run -d emulator-5554"), "emulator-5554")
        XCTAssertEqual(FlutterDiscoveryService.deviceID(in: "flutter run --device-id emulator-5554"), "emulator-5554")
        XCTAssertEqual(FlutterDiscoveryService.deviceID(in: "flutter run --device-id=emulator-5554"), "emulator-5554")
        XCTAssertNil(FlutterDiscoveryService.deviceID(in: "flutter run"))
    }

    func testParsesTargetPathVariants() {
        XCTAssertEqual(FlutterDiscoveryService.targetPath(in: "flutter run -t lib/main.dart"), "lib/main.dart")
        XCTAssertEqual(FlutterDiscoveryService.targetPath(in: "flutter run --target lib/main.dart"), "lib/main.dart")
        XCTAssertEqual(FlutterDiscoveryService.targetPath(in: "flutter run --target=lib/main.dart"), "lib/main.dart")
        XCTAssertEqual(FlutterDiscoveryService.targetPath(in: "flutter run -tlib/main.dart"), "lib/main.dart")
        XCTAssertNil(FlutterDiscoveryService.targetPath(in: "flutter run"))
    }

    func testParsesServiceInfoPathVariants() {
        XCTAssertEqual(
            FlutterDiscoveryService.serviceInfoPath(in: "flutter run --vmservice-out-file /tmp/a.json"),
            "/tmp/a.json"
        )
        XCTAssertEqual(
            FlutterDiscoveryService.serviceInfoPath(in: "flutter run --vmservice-out-file=/tmp/a.json"),
            "/tmp/a.json"
        )
        XCTAssertNil(FlutterDiscoveryService.serviceInfoPath(in: "flutter run"))
    }

    func testDetectsFlutterRunCommands() {
        XCTAssertTrue(FlutterDiscoveryService.isFlutterRun("/Users/me/flutter/bin/flutter run -d a"))
        XCTAssertTrue(FlutterDiscoveryService.isFlutterRun("/Users/me/flutter/bin/flutter_tools.snapshot run -d a"))
        XCTAssertFalse(FlutterDiscoveryService.isFlutterRun("/Users/me/flutter/bin/flutter test"))
        XCTAssertFalse(FlutterDiscoveryService.isFlutterRun("/usr/bin/dart run"))
    }

    func testDetectsMachineMode() {
        XCTAssertTrue(FlutterDiscoveryService.isMachineMode("flutter run --machine"))
        XCTAssertTrue(FlutterDiscoveryService.isMachineMode("flutter run --machine=true"))
        XCTAssertFalse(FlutterDiscoveryService.isMachineMode("flutter run -d macos"))
    }

    func testParsesProcessLine() {
        let process = FlutterDiscoveryService.parseProcess("  123 /Users/me/flutter/bin/flutter run")
        XCTAssertEqual(process?.pid, 123)
        XCTAssertEqual(process?.command, "/Users/me/flutter/bin/flutter run")
        XCTAssertNil(FlutterDiscoveryService.parseProcess("not-a-pid flutter run"))
    }

    private func processStartDateString(offset: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter.string(from: Date().addingTimeInterval(offset))
    }
}
