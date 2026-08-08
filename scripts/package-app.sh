#!/bin/bash
set -euo pipefail

# 把签好名的 .app 打成一个可以直接发给别人的 zip。
#
# 必须用 ditto，不能用 zip：zip 不保留 macOS 的扩展属性，解压出来的
# .app 签名会坏掉，对方那边表现为「已损坏，应将其移到废纸篓」——
# 比「未公证」还吓人，而且完全是打包方式造成的。
# 脚本打完会自己解压回来验一次签名，确认这条没被破坏。

APP_NAME="IELTS Speaking Coach"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/$APP_NAME.app"
DIST="$ROOT/.build/dist"
ZIP="$DIST/$APP_NAME.zip"

echo "▶︎ 先打包并签名…"
"$ROOT/scripts/build-app.sh"

echo "▶︎ 生成分发目录…"
rm -rf "$DIST"
mkdir -p "$DIST"
cp "$ROOT/packaging/open-instructions.txt" "$DIST/如何打开.txt"

echo "▶︎ 压缩（ditto，保留签名所需的扩展属性）…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▶︎ 自检：把 zip 解回来验签名…"
VERIFY_DIR="$DIST/.verify"
rm -rf "$VERIFY_DIR"; mkdir -p "$VERIFY_DIR"
ditto -x -k "$ZIP" "$VERIFY_DIR"
if ! codesign --verify --strict "$VERIFY_DIR/$APP_NAME.app" 2>/dev/null; then
    echo "❌ 压缩包里的签名坏了。"
    echo "   发生了什么：打包过程破坏了 .app 的扩展属性，"
    echo "   对方解压后会看到「已损坏，应将其移到废纸篓」。"
    echo "   下一步：确认这里用的是 ditto -c -k --keepParent，不是 zip -r。"
    exit 1
fi
rm -rf "$VERIFY_DIR"

echo
echo "✅ 可以发出去了："
echo "   $ZIP"
echo "   $DIST/如何打开.txt"
echo "   大小 $(du -h "$ZIP" | cut -f1)"
echo "   SHA256 $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo
echo "ℹ️  这份包没有经过 Apple 公证，对方第一次打开会被系统拦下。"
echo "   「如何打开.txt」里已经写清了怎么办，记得一起发过去。"
