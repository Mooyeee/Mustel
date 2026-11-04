import Foundation
import Observation

@MainActor
protocol ProjectPicking {
    func chooseProject() -> String?
}

@Observable
@MainActor
final class LaunchFormViewModel {
    var projectPath = ""
    var targetPath = ""
    var selectedDeviceID = ""
    var isPresented = false
    private(set) var error: String?

    @ObservationIgnored private let projectPicker: ProjectPicking

    init(projectPicker: ProjectPicking? = nil) {
        self.projectPicker = projectPicker ?? NSOpenPanelProjectPicker()
    }

    func toggle() {
        isPresented.toggle()
        error = nil
    }

    func dismiss() {
        isPresented = false
        error = nil
        targetPath = ""
    }

    func setError(_ message: String?) {
        error = message
    }

    func chooseProject() {
        guard let path = projectPicker.chooseProject() else { return }
        projectPath = path
        error = nil
    }

    func validate(devices: [FlutterDeviceInfo]) -> String? {
        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("pubspec.yaml").path) else {
            return "Choose a Flutter project folder containing pubspec.yaml."
        }
        guard devices.contains(where: { $0.id == selectedDeviceID && $0.isSupported }) else {
            return "Choose an available Flutter device."
        }
        return nil
    }

    func makeTarget(devices: [FlutterDeviceInfo]) -> FlutterTarget? {
        guard validate(devices: devices) == nil,
              let device = devices.first(where: { $0.id == selectedDeviceID && $0.isSupported }) else {
            return nil
        }
        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        let customTarget = targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return FlutterTarget(
            id: "run:\(UUID().uuidString)",
            name: "\(projectURL.lastPathComponent) · \(device.name)",
            projectPath: projectURL.path,
            deviceID: device.id,
            targetPath: customTarget.isEmpty ? nil : customTarget,
            vmServiceURL: nil,
            mode: .run
        )
    }
}
