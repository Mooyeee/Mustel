#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$PROJECT_ROOT/.build/Mustel.app"
OUTPUT_DIRECTORY="$PROJECT_ROOT/.build/releases"
PUBLISH=false
NO_INSTALL=false

for argument in "$@"; do
    case "$argument" in
        --publish)
            PUBLISH=true
            ;;
        --no-install)
            NO_INSTALL=true
            ;;
        *)
            printf 'Unknown option: %s\n' "$argument" >&2
            exit 1
            ;;
    esac
done

cd "$PROJECT_ROOT"
if [ "$NO_INSTALL" = true ]; then
    MUSTEL_SKIP_INSTALL=1 ./scripts/install-app.sh
else
    ./scripts/install-app.sh
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
VSCODE_VERSION="$(python3 -c 'import json; print(json.load(open("vscode-extension/package.json"))["version"])')"
INTELLIJ_VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' intellij-plugin/build.gradle.kts | head -1)"

if [ -z "$INTELLIJ_VERSION" ]; then
    echo "Could not read the IntelliJ plugin version from intellij-plugin/build.gradle.kts." >&2
    exit 1
fi

if [ -s "$HOME/.nvm/nvm.sh" ]; then
    # shellcheck disable=SC1090
    . "$HOME/.nvm/nvm.sh"
    nvm use 22 >/dev/null 2>&1 || nvm use --lts >/dev/null 2>&1 || true
fi
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "$NODE_MAJOR" -lt 18 ]; then
    echo "Node.js 18 or later is required to package the VS Code extension." >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIRECTORY"
rm -f \
    "$OUTPUT_DIRECTORY/Mustel.zip" \
    "$OUTPUT_DIRECTORY"/mustel-vscode-*.vsix \
    "$OUTPUT_DIRECTORY"/mustel-intellij-*.zip

ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT_DIRECTORY/Mustel.zip"

(
    cd vscode-extension
    npm install --no-package-lock
    npx @vscode/vsce package --out "$OUTPUT_DIRECTORY/mustel-vscode-$VSCODE_VERSION.vsix"
)

(
    cd intellij-plugin
    ./gradlew buildPlugin
)
INTELLIJ_ZIP="$(find "$PROJECT_ROOT/intellij-plugin/build/distributions" -maxdepth 1 -name "mustel-intellij-$INTELLIJ_VERSION.zip" -print -quit)"
if [ -z "$INTELLIJ_ZIP" ]; then
    echo "Could not find the IntelliJ plugin archive." >&2
    exit 1
fi
cp "$INTELLIJ_ZIP" "$OUTPUT_DIRECTORY/mustel-intellij-$INTELLIJ_VERSION.zip"

printf '\nRelease assets for v%s:\n' "$VERSION"
printf '  %s\n' "$OUTPUT_DIRECTORY/Mustel.zip"
printf '  %s\n' "$OUTPUT_DIRECTORY/mustel-vscode-$VSCODE_VERSION.vsix"
printf '  %s\n' "$OUTPUT_DIRECTORY/mustel-intellij-$INTELLIJ_VERSION.zip"
shasum -a 256 "$OUTPUT_DIRECTORY"/*

if [ "$PUBLISH" = true ]; then
    if ! command -v gh >/dev/null 2>&1; then
        echo "The GitHub CLI (gh) is required to publish a release." >&2
        exit 1
    fi
    TAG="v$VERSION"
    ASSETS=(
        "$OUTPUT_DIRECTORY/Mustel.zip"
        "$OUTPUT_DIRECTORY/mustel-vscode-$VSCODE_VERSION.vsix"
        "$OUTPUT_DIRECTORY/mustel-intellij-$INTELLIJ_VERSION.zip"
    )
    if gh release view "$TAG" >/dev/null 2>&1; then
        gh release upload "$TAG" "${ASSETS[@]}" --clobber
    else
        gh release create "$TAG" "${ASSETS[@]}" \
            --title "Mustel $VERSION" \
            --generate-notes
    fi
    printf 'Published GitHub release %s.\n' "$TAG"
else
    printf '\nUpload those three files to a GitHub release tagged v%s, or rerun with --publish.\n' "$VERSION"
fi
