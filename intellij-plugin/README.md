# Mustel Bridge for IntelliJ IDEA and Android Studio

The Mustel Bridge exposes active Flutter run configurations to the [Mustel macOS menu-bar app](../README.md). It forwards hot reload and hot restart requests through the Flutter plugin, so Mustel does not start a second `flutter attach` for IDE-managed runs.

## Requirements

- macOS (Mustel itself is macOS-only)
- IntelliJ IDEA or Android Studio 2023.1 or later
- The Flutter and Dart plugins installed and enabled
- Java 17 or later for building

## Build

```sh
./gradlew buildPlugin
```

The installable ZIP is written to `build/distributions/mustel-intellij-0.1.0.zip`. Install it with **Settings → Plugins → Install Plugin from Disk...**, then restart the IDE.

The default build targets IntelliJ IDEA Community 2023.1 and resolves compatible Flutter/Dart plugins from the JetBrains repositories. To build against an already installed IDE instead, pass the local paths:

```sh
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew buildPlugin \
  -Pmustel.localIde="/Applications/Android Studio.app/Contents" \
  -Pmustel.flutterPlugin="$HOME/Library/Application Support/Google/AndroidStudio2025.3.1/plugins/flutter-intellij" \
  -Pmustel.dartPlugin="$HOME/Library/Application Support/Google/AndroidStudio2025.3.1/plugins/Dart" \
  -Pmustel.lsp4ijPlugin="$HOME/Library/Application Support/Google/AndroidStudio2025.3.1/plugins/lsp4ij"
```

When `mustel.localIde` is set, the build uses the IDE's bundled JetBrains Runtime for compilation. Use the default build (without `mustel.localIde`) for a ZIP that can run on the full supported IDE range; the local override is intended for development and testing.

## Development

Run a sandboxed IDE with the plugin loaded:

```sh
./gradlew runIde
```

Run the bridge protocol tests:

```sh
./gradlew test
```

## How it works

The plugin starts a per-process Unix domain socket and publishes a descriptor under:

```text
~/Library/Application Support/Mustel/Bridge/intellij-<pid>.json
```

Mustel scans that directory, connects to the socket, and sends newline-delimited JSON requests:

- `{"type":"list"}` returns active Flutter runs.
- `{"type":"command","sessionId":"...","command":"hotReload"}` triggers a hot reload.
- `{"type":"command","sessionId":"...","command":"hotRestart"}` triggers a hot restart.

The plugin finds runs through `FlutterApp.allFromProjectProcess(project)` and uses `FlutterApp.performHotReload` / `performRestartApp`, matching the IDE's own reload behavior and document saving.

The bridge directory is restricted to the current user, and both the socket and descriptor are owner-only.

## License

This plugin is licensed under the [MIT License](../LICENSE).
