#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/.build/AppIcon.iconset"
ICNS="$ROOT/.build/AppIcon.icns"

mkdir -p "$ROOT/.build"
# 连旧的 .icns 一起删：生成中途失败时，不能留下一个上次的 .icns 让人以为是新的。
rm -rf "$ICONSET" "$ICNS"
swift "$ROOT/scripts/make-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ICNS"

# iconutil 对尺寸不合格的 PNG 是静默跳过 + 退出码 0，所以「转换成功」什么都不
# 证明。必须校验过尺寸齐全，才允许打印 ✅。
"$ROOT/scripts/verify-iconset.sh" "$ICONSET" "$ICNS"

echo "✅ 已生成 $ICNS（10 个尺寸齐全）"
