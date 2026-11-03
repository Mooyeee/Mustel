#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$PROJECT_ROOT/.build/Mustel.iconset"
MENU_ICON="$PROJECT_ROOT/Sources/Mustel/MustelMenuBar.png"
APP_ICON="$PROJECT_ROOT/Resources/Mustel.icns"
VSCODE_ICON="$PROJECT_ROOT/vscode-extension/images/icon.png"
FERRET_SVG="$PROJECT_ROOT/Resources/ferret.svg"
PADDED_APP_SVG="$PROJECT_ROOT/.build/mustel-app-icon.svg"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    printf 'Missing rsvg-convert. Install it with: brew install librsvg\n' >&2
    exit 1
fi

mkdir -p "$ICONSET" "$(dirname "$VSCODE_ICON")"
rsvg-convert -w 72 -h 72 "$FERRET_SVG" -o "$MENU_ICON"
MENU_ICON_CROPPED="${MENU_ICON%.png}.cropped.png"
sips --cropToHeightWidth 40 72 --cropOffset 16 0 "$MENU_ICON" --out "$MENU_ICON_CROPPED" >/dev/null
mv "$MENU_ICON_CROPPED" "$MENU_ICON"
python3 - "$FERRET_SVG" "$PADDED_APP_SVG" <<'PY'
import pathlib
import re
import sys

source_path = pathlib.Path(sys.argv[1])
output_path = pathlib.Path(sys.argv[2])
source = source_path.read_text()
match = re.search(r"<svg\b[^>]*>(.*)</svg>\s*$", source, re.DOTALL)
if not match:
    raise SystemExit(f"Could not parse SVG artwork: {source_path}")

artwork = match.group(1).replace("#070807", "#fff8ed")
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="background" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#6374c8"/>
      <stop offset="1" stop-color="#354078"/>
    </linearGradient>
    <radialGradient id="glow">
      <stop offset="0" stop-color="#a8b8ff" stop-opacity=".42"/>
      <stop offset="1" stop-color="#a8b8ff" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1024" height="1024" rx="228" fill="url(#background)"/>
  <ellipse cx="512" cy="480" rx="390" ry="370" fill="url(#glow)"/>
  <svg x="152" y="128" width="768" height="768" viewBox="342 0 1000 1000" preserveAspectRatio="xMidYMid meet">
    {artwork}
  </svg>
</svg>'''
output_path.write_text(svg)
PY
rsvg-convert -w 256 -h 256 "$PADDED_APP_SVG" -o "$VSCODE_ICON"
rsvg-convert -w 1024 -h 1024 "$PADDED_APP_SVG" -o "$ICONSET/icon_512x512@2x.png"

for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" "$PADDED_APP_SVG" -o "$ICONSET/icon_${size}x${size}.png"
done

for size in 32 64 256 512 1024; do
    rsvg-convert -w "$size" -h "$size" "$PADDED_APP_SVG" -o "$ICONSET/icon_$((size / 2))x$((size / 2))@2x.png"
done

iconutil --convert icns --output "$APP_ICON" "$ICONSET"
printf 'Generated menu bar icon: %s\n' "$MENU_ICON"
printf 'Generated app icon: %s\n' "$APP_ICON"
printf 'Generated VS Code extension icon: %s\n' "$VSCODE_ICON"
