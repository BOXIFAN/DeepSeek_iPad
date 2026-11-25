#!/usr/bin/env bash
# 四个界面方向在 iPad / iPhone 上各截一张，供对比页使用。
# 用法: Scripts/explore-shots.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/.build/DerivedData/Build/Products/Debug-iphonesimulator/iPadDS.app"
OUT="$PWD/explore/shots"
mkdir -p "$OUT"

IPAD="9C061938-493B-4BB4-BF5D-56EA001E774D"
IPHONE="F07ADD5C-2F69-4851-A64E-0A8358CA3F0D"

for UDID in "$IPAD" "$IPHONE"; do
  xcrun simctl boot "$UDID" 2>/dev/null || true
done
for UDID in "$IPAD" "$IPHONE"; do
  xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" appearance light
  xcrun simctl status_bar "$UDID" override \
    --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"
done

shoot() {
  local udid="$1" variant="$2" name="$3"
  xcrun simctl terminate "$udid" com.ruakiu.ipadds >/dev/null 2>&1 || true
  env SIMCTL_CHILD_DS_UI_VARIANT="$variant" \
    xcrun simctl launch "$udid" com.ruakiu.ipadds >/dev/null
  sleep 3
  xcrun simctl io "$udid" screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "saved: explore/shots/$name.png"
}

for variant in paper floating desk cards; do
  shoot "$IPAD" "$variant" "ipad-$variant"
  shoot "$IPHONE" "$variant" "iphone-$variant"
done
