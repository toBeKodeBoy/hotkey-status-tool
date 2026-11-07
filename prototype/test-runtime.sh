#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export HOTKEYSTATS_LOG_DIR="$TEST_DIR/logs"
swiftc -swift-version 5 -profile-generate -profile-coverage-mapping \
  Sources/HotkeyStats/Runtime.swift Sources/HotkeyStats/Models.swift Sources/HotkeyStats/AppLogger.swift \
  Sources/HotkeyStats/RecordOrdering.swift Sources/HotkeyStats/LoginLaunch.swift \
  Tests/Runtime/main.swift -framework AppKit -framework ServiceManagement -o "$TEST_DIR/tests"
LLVM_PROFILE_FILE="$TEST_DIR/runtime-%p.profraw" "$TEST_DIR/tests"
xcrun llvm-profdata merge -sparse "$TEST_DIR"/*.profraw -o "$TEST_DIR/runtime.profdata"
xcrun llvm-cov report "$TEST_DIR/tests" -instr-profile="$TEST_DIR/runtime.profdata" \
  Sources/HotkeyStats/Runtime.swift Sources/HotkeyStats/RecordOrdering.swift Sources/HotkeyStats/LoginLaunch.swift

xcrun llvm-cov export "$TEST_DIR/tests" -instr-profile="$TEST_DIR/runtime.profdata" \
  Sources/HotkeyStats/Runtime.swift Sources/HotkeyStats/RecordOrdering.swift Sources/HotkeyStats/LoginLaunch.swift > "$TEST_DIR/coverage.json"
python3 - "$TEST_DIR/coverage.json" <<'PY_CHECK'
import json, sys
for item in json.load(open(sys.argv[1]))['data'][0]['files']:
    for metric in ('regions', 'functions', 'lines'):
        value = item['summary'][metric]
        if value['count'] == 0 or value['covered'] != value['count']:
            sys.exit(f"Coverage gate failed: {item['filename']} {metric}")
print('PASS: runtime, ordering and login policy coverage 100% (system adapter excluded)')
PY_CHECK
