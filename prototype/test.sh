#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export HOTKEYSTATS_LOG_DIR="$TEST_DIR/logs"
export HOTKEYSTATS_DATA_DIR="$TEST_DIR/data"
swiftc -swift-version 5 Sources/HotkeyStats/Models.swift \
  Sources/HotkeyStats/Runtime.swift Sources/HotkeyStats/RecordOrdering.swift Sources/HotkeyStats/AppLogger.swift Sources/HotkeyStats/StatsStore.swift Sources/HotkeyStats/ApplicationBootstrap.swift Sources/HotkeyStats/ApplicationLifecycle.swift Sources/HotkeyStats/EventTapMonitor.swift Sources/HotkeyStats/StatusBar.swift Sources/HotkeyStats/LoginLaunch.swift Sources/HotkeyStats/LoginSystemAdapter.swift Sources/HotkeyStats/Analytics.swift Sources/HotkeyStats/ApplicationContext.swift Sources/HotkeyStats/TrendView.swift Sources/HotkeyStats/MainWindow.swift \
  Tests/main.swift -framework AppKit -framework CoreGraphics -o "$TEST_DIR/tests"
"$TEST_DIR/tests"

./test-logger.sh
./test_build.sh

./test-runtime.sh

./test-analytics.sh
