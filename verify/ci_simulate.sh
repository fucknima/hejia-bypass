#!/bin/sh
# 严格模拟 GitHub Actions 上的 Theos 编译环境
set -e
D=$(cd "$(dirname "$0")" && pwd)
FILES="Tweak.xm NoAds.xm UIPanel.mm SettingsVC.mm TabHide.mm"
for ARCH in arm64 arm64e; do
  for F in $FILES; do
    echo "### $F ($ARCH)"
    clang -c -x objective-c++ \
      -target ${ARCH}-apple-ios14.0 \
      -fobjc-arc -fblocks -O2 \
      -I"$D/stubs" -I"$D/stubs/Foundation" -I"$D/stubs/CoreFoundation" -I"$D/stubs/UIKit" \
      -Wall -Wextra -Werror \
      -Wno-unused-parameter \
      -Wstrict-prototypes -Wmissing-prototypes \
      -o "/tmp/$(basename $F .xm)_${ARCH}.o" "$D/../$F"
    if llvm-nm -u "/tmp/$(basename $F .xm)_${ARCH}.o" | grep -q "__Z"; then
      echo "  ❌ C++ 修饰符号"; exit 1
    fi
    echo "  OK"
  done
done
echo "=== 全部通过 ==="
