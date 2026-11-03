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
cp "$PROJECT_ROOT/Resources/Mustel.icns" "$BUILD_APP/Contents/Resources/Mustel.icns"
cp "$PROJECT_ROOT/Sources/Mustel/MustelMenuBar.png" "$BUILD_APP/Contents/Resources/MustelMenuBar.png"
cp -R "$BIN_DIRECTORY/Mustel_Mustel.bundle" "$BUILD_APP/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.ionutdanielfagadau.Mustel.resources" \
    "$BUILD_APP/Contents/Resources/Mustel_Mustel.bundle/Contents/Info.plist"
codesign --force --sign - --identifier com.ionutdanielfagadau.Mustel "$BUILD_APP"
ditto "$BUILD_APP" "$INSTALL_APP"
codesign --verify --deep --strict "$INSTALL_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_APP"
mdimport "$INSTALL_APP"

printf 'Installed %s\n' "$INSTALL_APP"
printf 'Open it with: open "%s"\n' "$INSTALL_APP"
