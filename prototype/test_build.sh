#!/bin/zsh
# 构建脚本的全部分支。临时目录里编译，不替换 prototype/dist。
set -euo pipefail
cd "$(dirname "$0")"

TMP=$(mktemp -d)
SLEEP_PID=""
cleanup() {
  if [[ -n "$SLEEP_PID" ]]; then
    kill "$SLEEP_PID" 2>/dev/null || true
    wait "$SLEEP_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  if [[ -f "$TMP/build.err" ]]; then
    echo "--- stderr ---" >&2
    cat "$TMP/build.err" >&2
  fi
  exit 1
}

run_build() {
  set +e
  env "$@" ./build.sh >"$TMP/build.out" 2>"$TMP/build.err"
  STATUS=$?
  set -e
}

assert_preserved() {
  local marker="$1"
  [[ "$STATUS" -ne 0 ]] || fail "$2 should fail"
  [[ "$(cat "$marker")" == "keep" ]] || fail "$2 replaced the previous app"
  [[ ! -d "${marker%/*}.previous" ]] || fail "$2 left a backup behind"
}

# 注入的进程检查为真时，在编译前停止。
mkdir -p "$TMP/out-env"
run_build HOTKEYSTATS_PROCESS_CHECK=/usr/bin/true HOTKEYSTATS_OUT_DIR="$TMP/out-env"
[[ "$STATUS" -ne 0 ]] || fail "injected running check should stop the build"
grep -q "正在运行" "$TMP/build.err" || fail "missing running message for injected check"
[[ ! -e "$TMP/out-env/HotkeyStats.app" ]] || fail "injected running check created an app"

# 进程名正好是 HotkeyStats 时，走真实的 pgrep 分支。
cat > "$TMP/sleeper.c" <<'EOF'
#include <unistd.h>
int main(void) { pause(); return 0; }
EOF
clang -o "$TMP/HotkeyStats" "$TMP/sleeper.c"
"$TMP/HotkeyStats" &
SLEEP_PID=$!
sleep 0.2
pgrep -x HotkeyStats >/dev/null || fail "sleeper process name was not HotkeyStats"
mkdir -p "$TMP/out-pgrep"
run_build HOTKEYSTATS_OUT_DIR="$TMP/out-pgrep"
[[ "$STATUS" -ne 0 ]] || fail "live HotkeyStats process should stop the build"
grep -q "正在运行" "$TMP/build.err" || fail "missing running message for live process"
[[ ! -e "$TMP/out-pgrep/HotkeyStats.app" ]] || fail "live process check created an app"
kill "$SLEEP_PID" 2>/dev/null || true
wait "$SLEEP_PID" 2>/dev/null || true
SLEEP_PID=""

# 缺少 Info.plist 时不编译，已有应用包保持原样。
MISS="$TMP/missing-plist"
mkdir -p "$MISS"
cp ./build.sh "$MISS/build.sh"
mkdir -p "$MISS/out/HotkeyStats.app"
echo keep > "$MISS/out/HotkeyStats.app/marker"
(
  cd "$MISS"
  set +e
  env HOTKEYSTATS_PROCESS_CHECK=/usr/bin/false HOTKEYSTATS_OUT_DIR="$MISS/out" \
    ./build.sh >"$TMP/build.out" 2>"$TMP/build.err"
  STATUS=$?
  set -e
  assert_preserved "$MISS/out/HotkeyStats.app/marker" "missing plist"
)
grep -q "缺少 Info.plist" "$TMP/build.err" || fail "missing plist message"

# 替换失败时把上一份应用包移回原处。
MV="$TMP/bin"
mkdir -p "$MV"
cat > "$MV/mv" <<'EOF'
#!/bin/zsh
if [[ "${1:-}" == *".build-stage."*/HotkeyStats.app && "${2:-}" == "$FAIL_MV_DEST" ]]; then
  exit 1
fi
exec /bin/mv "$@"
EOF
chmod +x "$MV/mv"
mkdir -p "$TMP/out-mv/HotkeyStats.app"
echo keep > "$TMP/out-mv/HotkeyStats.app/marker"
run_build PATH="$MV:$PATH" FAIL_MV_DEST="$TMP/out-mv/HotkeyStats.app" \
  HOTKEYSTATS_PROCESS_CHECK=/usr/bin/false HOTKEYSTATS_OUT_DIR="$TMP/out-mv"
assert_preserved "$TMP/out-mv/HotkeyStats.app/marker" "failed replace"
grep -q "替换应用包失败" "$TMP/build.err" || fail "missing replace failure message"
[[ -z "$(find "$TMP/out-mv" -name '.build-stage.*' -print)" ]] || fail "stage directory left behind"

# 首次构建、再次替换，以及删掉旧的裸二进制。
run_build HOTKEYSTATS_PROCESS_CHECK=/usr/bin/false HOTKEYSTATS_OUT_DIR="$TMP/out-ok"
[[ "$STATUS" -eq 0 ]] || fail "first build should succeed"
APP="$TMP/out-ok/HotkeyStats.app"
[[ "$(plutil -extract LSUIElement raw "$APP/Contents/Info.plist")" == "true" ]] || fail "LSUIElement"
codesign -dv "$APP" 2>"$TMP/sign.txt"
grep -q "Identifier=local.HotkeyStats" "$TMP/sign.txt" || fail "bundle identifier"
grep -q "Signature=adhoc" "$TMP/sign.txt" || fail "ad-hoc signature"
echo stale > "$TMP/out-ok/HotkeyStats"
run_build HOTKEYSTATS_PROCESS_CHECK=/usr/bin/false HOTKEYSTATS_OUT_DIR="$TMP/out-ok"
[[ "$STATUS" -eq 0 ]] || fail "replacement build should succeed"
[[ ! -e "$TMP/out-ok/HotkeyStats" ]] || fail "bare binary was not removed"
[[ ! -d "$APP.previous" ]] || fail "backup left after success"
[[ -z "$(find "$TMP/out-ok" -name '.build-stage.*' -print)" ]] || fail "stage left after success"
codesign -dv "$APP" >/dev/null 2>&1

echo "PASS: build script branches"
