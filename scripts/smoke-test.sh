#!/bin/bash
set -euo pipefail

# Verifies a packaged Mustel.app from a temporary directory, outside the build folder.
#
# It always runs `mustel --check-resources`, which resolves every runtime resource headlessly.
# Set MUSTEL_SMOKE_LAUNCH=1 to also launch the app and fail if it exits during startup; this
# catches crashes that only happen in the UI, but it needs a graphical session, so CI leaves it off.
#
# Usage: ./scripts/smoke-test.sh [path/to/Mustel.app]
# Environment: MUSTEL_SMOKE_SECONDS (default 5), MUSTEL_SMOKE_LAUNCH (default 0)

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$PROJECT_ROOT/.build/Mustel.app}"
DURATION="${MUSTEL_SMOKE_SECONDS:-5}"
LAUNCH="${MUSTEL_SMOKE_LAUNCH:-0}"
PLIST="$APP_PATH/Contents/Info.plist"

if [ ! -d "$APP_PATH" ]; then
    printf 'Smoke test failed: %s does not exist. Build the app first.\n' "$APP_PATH" >&2
    exit 1
fi

EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$PLIST")"
EXECUTABLE="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
if [ ! -x "$EXECUTABLE" ]; then
    printf 'Smoke test failed: %s is missing or not executable.\n' "$EXECUTABLE" >&2
    exit 1
fi

if ! find "$APP_PATH" -name "Mustel_Mustel.bundle" -type d -print -quit | grep -q .; then
    printf 'Smoke test failed: Mustel_Mustel.bundle is missing from %s.\n' "$APP_PATH" >&2
    exit 1
fi

WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/mustel-smoke.XXXXXX")"
cleanup() {
    if [ -n "${PID:-}" ]; then
        kill "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
    fi
    rm -rf "$WORK_DIRECTORY"
}
trap cleanup EXIT

# Copy the app out of .build so SwiftPM's build-directory fallback cannot be used by accident.
ditto "$APP_PATH" "$WORK_DIRECTORY/Mustel.app"
mkdir -p "$WORK_DIRECTORY/home"

if ! HOME="$WORK_DIRECTORY/home" "$WORK_DIRECTORY/Mustel.app/Contents/MacOS/$EXECUTABLE_NAME" \
    --check-resources; then
    printf 'Smoke test failed: %s cannot load its resources outside the build directory.\n' \
        "$APP_PATH" >&2
    exit 1
fi

if [ "$LAUNCH" != "1" ]; then
    printf 'Smoke test passed: %s resolves its resources outside its build directory.\n' "$APP_PATH"
    exit 0
fi

LOG="$WORK_DIRECTORY/run.log"
HOME="$WORK_DIRECTORY/home" "$WORK_DIRECTORY/Mustel.app/Contents/MacOS/$EXECUTABLE_NAME" >"$LOG" 2>&1 &
PID=$!

DEADLINE=$((SECONDS + DURATION))
while [ "$SECONDS" -lt "$DEADLINE" ]; do
    if ! kill -0 "$PID" 2>/dev/null; then
        wait "$PID" 2>/dev/null || true
        printf 'Smoke test failed: %s exited during startup.\n' "$APP_PATH" >&2
        printf -- '--- output ---\n' >&2
        tail -n 20 "$LOG" >&2 || true
        exit 1
    fi
    sleep 0.2
done

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
printf 'Smoke test passed: %s stayed alive for %ss outside its build directory.\n' \
    "$APP_PATH" "$DURATION"
