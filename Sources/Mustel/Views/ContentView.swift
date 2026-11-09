import AppKit
import SwiftUI

struct ContentView: View {
    let model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: model.hasCheckedIDEBridge
                      ? (model.ideBridgeInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                      : "circle.dotted")
                    .foregroundStyle(model.hasCheckedIDEBridge
                                     ? (model.ideBridgeInstalled ? Color.green : Color.yellow)
                                     : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.hasCheckedIDEBridge
                         ? (model.ideBridgeInstalled ? "IDE bridge installed" : "IDE bridge not installed")
                         : "Checking IDE bridge installation…")
                        .foregroundStyle(.primary)
                    Text(model.ideBridgeStatus)
                        .foregroundStyle(.secondary)
                    if model.hasCheckedIDEBridge && !model.ideBridgeInstalled {
                        Text("For existing desktop/web runs, use --vmservice-out-file or launch from here.")
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)

            Divider()
            sessionSection

            Divider()
            SettingsView(settings: model.settings)
        }
        .padding(14)
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            LogoView(animator: model.logoAnimator)
            Text("Mustel")
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                model.refreshDiscovery()
                model.refreshIDESessions()
            } label: {
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
            .help("Refresh Flutter runs and IDE sessions")
            .squareIconButtonStyle(isExpanded: model.isDiscovering)
            Button {
                model.launchForm.toggle()
            } label: {
                Image(systemName: model.launchForm.isPresented ? "xmark" : "plus")
                    .frame(width: 16, height: 16)
            }
            .help(model.launchForm.isPresented ? "Cancel launch" : "Launch a Flutter project")
            .squareIconButtonStyle()
            .popover(
                isPresented: Binding(
                    get: { model.launchForm.isPresented },
                    set: { presented in
                        if model.launchForm.isPresented != presented {
                            model.launchForm.toggle()
                        }
                    }
                ),
                arrowEdge: .top
            ) {
                LaunchFormView(
                    form: model.launchForm,
                    devices: model.devices,
                    onRun: model.launch
                )
                .padding(14)
                .frame(width: 320)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isDiscovering)
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewIfNeeded(maxHeight: 300) {
                VStack(alignment: .leading, spacing: 8) {
                    sessionTitle("IDE SESSIONS")
                    if model.ideSessions.isEmpty {
                        emptySessions("No IDE sessions")
                    }
                    ForEach(model.ideSessions) { target in
                        IDESessionRow(
                            target: target,
                            status: model.ideCommandStatuses[target.id],
                            onHotReload: { model.runIDECommand(.hotReload, on: target) },
                            onHotRestart: { model.runIDECommand(.hotRestart, on: target) }
                        )
                    }
                    if !model.sessions.isEmpty {
                        sessionTitle("OTHER SESSIONS")
                    }
                    ForEach(model.sessions) { session in
                        SessionRow(
                            session: session,
                            platformHint: model.devices.first(where: { $0.id == session.target.deviceID })?
                                .targetPlatform ?? "\(session.target.name) \(session.target.deviceID)",
                            onReconnect: { model.reconnect(session) },
                            onStop: { model.stop(session) },
                            onRemove: { model.remove(session) }
                        )
                    }
                }
            }
            Text(model.discoveryStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sessionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func emptySessions(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
