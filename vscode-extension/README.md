# Mustel Bridge for VS Code

The Mustel Bridge exposes active Dart/Flutter debug sessions to the [Mustel macOS menu-bar app](../README.md). It forwards hot reload and hot restart requests through Dart Code, so Mustel does not start a second `flutter attach` for sessions managed by VS Code.

## Requirements

- VS Code 1.85 or later
- The [Dart extension](https://marketplace.visualstudio.com/items?itemName=Dart-Code.dart-code), installed and enabled
- Mustel running on the same Mac and user account

## Build and install

From this directory:

```sh
npm install
npm run compile
npx @vscode/vsce package
```

Use a current Node.js release for VSIX packaging. Install the generated `mustel-vscode-0.1.1.vsix` with **Extensions: Install from VSIX...**, then reload the VS Code window if it was already open.

## Development

Open this directory in VS Code and press **F5** to launch an Extension Development Host. Start a Dart/Flutter debug session in that host while Mustel is running.

## Local communication

The extension publishes a descriptor and a per-process Unix domain socket under the current user's Mustel application-support directory. The directory is restricted to that user, and the socket is owner-only. The bridge handles active Dart debug sessions in its own extension host and supports only hot reload and hot restart.

This extension is licensed under the [MIT License](./LICENSE).
