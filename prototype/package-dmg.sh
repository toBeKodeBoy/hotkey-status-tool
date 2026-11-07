#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/HotkeyStats.app"
if [[ ! -d "$APP" ]]; then
  echo "缺少应用包，请先执行 ./build.sh。" >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(lipo -archs "$APP/Contents/MacOS/HotkeyStats" | tr ' ' '-')
if [[ "$VERSION" != [0-9]* || "$VERSION" == *[^0-9.]* ]]; then
  echo "应用版本号格式无效。" >&2
  exit 1
fi
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/payload"
ditto "$APP" "$STAGE/payload/HotkeyStats.app"
ln -s /Applications "$STAGE/payload/Applications"
DEST="dist/HotkeyStats-$VERSION-$ARCH.dmg"
hdiutil create -volname "HotkeyStats $VERSION" -srcfolder "$STAGE/payload" \
  -format UDZO -ov "$STAGE/HotkeyStats.dmg"
hdiutil verify "$STAGE/HotkeyStats.dmg"
mv -f "$STAGE/HotkeyStats.dmg" "$DEST"
echo "完成：$DEST"
