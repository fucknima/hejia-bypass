#!/bin/sh
# 用 clang 做 iOS 目标 + 头文件桩的语法/语义检查
set -e
D=$(cd "$(dirname "$0")" && pwd)
clang -fsyntax-only -x objective-c++ \
  -target arm64-apple-ios14.0 \
  -fobjc-arc \
  -fblocks \
  -I"$D/stubs" -I"$D/stubs/Foundation" -I"$D/stubs/CoreFoundation" \
  -Wall -Wextra -Wno-unused-parameter -Wno-unused-function \
  "$D/../Tweak.xm"
echo "=== 语法检查通过 ==="
