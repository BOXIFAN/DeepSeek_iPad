#!/usr/bin/env bash
# 编译到模拟器。
#
# 两个环境变量不是可选优化，是这个环境下的硬性条件：
#   TMPDIR / CLANG_MODULE_CACHE_PATH —— 沙盒不允许写 /var/folders 下的模块缓存
#   -disable-sandbox —— Swift 编译器默认用 sandbox-exec 隔离宏插件，沙盒里不能再套沙盒
# 这两个已写进 project.pbxproj 的 OTHER_SWIFT_FLAGS，此处只补环境变量。
set -euo pipefail
cd "$(dirname "$0")/.."

export TMPDIR="$PWD/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH"

DEST="${1:-platform=iOS Simulator,id=9C061938-493B-4BB4-BF5D-56EA001E774D}"

xcodebuild \
  -project iPadDS.xcodeproj \
  -scheme iPadDS \
  -destination "$DEST" \
  -derivedDataPath .build/DerivedData \
  build
