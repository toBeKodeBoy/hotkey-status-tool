#!/bin/zsh
# HotkeyStats 原型构建脚本
set -euo pipefail
cd "$(dirname "$0")"

refuse_if_running() {
  echo "HotkeyStats 正在运行。请先从菜单退出，再重新构建。" >&2
  exit 1
}

# HOTKEYSTATS_PROCESS_CHECK 和 HOTKEYSTATS_OUT_DIR 只给回归检查注入。
if [[ -n "${HOTKEYSTATS_PROCESS_CHECK:-}" ]]; then
  if "$HOTKEYSTATS_PROCESS_CHECK"; then
    refuse_if_running
  fi
elif pgrep -x HotkeyStats >/dev/null 2>&1; then
  refuse_if_running
fi

if [[ ! -f Info.plist ]]; then
  echo "缺少 Info.plist，已保留上一份构建。" >&2
  exit 1
fi

SRC_DIR="$PWD/Sources/HotkeyStats"
OUT_DIR="${HOTKEYSTATS_OUT_DIR:-dist}"
APP_NAME="HotkeyStats.app"
STAGE="$OUT_DIR/.build-stage.$$"
DEST="$OUT_DIR/$APP_NAME"
BACKUP="$OUT_DIR/$APP_NAME.previous"

cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

mkdir -p "$STAGE/$APP_NAME/Contents/MacOS"

echo "==> 编译（Swift 5 语言模式，避免严格并发误报）"
swiftc -O -swift-version 5 \
  "$SRC_DIR"/*.swift \
  -framework AppKit -framework CoreGraphics \
  -o "$STAGE/$APP_NAME/Contents/MacOS/HotkeyStats"

cp Info.plist "$STAGE/$APP_NAME/Contents/Info.plist"
mkdir -p "$STAGE/$APP_NAME/Contents/Resources"
cp Resources/AppIcon.icns "$STAGE/$APP_NAME/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc 签名（监听全局键盘事件必需）"
codesign --force --sign - "$STAGE/$APP_NAME"

# 签名成功后再替换。替换失败时把上一份包移回原处。
rm -rf "$BACKUP"
if [[ -d "$DEST" ]]; then
  mv "$DEST" "$BACKUP"
fi
if ! mv "$STAGE/$APP_NAME" "$DEST"; then
  if [[ -d "$BACKUP" ]]; then
    mv "$BACKUP" "$DEST"
  fi
  echo "替换应用包失败，已保留上一份构建。" >&2
  exit 1
fi
rm -rf "$BACKUP"
rm -f "$OUT_DIR/HotkeyStats"

echo "==> 完成: $DEST"
echo "运行: open $DEST"
echo "首次运行需在 系统设置 → 隐私与安全性 → 辅助功能 和 输入监控 中勾选 HotkeyStats。"
