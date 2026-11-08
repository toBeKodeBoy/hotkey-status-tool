#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export HOTKEYSTATS_LOG_DIR="$TEST_DIR/logs"
export HOTKEYSTATS_DATA_DIR="$TEST_DIR/data"
swiftc -swift-version 5 -profile-generate -profile-coverage-mapping \
  Sources/HotkeyStats/Models.swift Sources/HotkeyStats/AppLogger.swift \
  Sources/HotkeyStats/Runtime.swift Sources/HotkeyStats/ApplicationBootstrap.swift Sources/HotkeyStats/ApplicationLifecycle.swift Sources/HotkeyStats/EventTapMonitor.swift Sources/HotkeyStats/StatusBar.swift Sources/HotkeyStats/MainWindow.swift Sources/HotkeyStats/TrendView.swift Sources/HotkeyStats/RecordOrdering.swift Sources/HotkeyStats/LoginLaunch.swift Sources/HotkeyStats/LoginSystemAdapter.swift Sources/HotkeyStats/ApplicationContext.swift \
  Sources/HotkeyStats/StatsStore.swift Sources/HotkeyStats/Analytics.swift \
  Tests/Analytics/main.swift -framework CoreGraphics -framework AppKit -o "$TEST_DIR/tests"
LLVM_PROFILE_FILE="$TEST_DIR/analytics.profraw" "$TEST_DIR/tests"
xcrun llvm-profdata merge -sparse "$TEST_DIR/analytics.profraw" -o "$TEST_DIR/analytics.profdata"
xcrun llvm-cov report "$TEST_DIR/tests" -instr-profile="$TEST_DIR/analytics.profdata" \
  Sources/HotkeyStats/Analytics.swift Sources/HotkeyStats/StatsStore.swift

mkdir -p dist/coverage
xcrun llvm-cov export "$TEST_DIR/tests" -instr-profile="$TEST_DIR/analytics.profdata" > dist/coverage/analytics.json
xcrun llvm-cov show "$TEST_DIR/tests" -instr-profile="$TEST_DIR/analytics.profdata" \
  Sources/HotkeyStats/StatsStore.swift Sources/HotkeyStats/Analytics.swift > dist/coverage/analytics.txt
