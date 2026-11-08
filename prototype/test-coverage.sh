#!/bin/zsh
# Full source inventory is checked even when the app entry point has no executed profile.
set -euo pipefail
cd "$(dirname "$0")"
OUT="$PWD/dist/coverage/full"
mkdir -p "$OUT"
WORK=$(mktemp -d)
APP_PID=""
cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    "$WORK/shutdown" "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT
export HOTKEYSTATS_LOG_DIR="$WORK/logs"
export HOTKEYSTATS_DATA_DIR="$WORK/data"
SOURCES=(Sources/HotkeyStats/*.swift)
LIBRARY=(${SOURCES:#Sources/HotkeyStats/main.swift})
FLAGS=(-swift-version 5 -module-name HotkeyStats -profile-generate -profile-coverage-mapping)
swiftc "${FLAGS[@]}" "${SOURCES[@]}" -framework AppKit -framework CoreGraphics -o "$WORK/app"
OBJECTS=()
for CASE in core analytics logger runtime desktop; do
  case "$CASE" in
    core) ENTRY=Tests/main.swift ;;
    analytics) ENTRY=Tests/Analytics/main.swift ;;
    logger) ENTRY=Tests/Logger/main.swift ;;
    runtime) ENTRY=Tests/Runtime/main.swift ;;
    desktop) ENTRY=Tests/Desktop/main.swift ;;
  esac
  EXTRA=()
  if [[ "$CASE" == desktop ]]; then EXTRA=(Tests/Desktop/TapChecks.swift Tests/Desktop/LifecycleChecks.swift Tests/Desktop/ReviewChecks.swift); fi
  swiftc "${FLAGS[@]}" "${LIBRARY[@]}" "$ENTRY" "${EXTRA[@]}" -framework AppKit -framework CoreGraphics -o "$WORK/$CASE"
  LLVM_PROFILE_FILE="$WORK/$CASE-%p.profraw" "$WORK/$CASE"
  if [[ "$CASE" == desktop ]]; then
    LLVM_PROFILE_FILE="$WORK/terminate-%p.profraw" "$WORK/$CASE" --terminate-action
  fi
  OBJECTS+=(-object "$WORK/$CASE")
done
# Launch the real entry point against an isolated store and bundle identity.
BUNDLE="$WORK/HotkeyStatsCoverage.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$WORK/app" "$BUNDLE/Contents/MacOS/HotkeyStats"
cp Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.HotkeyStats.Coverage' "$BUNDLE/Contents/Info.plist"
codesign --force --sign - "$BUNDLE"
swiftc Tests/Shutdown/main.swift -framework AppKit -o "$WORK/shutdown"
env HOTKEYSTATS_DATA_DIR="$WORK/smoke-data" LLVM_PROFILE_FILE="$WORK/application-%p.profraw" \
  "$BUNDLE/Contents/MacOS/HotkeyStats" &
APP_PID=$!
sleep 1
kill -0 "$APP_PID"
env HOTKEYSTATS_DATA_DIR="$WORK/smoke-data" LLVM_PROFILE_FILE="$WORK/duplicate-%p.profraw" \
  "$BUNDLE/Contents/MacOS/HotkeyStats"
sleep 5
"$WORK/shutdown" "$APP_PID"
wait "$APP_PID"
APP_PID=""
xcrun llvm-profdata merge -sparse "$WORK"/*.profraw -o "$WORK/all.profdata"
xcrun llvm-cov report "$WORK/app" "${OBJECTS[@]}" -instr-profile="$WORK/all.profdata" "${SOURCES[@]}" | tee "$OUT/report.txt"
xcrun llvm-cov export "$WORK/app" "${OBJECTS[@]}" -instr-profile="$WORK/all.profdata" "${SOURCES[@]}" > "$OUT/report.json"
python3 - "$OUT/report.json" "${SOURCES[@]}" <<'PY'
import json, pathlib, sys
files = {str(pathlib.Path(f['filename']).resolve()): f for block in json.load(open(sys.argv[1]))['data'] for f in block['files']}
failures = []
for source in sys.argv[2:]:
    file = files.get(str(pathlib.Path(source).resolve()))
    if file is None:
        failures.append(f'{source}: missing from report')
        continue
    for name in ('regions', 'functions', 'lines'):
        metric = file['summary'][name]
        if metric['count'] == 0 or metric['covered'] != metric['count']:
            failures.append(f"{source}: {name} {metric['covered']}/{metric['count']}")
if failures:
    sys.exit('Full-source 100% coverage gate failed:\n' + '\n'.join(failures))
print('PASS: every application Swift source has 100% regions, functions and lines')
PY
