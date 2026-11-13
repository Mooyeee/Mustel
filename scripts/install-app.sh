#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mustel.app"
BUILD_APP="$PROJECT_ROOT/.build/$APP_NAME"
INSTALL_DIRECTORY="${HOME}/Applications"
INSTALL_APP="$INSTALL_DIRECTORY/$APP_NAME"

cd "$PROJECT_ROOT"
./scripts/generate-icons.sh
swift build --configuration release --product mustel
BIN_DIRECTORY="$(swift build --configuration release --product mustel --show-bin-path)"
mkdir -p "$BUILD_APP/Contents/MacOS" "$BUILD_APP/Contents/Resources" "$INSTALL_DIRECTORY"
cp "$BIN_DIRECTORY/mustel" "$BUILD_APP/Contents/MacOS/mustel"
cp "$PROJECT_ROOT/Resources/Info.plist" "$BUILD_APP/Contents/Info.plist"
cp "$PROJECT_ROOT/Resources/Mustel-0.1.6.icns" "$BUILD_APP/Contents/Resources/Mustel-0.1.6.icns"
cp "$PROJECT_ROOT/Sources/Mustel/MustelMenuBar.png" "$BUILD_APP/Contents/Resources/MustelMenuBar.png"
cp -R "$BIN_DIRECTORY/Mustel_Mustel.bundle" "$BUILD_APP/Contents/Resources/"
codesign --force --sign - --identifier com.mooyee.Mustel "$BUILD_APP"
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
