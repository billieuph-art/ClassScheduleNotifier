#!/bin/bash
# 侧载 IPA 发布前校验。任一检查失败则退出非 0，阻止发版。
set -euo pipefail

IPA="${1:?usage: validate-sideload-ipa.sh <ipa>}"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> Validating $IPA"
test -f "$IPA"
SIZE=$(stat -f%z "$IPA" 2>/dev/null || stat -c%s "$IPA")
# 空包或异常偏小
if [ "$SIZE" -lt 200000 ]; then
  echo "ERROR: IPA too small ($SIZE bytes)"
  exit 1
fi

unzip -q "$IPA" -d "$WORKDIR"
APP="$WORKDIR/Payload/GlassSchedule.app"
test -d "$APP"
test -f "$APP/GlassSchedule"
test -f "$APP/Info.plist"

# 根目录只能是 Payload
ROOT_ENTRIES=$(find "$WORKDIR" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null || ls -1 "$WORKDIR")
echo "$ROOT_ENTRIES" | grep -qx Payload
EXTRA=$(echo "$ROOT_ENTRIES" | grep -v '^Payload$' || true)
if [ -n "$EXTRA" ]; then
  echo "ERROR: unexpected IPA root entries: $EXTRA"
  exit 1
fi

# 禁止 Watch / 付费残留
if [ -d "$APP/Watch" ]; then
  echo "ERROR: Watch app still embedded"
  exit 1
fi
if find "$APP" -name '*.entitlements' | grep -q .; then
  echo "ERROR: entitlements files still present"
  exit 1
fi

# 可执行权限
test -x "$APP/GlassSchedule"

# Info.plist 关键字段
plutil -extract CFBundleIdentifier raw -o - "$APP/Info.plist" | grep -qx 'com.billieuphart.glassschedule'
plutil -extract CFBundleDisplayName raw -o - "$APP/Info.plist" | grep -qx 'Classio'
MINOS=$(plutil -extract MinimumOSVersion raw -o - "$APP/Info.plist")
echo "MinimumOSVersion=$MINOS"
VER=$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Info.plist")
BUILD=$(plutil -extract CFBundleVersion raw -o - "$APP/Info.plist")
echo "Version=$VER ($BUILD)"

# 主二进制 arm64 + iOS
FILE_OUT=$(file "$APP/GlassSchedule")
echo "$FILE_OUT" | grep -qi 'arm64'
# 拒绝模拟器切片
if echo "$FILE_OUT" | grep -qi 'x86_64'; then
  echo "ERROR: simulator slice present"
  exit 1
fi

# Widget 扩展（实时活动必需）
APPEX="$APP/PlugIns/GlassScheduleWidgets.appex"
test -d "$APPEX"
test -x "$APPEX/GlassScheduleWidgets"
WID=$(plutil -extract CFBundleIdentifier raw -o - "$APPEX/Info.plist")
echo "Widget ID=$WID"
echo "$WID" | grep -qx 'com.billieuphart.glassschedule.widgets'
WVER=$(plutil -extract CFBundleShortVersionString raw -o - "$APPEX/Info.plist")
WBUILD=$(plutil -extract CFBundleVersion raw -o - "$APPEX/Info.plist")
if [ "$WVER" != "$VER" ] || [ "$WBUILD" != "$BUILD" ]; then
  echo "ERROR: widget version mismatch app=$VER/$BUILD widget=$WVER/$WBUILD"
  exit 1
fi

# 侧载友好：不应再带 iPad 专用图标键（iPhone-only）
if plutil -extract 'CFBundleIcons~ipad' raw -o - "$APP/Info.plist" >/dev/null 2>&1; then
  echo "ERROR: CFBundleIcons~ipad still present (iPhone-only target)"
  exit 1
fi
if ls "$APP"/AppIcon*ipad* >/dev/null 2>&1; then
  echo "ERROR: iPad AppIcon files still present"
  exit 1
fi

# 不应残留 ad-hoc / 未完成签名目录（由打包脚本剥离，留给 Sideloadly 重签）
if [ -d "$APP/_CodeSignature" ]; then
  echo "ERROR: _CodeSignature present — package must be unsigned for clean resign"
  exit 1
fi
if [ -d "$APPEX/_CodeSignature" ]; then
  echo "ERROR: appex _CodeSignature present"
  exit 1
fi

# Assets / 图标
test -f "$APP/Assets.car"
test -f "$APP/AppIcon60x60@2x.png"

echo "==> IPA validation passed"
ls -lh "$IPA"
