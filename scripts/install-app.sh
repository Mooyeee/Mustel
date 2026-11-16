#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mustel.app"
BUILD_APP="$PROJECT_ROOT/.build/$APP_NAME"
INSTALL_DIRECTORY="${HOME}/Applications"
INSTALL_APP="$INSTALL_DIRECTORY/$APP_NAME"

cd "$PROJECT_ROOT"
if [ "${MUSTEL_SKIP_ICONS:-0}" = "1" ]; then
    printf 'Skipping icon generation (MUSTEL_SKIP_ICONS=1)\n'
else
    ./scripts/generate-icons.sh
fi
# Xcode 27 links the binary with "sdk 14.0" unless told otherwise. macOS 26+ then
# draws controls (toggles, menus) in the legacy, non-Liquid-Glass style. Always
# record the real SDK version in the binary.
SDK_VERSION="$(xcrun --show-sdk-version)"
SWIFT_BUILD_FLAGS=(
    --configuration release --product mustel
    -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION"
)
swift build "${SWIFT_BUILD_FLAGS[@]}"
BIN_DIRECTORY="$(swift build "${SWIFT_BUILD_FLAGS[@]}" --show-bin-path)"
LINKED_SDK="$(vtool -show-build "$BIN_DIRECTORY/mustel" | awk '$1 == "sdk" { print $2 }')"
if [ "${LINKED_SDK%%.*}" -lt 26 ]; then
    echo "mustel is linked against SDK $LINKED_SDK: Liquid Glass controls would be disabled on macOS 26+." >&2
    exit 1
fi
RESOURCE_BUNDLE="$BIN_DIRECTORY/Mustel_Mustel.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
    printf 'The build did not produce %s. Cannot package the app.\n' "$RESOURCE_BUNDLE" >&2
    exit 1
fi
rm -rf "$BUILD_APP"
mkdir -p "$BUILD_APP/Contents/MacOS" "$BUILD_APP/Contents/Resources" "$INSTALL_DIRECTORY"
cp "$BIN_DIRECTORY/mustel" "$BUILD_APP/Contents/MacOS/mustel"
cp "$PROJECT_ROOT/Resources/Info.plist" "$BUILD_APP/Contents/Info.plist"
cp "$PROJECT_ROOT/Resources/Mustel-0.1.7.icns" "$BUILD_APP/Contents/Resources/Mustel-0.1.7.icns"
cp "$PROJECT_ROOT/Sources/Mustel/MustelMenuBar.png" "$BUILD_APP/Contents/Resources/MustelMenuBar.png"
ditto "$RESOURCE_BUNDLE" "$BUILD_APP/Contents/Resources/Mustel_Mustel.bundle"
codesign --force --sign - --identifier com.mooyee.Mustel "$BUILD_APP"

if [ "${MUSTEL_SKIP_INSTALL:-0}" = "1" ]; then
    codesign --verify --deep --strict "$BUILD_APP"
    printf 'Built %s (not installed)\n' "$BUILD_APP"
    exit 0
fi

ditto "$BUILD_APP" "$INSTALL_APP"
codesign --verify --deep --strict "$INSTALL_APP"
touch "$INSTALL_APP" "$INSTALL_APP/Contents/Info.plist"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_APP"
mdimport -i "$INSTALL_APP"

if FLUTTER_EXECUTABLE="$(command -v flutter)"; then
    if ! defaults read com.mooyee.Mustel flutterExecutable >/dev/null 2>&1; then
        defaults write com.mooyee.Mustel flutterExecutable -string "$FLUTTER_EXECUTABLE"
    fi
fi

printf 'Installed %s\n' "$INSTALL_APP"
printf 'Open it with: open "%s"\n' "$INSTALL_APP"
