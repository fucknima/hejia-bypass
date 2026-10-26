#!/bin/sh
# 严格模拟 GitHub Actions 上的 Theos 编译环境：
#  - Theos 用 clang -x objective-c++ 预处理 .xm
#  - 走真实 iOS SDK 头文件语义（本桩已剔除 iOS 不提供的符号）
#  - -Werror 全开
set -e
D=$(cd "$(dirname "$0")" && pwd)
for ARCH in arm64 arm64e; do
  echo "### 编译 $ARCH"
  clang -c -x objective-c++ \
    -target ${ARCH}-apple-ios14.0 \
    -fobjc-arc -fblocks -O2 \
    -I"$D/stubs" -I"$D/stubs/Foundation" -I"$D/stubs/CoreFoundation" \
    -Wall -Wextra -Werror \
    -Wno-unused-parameter \
    -Wstrict-prototypes -Wmissing-prototypes \
    -o "/tmp/HJ_${ARCH}.o" "$D/../Tweak.xm"
  echo "  OK"
  echo "  C++ 修饰符号:"
  if llvm-nm -u "/tmp/HJ_${ARCH}.o" | grep -q "__Z"; then
    llvm-nm -u "/tmp/HJ_${ARCH}.o" | grep "__Z" | sed 's/^/    !! /'
    echo "  ❌ 存在 C++ 修饰，链接会失败"
    exit 1
  else
    echo "    (无)"
  fi
done
echo "=== 双架构均通过 ==="
