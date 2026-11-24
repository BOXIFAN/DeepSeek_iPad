#!/usr/bin/env bash
# 装到指定模拟器并截图。
# 用法: Scripts/shot.sh <udid> <输出png路径>
set -euo pipefail
cd "$(dirname "$0")/.."

UDID="${1:?需要模拟器 UDID}"
OUT="${2:-shots/shot.png}"
APP="$PWD/.build/DerivedData/Build/Products/Debug-iphonesimulator/iPadDS.app"

mkdir -p "$(dirname "$OUT")"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b 2>&1 | tail -2

xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" com.ruakiu.ipadds 2>/dev/null || true
xcrun simctl launch "$UDID" com.ruakiu.ipadds

sleep 4
xcrun simctl io "$UDID" screenshot "$OUT"
echo "saved: $OUT"
