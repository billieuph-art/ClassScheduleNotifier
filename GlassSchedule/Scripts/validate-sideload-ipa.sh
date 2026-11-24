#!/bin/bash
# 侧载 IPA 发布前校验。任一检查失败则退出非 0，阻止发版。
# 用法: validate-sideload-ipa.sh <ipa> [--lite]
set -euo pipefail

IPA="${1:?usage: validate-sideload-ipa.sh <ipa> [--lite]}"
LITE=no
if [ "${2:-}" = "--lite" ]; then
  LITE=yes
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> Validating $IPA (lite=$LITE)"
test -f "$IPA"
SIZE=$(stat -f%z "$IPA" 2>/dev/null || stat -c%s "$IPA")
if [ "$SIZE" -lt 150000 ]; then
  echo "ERROR: IPA too small ($SIZE bytes)"
  exit 1
fi

unzip -q "$IPA" -d "$WORKDIR"
APP="$WORKDIR/Payload/GlassSchedule.app"
test -d "$APP"
test -f "$APP/GlassSchedule"
test -f "$APP/Info.plist"

ROOT_ENTRIES=$(ls -1 "$WORKDIR")
echo "$ROOT_ENTRIES" | grep -qx Payload
EXTRA=$(echo "$ROOT_ENTRIES" | grep -v '^Payload$' || true)
if [ -n "$EXTRA" ]; then
  echo "ERROR: unexpected IPA root entries: $EXTRA"
  exit 1
fi

if [ -d "$APP/Watch" ]; then
  echo "ERROR: Watch app still embedded"
  exit 1
fi
if find "$APP" -name '*.entitlements' | grep -q .; then
  echo "ERROR: entitlements files still present"
  exit 1
fi

test -x "$APP/GlassSchedule"

plutil -extract CFBundleIdentifier raw -o - "$APP/Info.plist" | grep -qx 'com.billieuphart.glassschedule'
plutil -extract CFBundleDisplayName raw -o - "$APP/Info.plist" | grep -qx 'Classio'
MINOS=$(plutil -extract MinimumOSVersion raw -o - "$APP/Info.plist")
echo "MinimumOSVersion=$MINOS"
VER=$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Info.plist")
BUILD=$(plutil -extract CFBundleVersion raw -o - "$APP/Info.plist")
echo "Version=$VER ($BUILD)"

# 不应再声明 processing（免费侧载安装失败高发）
if plutil -p "$APP/Info.plist" | grep -q 'processing'; then
  echo "ERROR: UIBackgroundModes still contains processing"
  exit 1
fi

FILE_OUT=$(file "$APP/GlassSchedule")
echo "$FILE_OUT" | grep -qi 'arm64'
if echo "$FILE_OUT" | grep -qi 'x86_64'; then
  echo "ERROR: simulator slice present"
  exit 1
fi

# 与可安装的 1.0.7 一致：需要 ad-hoc 签名目录
if [ ! -d "$APP/_CodeSignature" ]; then
  echo "ERROR: missing _CodeSignature (expected ad-hoc sign like v1.0.7)"
  exit 1
fi

if [ "$LITE" = "yes" ]; then
  if [ -d "$APP/PlugIns" ]; then
    echo "ERROR: lite IPA must not contain PlugIns"
    exit 1
  fi
else
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
  if [ ! -d "$APPEX/_CodeSignature" ]; then
    echo "ERROR: appex missing _CodeSignature"
    exit 1
  fi
fi

if plutil -extract 'CFBundleIcons~ipad' raw -o - "$APP/Info.plist" >/dev/null 2>&1; then
  echo "ERROR: CFBundleIcons~ipad still present"
  exit 1
fi
if ls "$APP"/AppIcon*ipad* >/dev/null 2>&1; then
  echo "ERROR: iPad AppIcon files still present"
  exit 1
fi

test -f "$APP/Assets.car"
test -f "$APP/AppIcon60x60@2x.png"

# 可安装的 v1.0.11：单外观 Assets.car≈377KB、AppIcon60x60≈17KB。
# 多外观未压缩曾到 ~898KB 导致拒装；过度压缩又会让图标过小/损坏。
CAR_SIZE=$(stat -f%z "$APP/Assets.car" 2>/dev/null || stat -c%s "$APP/Assets.car")
ICON_SIZE=$(stat -f%z "$APP/AppIcon60x60@2x.png" 2>/dev/null || stat -c%s "$APP/AppIcon60x60@2x.png")
echo "Assets.car=$CAR_SIZE AppIcon60x60@2x=$ICON_SIZE"
if [ "$CAR_SIZE" -lt 200000 ] || [ "$CAR_SIZE" -gt 600000 ]; then
  echo "ERROR: Assets.car out of installable range ($CAR_SIZE); use single full-quality AppIcon like v1.0.11"
  exit 1
fi
if [ "$ICON_SIZE" -lt 12000 ]; then
  echo "ERROR: AppIcon60x60@2x.png too small ($ICON_SIZE); catalog likely corrupt"
  exit 1
fi

# 对齐可安装的 v1.0.11：lite 无 PlugIns，但仍声明 Live Activities
if [ "$LITE" = "yes" ]; then
  plutil -extract NSSupportsLiveActivities raw -o - "$APP/Info.plist" | grep -qx 'true' \
    || { echo "ERROR: lite should keep NSSupportsLiveActivities like v1.0.11"; exit 1; }
fi

echo "==> IPA validation passed"
ls -lh "$IPA"
