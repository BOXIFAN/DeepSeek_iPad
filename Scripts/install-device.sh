#!/usr/bin/env bash
# 把 App 装到已连接的 iPad / iPhone 上。
#
# 用法：./Scripts/install-device.sh [设备 UDID]
# 不传 UDID 时自动选第一个物理设备。
#
# 前置（脚本会检查并提示）：
#   1. 设备已开启开发者模式（设置 → 隐私与安全性 → 开发者模式）
#   2. Xcode 里已登录 Apple ID，并在 Signing & Capabilities 里选好 Team
set -euo pipefail
cd "$(dirname "$0")/.."

export TMPDIR="$PWD/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH"

red()   { printf "\033[31m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
dim()   { printf "\033[2m%s\033[0m\n" "$1"; }

# ---------- 1. 找设备 ----------

DEVICE_UDID="${1:-}"
if [ -z "$DEVICE_UDID" ]; then
  xcrun devicectl list devices --json-output /tmp/dsh-devices.json >/dev/null 2>&1 || true
  DEVICE_UDID=$(python3 - <<'PY' 2>/dev/null || true
import json
try:
    data = json.load(open('/tmp/dsh-devices.json'))
except Exception:
    raise SystemExit(0)
for dev in data.get('result', {}).get('devices', []):
    hw = dev.get('hardwareProperties', {})
    if hw.get('reality') == 'physical' and hw.get('udid'):
        print(hw['udid'])
        break
PY
)
fi

if [ -z "$DEVICE_UDID" ]; then
  red "没有找到已连接的物理设备。"
  dim "  插上数据线，在设备上点「信任此电脑」，然后重新运行。"
  exit 1
fi

dim "设备：$DEVICE_UDID"

# ---------- 2. 检查开发者模式 ----------

INFO=$(xcrun devicectl device info details --device "$DEVICE_UDID" 2>&1 || true)
if printf "%s" "$INFO" | grep -q "Developer Mode is turned off"; then
  red "设备没有开启开发者模式。"
  dim "  iPad / iPhone 上：设置 → 隐私与安全性 → 开发者模式 → 打开，然后重启设备。"
  exit 1
fi

# ---------- 3. 检查签名 ----------

IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null | grep -c "Apple Development" || true)
if [ "$IDENTITIES" -eq 0 ]; then
  red "本机没有 Apple Development 签名证书。"
  dim "  先在 Xcode 里登录账号：Xcode → Settings → Accounts → 加 Apple ID"
  dim "  再选 Team：Xcode 打开工程 → iPadDS target → Signing & Capabilities → Team"
  dim "  这两步做完证收会自动生出来，回来重跑这个脚本即可。"
  exit 1
fi

# ---------- 4. 构建 ----------

green "开始构建（真机架构，第一次会慢一些）…"
xcodebuild \
  -project iPadDS.xcodeproj \
  -scheme iPadDS \
  -destination "platform=iOS,id=$DEVICE_UDID" \
  -derivedDataPath .build/DerivedData \
  -allowProvisioningUpdates \
  build 2>&1 | tail -5

APP=".build/DerivedData/Build/Products/Debug-iphoneos/iPadDS.app"
if [ ! -d "$APP" ]; then
  red "没找到构建产物：$APP"
  exit 1
fi

# ---------- 5. 安装并启动 ----------

green "安装到设备…"
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP" 2>&1 | grep -vE "^\s*$" | tail -5

green "启动…"
xcrun devicectl device process launch --device "$DEVICE_UDID" com.ruakiu.ipadds 2>&1 | tail -3 || true

green "完成。第一次打开如果提示「未受信任的开发者」："
dim "  设备 → 设置 → 通用 → VPN 与设备管理 → 选你的 Apple ID → 信任"
dim "  然后在 App 里重新填一次 API Key（Keychain 不跨设备）。"
