#!/bin/bash
# 用法：./build.sh                  正式版 roothide 包（不显示「调试」区）
#       ./build.sh rootless         正式版 rootless 包
#       ./build.sh debug            调试版：设置页显示 运行日志 / 动作自检 / 系统接口诊断
#       ./build.sh rootless debug   调试版 rootless 包
# 只装了 CommandLineTools、没装 Xcode 时，clang modules 会报 SwiftBridging 重复定义，所以清空 MODULESFLAGS。
set -e
cd "$(dirname "$0")"
export THEOS="${THEOS:-$HOME/theos-roothide}"
SCHEME=roothide; DEBUGUI=0
for a in "$@"; do
  case "$a" in
    rootless|roothide) SCHEME="$a" ;;
    debug) DEBUGUI=1 ;;
    *) echo "未知参数：$a"; exit 1 ;;
  esac
done
ARCH=iphoneos-arm64e; [ "$SCHEME" = rootless ] && ARCH=iphoneos-arm64
sed -i '' "s/^Architecture: .*/Architecture: $ARCH/" control
make clean >/dev/null 2>&1 || true
make package FINALPACKAGE=1 MODULESFLAGS= THEOS_PACKAGE_SCHEME="$SCHEME" CX_DEBUG_UI="$DEBUGUI"
[ "$DEBUGUI" = 1 ] && echo "⚠️  这是调试版（设置页带「调试」区）" || true
