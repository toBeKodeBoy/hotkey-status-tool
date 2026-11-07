#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export HOTKEYSTATS_LOG_DIR="$TEST_DIR/logs"
swiftc -swift-version 5 Sources/HotkeyStats/Models.swift \
  Sources/HotkeyStats/Runtime.swift Sources/HotkeyStats/RecordOrdering.swift Sources/HotkeyStats/AppLogger.swift Sources/HotkeyStats/StatsStore.swift Sources/HotkeyStats/MainWindow.swift \
  Tests/main.swift -framework AppKit -framework CoreGraphics -o "$TEST_DIR/tests"
"$TEST_DIR/tests"

./test-logger.sh
./test_build.sh

./test-runtime.sh
