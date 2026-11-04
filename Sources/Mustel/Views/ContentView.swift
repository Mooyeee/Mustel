import SwiftUI

struct ContentView: View {
    let model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Text(model.discoveryStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            VSCodeSectionView(
                sessions: model.vscodeSessions,
                status: model.vscodeBridgeStatus,
                commandStatuses: model.vscodeCommandStatuses,
                onRefresh: model.refreshVSCodeSessions,
                onCommand: { command, target in
                    model.runVSCodeCommand(command, on: target)
                }
            )

            sessionSection

            if model.launchForm.isPresented {
                Divider()
                LaunchFormView(
                    form: model.launchForm,
                    devices: model.devices,
                    onRun: model.launch
                )
            } else if !model.sessions.isEmpty {
                Divider()
            }

            SettingsView(settings: model.settings)
        }
        .padding(14)
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            Text("Mustel")
                .font(.title3.weight(.semibold))
            Spacer()
            Button(action: model.refreshDiscovery) {
                if model.isDiscovering {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                        Text("Scanning active Flutter runs…")
                            .font(.caption)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeIn(duration: 0.12).delay(0.08)),
                        removal: .opacity.animation(.easeOut(duration: 0.06))
                    ))
                } else {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 16, height: 16)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeIn(duration: 0.12).delay(0.08)),
                            removal: .opacity.animation(.easeOut(duration: 0.06))
                        ))
                }
            }
            .disabled(model.isDiscovering)
            .help("Discover running Flutter apps")
            .glassButtonStyleIfAvailable()
            Button {
                model.launchForm.toggle()
            } label: {
                Image(systemName: model.launchForm.isPresented ? "xmark" : "plus")
                    .frame(width: 16, height: 16)
            }
            .help(model.launchForm.isPresented ? "Cancel launch" : "Launch a Flutter project")
            .glassButtonStyleIfAvailable()
        }
        .animation(.easeInOut(duration: 0.2), value: model.isDiscovering)
    }

    @ViewBuilder
    private var sessionSection: some View {
        if model.sessions.count == 1, let session = model.sessions.first {
            SessionRow(
                session: session,
                onReconnect: { model.reconnect(session) },
                onStop: { model.stop(session) },
                onRemove: { model.remove(session) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.sessions.count > 1 {
            ScrollViewIfNeeded(maxHeight: 300) {
                VStack(spacing: 8) {
                    ForEach(model.sessions) { session in
                        SessionRow(
                            session: session,
                            onReconnect: { model.reconnect(session) },
                            onStop: { model.stop(session) },
                            onRemove: { model.remove(session) }
                        )
                    }
                }
            }
        } else if !model.launchForm.isPresented {
            DiscoveryBanner(extensionInstalled: model.vscodeExtensionInstalled)
        }
    }
}
