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
if ! security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    echo "❌ 找不到签名证书「$SIGN_IDENTITY」。"
    echo "   下一步：按 docs/superpowers/plans/2026-08-05-phase3-gui-shell.md「前置条件」一节重新创建，"
    echo "   否则每次编译后辅助功能授权都会失效，需反复去系统设置重新勾选。"
    exit 1
fi
codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"

echo "✅ 已生成 $APP"
codesign -d -r- "$APP" 2>&1 | grep designated || true
