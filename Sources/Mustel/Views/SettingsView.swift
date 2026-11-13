import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsViewModel
    let updates: UpdateViewModel
    @State private var isExpanded = false
    @State private var contentOpacity = 0.0
    @State private var gearAngle = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                toggleExpanded()
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
                            Text("Animate the logo")
                            Text("Show the running ferret while Mustel works. Turn off to keep a static icon.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("Animate the logo", isOn: $settings.animationsEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
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
                            .disabled(!settings.animationsEnabled)
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

                    Divider()
                    sectionTitle("UPDATES")
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Version \(updates.currentVersionText)")
                            Text(updateStatusText)
                                .font(.caption)
                                .foregroundStyle(updateStatusColor)
                                .fixedSize(horizontal: false, vertical: true)
                            if case let .downloading(progress) = updates.state {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        updateButton
                    }
                    if let asset = updates.visualStudioCodeUpdate {
                        ideUpdateRow(
                            title: "VS Code bridge",
                            asset: asset,
                            installed: updates.installedIDEVersions.visualStudioCode
                        )
                    }
                    if let asset = updates.intellijUpdate {
                        ideUpdateRow(
                            title: "IntelliJ bridge",
                            asset: asset,
                            installed: updates.installedIDEVersions.intellij
                        )
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(contentOpacity)
                .animation(reduceMotion ? nil : .easeIn(duration: 0.18), value: contentOpacity)
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                updates.checkForUpdatesIfNeeded()
            }
        }
    }

    private func toggleExpanded() {
        let expanded = !isExpanded
        isExpanded = expanded
        contentOpacity = 0
        DispatchQueue.main.async {
            guard expanded == isExpanded else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                gearAngle = expanded ? 90 : 0
            }
            if expanded {
                contentOpacity = 1
            }
        }
    }

    @ViewBuilder
    private var updateButton: some View {
        switch updates.state {
        case .available:
            Button("Update") {
                updates.installAvailableUpdate()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .checking, .downloading, .installing:
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
        default:
            Button("Check") {
                updates.checkForUpdates()
            }
            .controlSize(.small)
            .glassButtonStyleIfAvailable()
            .disabled(updates.isBusy)
        }
    }

    private var updateStatusText: String {
        switch updates.state {
        case .idle:
            return "Check GitHub for a newer version."
        case .checking:
            return "Checking for updates…"
        case .upToDate:
            return "You are up to date."
        case .noReleases:
            return "No releases published yet."
        case let .available(release):
            return "\(release.displayVersion) is available."
        case let .downloading(progress):
            return "Downloading… \(Int(progress * 100))%"
        case .installing:
            return "Installing… Mustel will restart."
        case let .failed(message):
            return message
        }
    }

    private var updateStatusColor: Color {
        if case .failed = updates.state {
            return .red
        }
        return .secondary
    }

    private func ideUpdateRow(title: String, asset: UpdateAsset, installed: AppVersion?) -> some View {
        HStack(spacing: 6) {
            Text("\(title) update: \(installed.map { "v\($0)" } ?? "installed") → \(asset.version.map { "v\($0)" } ?? "new")")
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Link("Download", destination: asset.url)
        }
        .font(.caption2)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }
}
