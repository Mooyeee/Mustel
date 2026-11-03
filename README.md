# Mustel

**A little ferret for your Flutter hot reloads.**

Mustel is a macOS menu-bar app that puts hot reload and hot restart within reach while you work. It can discover supported Flutter runs, control Dart/Flutter debug sessions already running in VS Code, or launch a Flutter project itself. Its goal is to make the quick feedback loop easy to reach without switching back to a terminal or interrupting your current workflow.

The name comes from *Mustela*, the genus that includes ferrets and weasels: curious little creatures that like to get into things. In the same spirit, Mustel gets its paws on Flutter's reload controls.

## Contents

- [What it does](#what-it-does)
- [Requirements](#requirements)
- [Install the macOS app](#install-the-macos-app)
- [Install the VS Code bridge](#install-the-vs-code-bridge)
- [Using Mustel](#using-mustel)
- [Privacy and local bridge](#privacy-and-local-bridge)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [Known limitations](#known-limitations)
- [License](#license)

## What it does

- **Lives in the macOS menu bar.** Click the ferret to open Mustel; right-click it to quit.
- **Discovers existing mobile Flutter runs.** Mustel scans for supported Android and iOS runs and attaches to them automatically.
- **Controls VS Code debug sessions.** With the companion extension installed, use hot reload and hot restart on active Dart/Flutter sessions in one or more VS Code windows. Mustel sends the request to Dart Code; it does not start a competing `flutter attach` for those sessions.
- **Launches Flutter projects.** Choose a project and device in Mustel to start and control a new `flutter run --machine` session, including macOS desktop and web targets.
- **Supports desktop/web VM Service discovery when enabled.** Start a run with `--vmservice-out-file` and Mustel can read the VM Service URL from the file.
- **Can launch at login.** Enable **Launch at login** in Settings after installing the app.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools and Swift 5.9 or later
- Flutter installed and available as `flutter`, or the path to its executable
- `librsvg` (`rsvg-convert`) to generate the app icons
- For VS Code integration: VS Code 1.85 or later and the [Dart extension](https://marketplace.visualstudio.com/items?itemName=Dart-Code.dart-code)

## Install the macOS app

Clone the repository, then from its directory run:

```sh
brew install librsvg
./scripts/install-app.sh
open "$HOME/Applications/Mustel.app"
```

The installer generates the icons from [`Resources/ferret.svg`](./Resources/ferret.svg), builds the release app, installs it in `~/Applications`, and verifies its code signature. Run the installer again after pulling updates.

The app is locally ad-hoc signed and **not notarized**. This setup is intended for building from source on your own Mac, not distributing a ready-to-run app to other people. Launch at login uses Apple's `SMAppService` API to start the regular app in your user session; Mustel is not a privileged daemon. If macOS requests approval, allow it under **System Settings → General → Login Items**.

## Install the VS Code bridge

The bridge is a separate extension. Build and package it from the repository:

```sh
cd vscode-extension
npm install
npm run compile
npx @vscode/vsce package
```

Use a current Node.js release for VSIX packaging. Install the generated `local.mustel-vscode-0.1.0.vsix` in VS Code with **Extensions: Install from VSIX...**, or from a terminal:

```sh
code --install-extension local.mustel-vscode-0.1.0.vsix
```

Reload the VS Code window if it was already open. Start a Dart/Flutter debug session; it will appear in Mustel's **VS Code** section with its own hot reload and hot restart controls. The extension requires the Dart extension to be installed and enabled.

## Using Mustel

### Control an existing mobile run

Start a Flutter app on a supported Android or iOS device as usual. Mustel periodically scans for eligible runs; use the refresh button to scan immediately. Select its reload or restart control from the menu-bar popover.

If more than one supported device is connected, specify the device when starting the run so Mustel can match it unambiguously:

```sh
flutter run -d <device-id>
```

### Control an existing VS Code session

Install and enable the bridge extension, then start or keep a Dart/Flutter debug session active in VS Code. Mustel lists sessions from each open VS Code window and sends the selected action to that session through Dart Code.

### Launch a project from Mustel

Click **+**, choose a Flutter project folder and a connected device, and select **Run**. Mustel starts and manages the `flutter run --machine` process. The launched session has its own reload, restart, and stop controls.

### Discover an existing desktop or web run

Flutter does not provide a reliable place for Mustel to discover the authenticated VM Service URL for an already-running desktop or web app by default. To opt in, start the run with an output file:

```sh
flutter run -d macos --vmservice-out-file=/tmp/my-app-vmservice.json
```

Mustel reads the URL from that file and attaches to it. The file must contain the URL for the current run; stale URLs are ignored. Alternatively, launch the desktop or web project from Mustel.

## Privacy and local bridge

The VS Code bridge is local to your Mac. The extension and app communicate through per-user files and Unix domain sockets; the bridge does not expose a network listener or require a cloud service. The bridge directory is restricted to the current user, socket files are owner-only, and Mustel validates the socket paths it reads. The extension accepts requests only for active Dart debug sessions in the VS Code extension host that owns those sessions, and supports only hot reload and hot restart commands.

Mustel invokes the Flutter executable you configure. Flutter itself may perform its normal network operations, for example when resolving packages or running a project; those are not relayed through Mustel's VS Code bridge.

## Troubleshooting

- **Mustel cannot find Flutter:** open **Settings → Flutter executable** and enter the absolute path to the `flutter` executable. Apps launched from Finder may not inherit the same shell `PATH` as Terminal.
- **An existing run is missing:** refresh discovery. For mobile runs with multiple connected devices, restart with `flutter run -d <device-id>`. Desktop/web runs need `--vmservice-out-file` to be discovered automatically.
- **Attach reports that `.dart_tool/package_graph.json` is missing:** run `flutter pub get` in the project directory, then reconnect.
- **VS Code sessions do not appear:** confirm the Dart extension and Mustel Bridge are enabled, start a Dart/Flutter debug session, and reload VS Code after installing the VSIX.
- **Launch at login is unavailable:** install and open `~/Applications/Mustel.app`; it is not available when running with `swift run`.

## Development

Build and run the menu-bar app from source:

```sh
swift build --configuration debug --product mustel
swift run mustel
```

Build the release app and install it with the same script used above:

```sh
./scripts/install-app.sh
```

Compile the VS Code extension:

```sh
cd vscode-extension
npm install
npm run compile
```

For extension development, open `vscode-extension/` in VS Code, press **F5** to launch an Extension Development Host, then start a Flutter debug session there while Mustel is running.

## Known limitations

- Automatic discovery of existing non-IDE-managed runs supports Android and iOS. Existing macOS desktop and web runs need `--vmservice-out-file`; starting a new desktop or web run from Mustel is also supported.
- When a mobile run does not specify a device ID, automatic matching is possible only when exactly one supported device is connected.
- Mustel skips IDE-managed Flutter runs during process discovery to avoid competing with the IDE's Flutter tool. Use the VS Code bridge for sessions managed by VS Code.
- Attaching to an external Flutter run can involve a second Flutter tool client and may conflict with the original run. For an owned session, launch it from Mustel; for a VS Code session, use the bridge.
- Flutter machine-protocol behavior can vary between Flutter SDK versions.

## License

Mustel is licensed under the [MIT License](./LICENSE).
