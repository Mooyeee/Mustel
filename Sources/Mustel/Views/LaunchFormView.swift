import SwiftUI

struct LaunchFormView: View {
    @Bindable var form: LaunchFormViewModel
    let devices: [FlutterDeviceInfo]
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Launch Flutter app")
                .font(.headline)
            HStack {
                Text(form.projectPath.isEmpty
                     ? "Choose a project folder…"
                     : URL(fileURLWithPath: form.projectPath).lastPathComponent)
                    .lineLimit(1)
                    .foregroundStyle(form.projectPath.isEmpty ? Color.secondary : Color.primary)
                Spacer()
                Button("Choose…", action: form.chooseProject)
                    .glassButtonStyleIfAvailable()
            }
            Picker("Device", selection: $form.selectedDeviceID) {
                ForEach(devices) { device in
                    Text("\(device.name) (\(device.targetPlatform))")
                        .tag(device.id)
                }
            }
            .disabled(devices.isEmpty)
            TextField("Entrypoint (optional, e.g. lib/main_dev.dart)", text: $form.targetPath)
                .textFieldStyle(.roundedBorder)
            if devices.isEmpty {
                Text("No supported Flutter devices found yet. Refresh or check the Flutter executable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = form.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Run", action: onRun)
                    .keyboardShortcut(.defaultAction)
                    .disabled(form.projectPath.isEmpty || form.selectedDeviceID.isEmpty)
                    .glassButtonStyleIfAvailable()
            }
        }
    }
}
