#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 5 -profile-generate -profile-coverage-mapping \
  Sources/HotkeyStats/AppLogger.swift Tests/Logger/main.swift -o "$TEST_DIR/tests"
LLVM_PROFILE_FILE="$TEST_DIR/logger.profraw" "$TEST_DIR/tests"
xcrun llvm-profdata merge -sparse "$TEST_DIR/logger.profraw" -o "$TEST_DIR/logger.profdata"
xcrun llvm-cov report "$TEST_DIR/tests" -instr-profile="$TEST_DIR/logger.profdata" \
  Sources/HotkeyStats/AppLogger.swift
xcrun llvm-cov export "$TEST_DIR/tests" -instr-profile="$TEST_DIR/logger.profdata" \
  Sources/HotkeyStats/AppLogger.swift > "$TEST_DIR/cov.json"
python3 - "$TEST_DIR/cov.json" <<'PY'
import json, sys
totals = json.load(open(sys.argv[1]))["data"][0]["totals"]
for key in ("regions", "functions", "lines"):
    part = totals[key]
    if part["count"] == 0 or part["covered"] != part["count"]:
        sys.exit(f"AppLogger {key} {part['covered']}/{part['count']}")
print("PASS: AppLogger coverage 100%")
PY
