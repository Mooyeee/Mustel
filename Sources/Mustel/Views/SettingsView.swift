import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsViewModel
    @State private var isExpanded = false
    @State private var gearAngle = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                isExpanded.toggle()
                let expanded = isExpanded
                DispatchQueue.main.async {
                    guard expanded == isExpanded else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                        gearAngle = expanded ? 90 : 0
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Color.clear
                        .frame(width: 18, height: 18)
                        .overlay {
                            Image(systemName: "gearshape.fill")
                                .rotationEffect(.degrees(gearAngle))
                        }
                    Text("Settings")
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isExpanded ? "Hide settings" : "Show settings")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("DISCOVERY")
                    HStack {
                        Text("Scan for new runs")
                        Spacer()
                        Picker("Scan for new runs", selection: $settings.discoveryInterval) {
                            ForEach(SettingsViewModel.discoveryIntervalOptions, id: \.self) { interval in
                                Text(SettingsViewModel.discoveryIntervalLabel(for: interval))
                                    .tag(interval)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    Divider()
                    sectionTitle("FLUTTER SDK")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Flutter executable")
                        TextField("flutter or absolute path", text: $settings.flutterExecutable)
                            .textFieldStyle(.roundedBorder)
                        Text("If Flutter is not found, enter its absolute path.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()
                    sectionTitle("APPEARANCE")
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Always animate the logo")
                            Text("Keep the running ferret animation active when Mustel is not scanning.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("Always animate the logo", isOn: $settings.alwaysAnimateLogo)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()
                    sectionTitle("GENERAL")
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Launch at login")
                            if let message = settings.launchAtLoginError ?? settings.launchAtLoginMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(settings.launchAtLoginError == nil ? Color.secondary : Color.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle(
                            "Launch at login",
                            isOn: Binding(
                                get: { settings.launchAtLoginEnabled },
                                set: { settings.setLaunchAtLogin($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!settings.canConfigureLaunchAtLogin)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }
}
