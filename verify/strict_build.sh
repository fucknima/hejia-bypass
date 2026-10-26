#!/bin/sh
# 严格编译：-Werror + iOS 目标，产出 arm64 目标文件
set -e
D=$(cd "$(dirname "$0")" && pwd)
OUT="${1:-/tmp/HeJiaBypass.o}"
clang -c -x objective-c \
  -target arm64-apple-ios14.0 \
  -fobjc-arc -fblocks -O2 \
  -I"$D/stubs" -I"$D/stubs/Foundation" -I"$D/stubs/CoreFoundation" \
  -Wall -Wextra -Werror \
  -Wno-unused-parameter \
  -Wstrict-prototypes -Wmissing-prototypes \
  -o "$OUT" "$D/../Tweak.xm"
echo "=== 严格编译通过 -> $OUT ==="
llvm-objdump -h "$OUT" | head -14
