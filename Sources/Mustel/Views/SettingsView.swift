import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsViewModel
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 16, weight: .heavy))
                    .rotationEffect(.degrees(isExpanded ? 0 : 180))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isExpanded ? "Hide settings" : "Show settings")

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Flutter executable")
                            .font(.caption.weight(.medium))
                        TextField("flutter or absolute path", text: $settings.flutterExecutable)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        Text("If Flutter is not found, enter its absolute path.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Scan for new runs")
                            .font(.caption.weight(.medium))
                        Picker("Scan for new runs", selection: $settings.discoveryInterval) {
                            ForEach(SettingsViewModel.discoveryIntervalOptions, id: \.self) { interval in
                                Text(SettingsViewModel.discoveryIntervalLabel(for: interval))
                                    .tag(interval)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .font(.caption)
                        Text("How often Mustel looks for new Flutter runs.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(
                            "Launch at login",
                            isOn: Binding(
                                get: { settings.launchAtLoginEnabled },
                                set: { settings.setLaunchAtLogin($0) }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .disabled(!settings.canConfigureLaunchAtLogin)
                        .glassPlateIfAvailable()
                        if let message = settings.launchAtLoginError ?? settings.launchAtLoginMessage {
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(settings.launchAtLoginError == nil ? Color.secondary : Color.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
        }
    }
}
