#!/usr/bin/env bash
# 浮岛新骨架的验收截图：空态 / 对话态 / 历史浮层 / 深色，iPad 与 iPhone 各一套。
# 用法: Scripts/preview-shots.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/.build/DerivedData/Build/Products/Debug-iphonesimulator/iPadDS.app"
OUT="$PWD/shots/redesign"
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
  local udid="$1" name="$2"
  shift 2
  xcrun simctl terminate "$udid" com.ruakiu.ipadds >/dev/null 2>&1 || true
  env SIMCTL_CHILD_DS_BALANCE_DEMO=1 "$@" \
    xcrun simctl launch "$udid" com.ruakiu.ipadds >/dev/null
  sleep 3
  xcrun simctl io "$udid" screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "saved: shots/redesign/$name.png"
}

for UDID in "$IPAD" "$IPHONE"; do
  PREFIX="ipad"; [ "$UDID" = "$IPHONE" ] && PREFIX="iphone"

  shoot "$UDID" "$PREFIX-empty" SIMCTL_CHILD_DS_START_EMPTY=1
  shoot "$UDID" "$PREFIX-chat" SIMCTL_CHILD_DS_DEMO_THREAD=1
  shoot "$UDID" "$PREFIX-history" SIMCTL_CHILD_DS_DEMO_THREAD=1 SIMCTL_CHILD_DS_DEMO_HISTORY=1 SIMCTL_CHILD_DS_SHOW_HISTORY=1

  shoot "$UDID" "$PREFIX-balance" SIMCTL_CHILD_DS_DEMO_THREAD=1 SIMCTL_CHILD_DS_SHOW_BALANCE=1
  shoot "$UDID" "$PREFIX-usage" SIMCTL_CHILD_DS_DEMO_THREAD=1 SIMCTL_CHILD_DS_SHOW_USAGE=1
  shoot "$UDID" "$PREFIX-settings" SIMCTL_CHILD_DS_DEMO_THREAD=1 SIMCTL_CHILD_DS_SHOW_SETTINGS=1
  shoot "$UDID" "$PREFIX-prompt" SIMCTL_CHILD_DS_SHOW_SETTINGS=1 SIMCTL_CHILD_DS_SETTINGS_PAGE=prompt
  shoot "$UDID" "$PREFIX-skills" SIMCTL_CHILD_DS_SHOW_SETTINGS=1 SIMCTL_CHILD_DS_SETTINGS_PAGE=skills SIMCTL_CHILD_DS_MEMORY_STORE=1

  xcrun simctl ui "$UDID" appearance dark
  shoot "$UDID" "$PREFIX-dark" SIMCTL_CHILD_DS_DEMO_THREAD=1
  xcrun simctl ui "$UDID" appearance light
done
