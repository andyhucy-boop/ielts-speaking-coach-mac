#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/.build/AppIcon.iconset"

rm -rf "$ICONSET"
swift "$ROOT/scripts/make-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ROOT/.build/AppIcon.icns"
echo "✅ 已生成 $ROOT/.build/AppIcon.icns"
