#!/bin/bash
set -euo pipefail

# 校验 iconset 与 .icns 的尺寸是否齐全。
#
# 为什么必须有这道校验：`iconutil -c icns` 遇到像素尺寸与文件名不符的 PNG 会
# **静默跳过**那个表示——不打印警告，退出码仍然是 0。曾经因此打出只含 6 个表示
# 的 .icns（16×16、32×32、128×128、256×256 四档被悄悄丢掉），而打包脚本照样
# 打印「✅ 已生成」。铁律 7：禁止静默失败。
#
# 用法：verify-iconset.sh <iconset 目录> <icns 文件>

fail() {
    echo "❌ $1" >&2
    echo "   下一步：$2" >&2
    exit 1
}

if [ "$#" -ne 2 ]; then
    fail "verify-iconset.sh 需要两个参数，实际收到 $# 个。" \
         "按 verify-iconset.sh <iconset 目录> <icns 文件> 的形式调用。"
fi

ICONSET="$1"
ICNS="$2"

# 文件名里的尺寸是「点」，@2x 的像素要翻倍——这里写的是**像素**边长。
EXPECTED="icon_16x16.png:16
icon_16x16@2x.png:32
icon_32x32.png:32
icon_32x32@2x.png:64
icon_128x128.png:128
icon_128x128@2x.png:256
icon_256x256.png:256
icon_256x256@2x.png:512
icon_512x512.png:512
icon_512x512@2x.png:1024"

[ -d "$ICONSET" ] || fail "找不到 iconset 目录 ${ICONSET}。" \
    "先跑 ./scripts/make-icon.sh 生成图标，再重试。"

# ---- 第一关：10 个 PNG 都在，且像素尺寸与文件名一致 ----
while IFS=: read -r name side; do
    path="$ICONSET/$name"
    [ -f "$path" ] || fail "iconset 里缺少 ${name}（${ICONSET}）。" \
        "检查 scripts/make-icon.swift 末尾的循环是否写全了 10 个文件，然后重跑 ./scripts/make-icon.sh。"

    if ! probe=$(sips -g pixelWidth -g pixelHeight "$path" 2>&1); then
        fail "读不到 $name 的像素尺寸：$probe" \
             "确认该文件是完整的 PNG（可能写盘中断），删掉 .build/AppIcon.iconset 后重跑 ./scripts/make-icon.sh。"
    fi
    width=$(printf '%s\n' "$probe" | awk '/pixelWidth/ {print $2}')
    height=$(printf '%s\n' "$probe" | awk '/pixelHeight/ {print $2}')

    if [ "$width" != "$side" ] || [ "$height" != "$side" ]; then
        fail "$name 是 ${width}×${height} 像素，应为 ${side}×${side}；iconutil 会静默丢掉这个尺寸。" \
             "多半是绘图代码用了跟随屏幕缩放的 NSImage.lockFocus()。改用显式的 NSBitmapImageRep(pixelsWide:pixelsHigh:) 后重跑 ./scripts/make-icon.sh。"
    fi
done <<< "$EXPECTED"

# ---- 第二关：.icns 里真的打进了这 10 个表示 ----
[ -f "$ICNS" ] || fail "找不到 ${ICNS}。" \
    "先跑 ./scripts/make-icon.sh 生成 .icns，再重试。"

ROUNDTRIP="$(mktemp -d)"
trap 'rm -rf "$ROUNDTRIP"' EXIT

# 把 .icns 反向转回 iconset：转出来有哪些文件，里面就真的有哪些表示。
if ! out=$(iconutil -c iconset "$ICNS" -o "$ROUNDTRIP/check.iconset" 2>&1); then
    fail "$ICNS 解不开，可能不是合法的 .icns：$out" \
         "删掉它后重跑 ./scripts/make-icon.sh。"
fi

missing=""
while IFS=: read -r name side; do
    [ -f "$ROUNDTRIP/check.iconset/$name" ] || missing="$missing $name"
done <<< "$EXPECTED"

if [ -n "$missing" ]; then
    fail "$ICNS 里缺少这些尺寸：$missing" \
         "iconutil 把尺寸不合格的 PNG 静默丢掉了。先核对 $ICONSET 里各 PNG 的像素尺寸，修好后重跑 ./scripts/make-icon.sh。"
fi
