#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HOTKEYSTATS_LOG_DIR="$WORK/logs"
export HOTKEYSTATS_DATA_DIR="$WORK/data"
mkdir -p dist/coverage
SOURCES=(Sources/HotkeyStats/*.swift)
SOURCES=(${SOURCES:#Sources/HotkeyStats/main.swift})
swiftc -swift-version 5 "${SOURCES[@]}" Tests/Desktop/main.swift Tests/Desktop/TapChecks.swift Tests/Desktop/LifecycleChecks.swift \
  -framework AppKit -framework CoreGraphics -o "$WORK/desktop"
"$WORK/desktop"
