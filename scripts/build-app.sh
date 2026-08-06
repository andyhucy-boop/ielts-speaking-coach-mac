#!/bin/bash
set -euo pipefail

# 组装 .app 包并签名。
#
# 为什么必须用固定的自签名证书而不是 ad-hoc（codesign -s -）：
# TCC（辅助功能授权）记的是签名的「指定要求」。ad-hoc 绑的是二进制指纹 cdhash，
# 每次编译都变，用户得反复去系统设置重新勾选。自签名绑「标识 + 证书」，
# 编译多少次都不变。实测对比见计划的「前置条件」一节。

APP_NAME="IELTS Speaking Coach"
BUNDLE_ID="com.ielts.speakingcoach"
SIGN_IDENTITY="IELTS Coach Dev"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "▶︎ 编译…"
swift build -c release --product IELTSCoachApp

echo "▶︎ 组装 .app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/release/IELTSCoachApp" "$APP/Contents/MacOS/IELTSCoachApp"

echo "▶︎ 生成图标…"
"$ROOT/scripts/make-icon.sh"
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>IELTSCoachApp</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.3.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>开启「保存我的回答录音」后，用于录下你练习时的回答，便于回听。录音只存在本机，可随时删除。</string>
</dict>
</plist>
PLIST

# 立即校验生成的 plist 是否合法。少一个闭合标签就会让 App 起不来，
# 而那时的报错往往含糊到看不出是 plist 的问题。
plutil -lint "$APP/Contents/Info.plist" >/dev/null || {
    echo "❌ 生成的 Info.plist 不是合法 plist。"
    echo "   下一步：检查 build-app.sh 里那段 heredoc 的标签是否闭合。"
    exit 1
}

echo "▶︎ 签名…"

# 查的是「签名身份」（证书 + 私钥），不是「证书在不在」。
# security find-certificate 只要钥匙串里有那张证书就返回 0，而 codesign -s 要的是 identity。
# 只导进证书没导进私钥时（PKCS12 导入容易只成一半，换机器只拷 .cer 也一样），
# 查证书会放行，然后死在下面 codesign 的英文报错上——恰恰是这个闸门存在的目的所在的场景。
#
# 用不带 -v 的 find-identity：它会把未被信任的身份也列出来
# （显示为 CSSMERR_TP_NOT_TRUSTED），正好绕开「find-identity -v 显示 0 valid」那个坑。
if ! security find-identity -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
    echo "❌ 找不到可用的签名身份「${SIGN_IDENTITY}」（证书或私钥缺失）。"
    echo "   下一步：按 docs/superpowers/plans/2026-08-05-phase3-gui-shell.md「前置条件」一节重新创建。"
    echo "   注意 PKCS12 导入必须带 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1，"
    echo "   否则 macOS 读不了新版加密，会出现「证书在、私钥不在」这种半截状态。"
    exit 1
fi

codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"

# 签名成功什么都不证明——真正要守的是「指定要求」是否仍然稳定。
# TCC（辅助功能授权）记的就是它。ad-hoc 签名会让它变成 cdhash H"…"，
# 每打包一次就换一次，用户每次都得重新去系统设置勾选。
#
# 这一段必须在打印「✅ 已生成」**之前**跑，且不许 `|| true`。
# 触发路径不需要有人手改脚本：证书到期、或重新生成/重新导入一次，leaf 哈希就变了。
# 那时用户唯一的线索是 macOS 又来要一次辅助功能权限——查起来极难。
DESIGNATED="$(codesign -d -r- "$APP" 2>&1 | grep designated || true)"

if [ -z "$DESIGNATED" ]; then
    echo "❌ 读不出签名的指定要求（designated requirement）。"
    echo "   下一步：跑 codesign -d -r- \"$APP\" 看完整输出。签名可能没真正生效。"
    exit 1
fi

case "$DESIGNATED" in
    *"identifier \"$BUNDLE_ID\""*"certificate leaf"*)
        ;;
    *)
        echo "❌ 签名的指定要求不是预期形状，辅助功能授权会反复失效。"
        echo "   实际读到：$DESIGNATED"
        echo "   期望包含：identifier \"$BUNDLE_ID\" and certificate leaf = H\"…\""
        echo "   下一步：若里面是 cdhash，说明用成了 ad-hoc 签名（codesign -s -），"
        echo "   检查 SIGN_IDENTITY 是否为空；若 leaf 哈希变了，说明证书被重新生成过，"
        echo "   那么授权需要重做一次，之后才会重新稳定。"
        exit 1
        ;;
esac

echo "✅ 已生成 $APP"
echo "   $DESIGNATED"
