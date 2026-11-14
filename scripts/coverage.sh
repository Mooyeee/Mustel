#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

printf 'Running Swift tests with coverage…\n'
swift test --enable-code-coverage

TEST_BUNDLE="$(find .build -name '*Tests.xctest' -type d -print -quit)"
TEST_BINARY="$(find "$TEST_BUNDLE" -type f -perm -111 -print -quit)"
PROFILE="$(find .build -name default.profdata -print -quit)"
if [ -z "$TEST_BINARY" ] || [ -z "$PROFILE" ]; then
    printf 'Could not find Swift coverage data.\n' >&2
    exit 1
fi

xcrun llvm-cov report "$TEST_BINARY" -instr-profile="$PROFILE"
xcrun llvm-cov export "$TEST_BINARY" \
    -instr-profile="$PROFILE" \
    -format=lcov > "$PROJECT_ROOT/swift-coverage.lcov"
printf 'Swift coverage written to %s\n' "$PROJECT_ROOT/swift-coverage.lcov"

if [ -s "$HOME/.nvm/nvm.sh" ]; then
    # shellcheck disable=SC1090
    . "$HOME/.nvm/nvm.sh"
    nvm use 22 >/dev/null 2>&1 || nvm use --lts >/dev/null 2>&1 || true
fi

printf '\nRunning VS Code bridge tests with coverage…\n'
cd "$PROJECT_ROOT/vscode-extension"
npm test
printf 'VS Code coverage written to %s\n' "$PROJECT_ROOT/vscode-extension/coverage/lcov.info"
