#!/bin/bash
set -euo pipefail

# 公证脚本。
#
# **本期不购买 Developer ID，也不实际执行公证**（设计文档第 10 节）。
# 这个脚本存在的意义是把「将来要怎么做」写成可以直接跑、而且有测试守着的东西，
# 而不是写成一段没人验证过的文档。默认 --dry-run：只检查前置条件、
# 原样打印将来要跑的每条命令，一个文件都不动。
#
# 用法：
#   ./scripts/notarize.sh            # 等同 --dry-run
#   ./scripts/notarize.sh --execute  # 真的公证（需要 Developer ID 与钥匙串凭据）

APP_NAME="IELTS Speaking Coach"
BUNDLE_ID="com.ielts.speakingcoach"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/$APP_NAME.app"
ZIP="$ROOT/.build/dist/$APP_NAME.zip"
ENTITLEMENTS="$ROOT/packaging/IELTSCoach.entitlements"
BASELINE="$ROOT/packaging/expected-designated-requirement.txt"

# 形如 "Developer ID Application: 你的名字 (TEAMID)"
DEV_ID="${IELTS_DEVELOPER_ID:-}"
# xcrun notarytool store-credentials 存进钥匙串的档案名
PROFILE="${IELTS_NOTARY_PROFILE:-}"

MODE="dry-run"
for arg in "$@"; do
    case "$arg" in
        --dry-run) MODE="dry-run" ;;
        --execute) MODE="execute" ;;
        -h|--help) MODE="help" ;;
        *)
            echo "❌ 不认识的参数「$arg」。"
            echo "   下一步：只能传 --dry-run（默认）、--execute 或 --help。"
            exit 2
            ;;
    esac
done

if [[ "$MODE" == "help" ]]; then
    # 只打印上面那段说明（第 4–13 行）。计划里写的是 '3,20p'，那个范围会把
    # 下面 APP_NAME/BUNDLE_ID/ROOT… 六行 shell 赋值一起打进帮助里——
    # 帮助信息是给人看的，不该混进代码。testHelpPrintsTheUsageWithoutLeakingShellCode 守着。
    sed -n '4,13p' "$0"
    exit 0
fi

echo "════════════════════════════════════════════════════════════"
echo " 公证（模式：$MODE）"
echo "════════════════════════════════════════════════════════════"
echo
echo "⚠️  换成 Developer ID 证书会改变签名的「指定要求」。"
echo "   发生了什么：指定要求里带着证书指纹，换了证书它就变了，"
echo "   系统会把重签后的 App 当成另一个程序——本机已授予的辅助功能授权会失效。"
echo "   下一步（公证完成后立刻做这两件事）："
echo "     1. 把新的指定要求写进 packaging/expected-designated-requirement.txt 并提交，"
echo "        否则 build-app.sh 会一直拦着不让打包。"
echo "     2. 到 系统设置 › 隐私与安全性 › 辅助功能，删掉旧条目，重新勾选一次。"
echo "   这一次失效躲不掉，但只发生一次，而且只影响你自己这台开发机。"
echo

# ── 前置条件 ────────────────────────────────────────────────
# 顺序有意义：先查最难补的（证书要加入 Apple Developer Program，按年付费、还要等审核），
# 再查随手就能补的（.app 重打一次就有）。

MISSING=0

check() {   # $1=是否满足(0/1)  $2=名称  $3=发生了什么  $4=下一步
    if [[ "$1" -eq 0 ]]; then
        echo "✅ $2"
    else
        echo "⚠️  $2"
        echo "   $3"
        echo "   下一步：$4"
        MISSING=1
    fi
}

if [[ -n "$DEV_ID" ]]; then HAS_ENV=0; else HAS_ENV=1; fi
check $HAS_ENV "Developer ID 证书名（环境变量 IELTS_DEVELOPER_ID）" \
    "没设置。公证必须用 Apple 签发的 Developer ID Application 证书，自签名证书不行。" \
    "先加入 Apple Developer Program（按年付费），在 developer.apple.com 申请并下载
   「Developer ID Application」证书装进钥匙串，然后
   export IELTS_DEVELOPER_ID=\"Developer ID Application: 你的名字 (TEAMID)\""

if [[ -n "$DEV_ID" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -qF "$DEV_ID"; then
    HAS_CERT=0
else
    HAS_CERT=1
fi
check $HAS_CERT "该证书在钥匙串里且可用于签名" \
    "security find-identity 里找不到它。" \
    "双击下载来的 .cer 装进 login 钥匙串；确认它连着私钥（钥匙串里能展开出一条私钥）。"

if xcrun --find notarytool >/dev/null 2>&1; then HAS_TOOL=0; else HAS_TOOL=1; fi
check $HAS_TOOL "xcrun notarytool 可用" \
    "找不到 notarytool，它随 Xcode 提供。" \
    "安装 Xcode，然后 sudo xcode-select -s /Applications/Xcode.app"

if [[ -n "$PROFILE" ]]; then HAS_PROFILE=0; else HAS_PROFILE=1; fi
check $HAS_PROFILE "公证凭据档案名（环境变量 IELTS_NOTARY_PROFILE）" \
    "没设置。凭据必须先存进钥匙串，本脚本不接受把密码写在命令行上。" \
    "xcrun notarytool store-credentials \"ielts-notary\" --apple-id <你的 Apple ID>
   --team-id <TEAMID> --password <App 专用密码>
   注意那是在 appleid.apple.com 生成的「App 专用密码」，不是你的 Apple ID 登录密码。
   存好之后 export IELTS_NOTARY_PROFILE=ielts-notary"

if [[ -d "$APP" ]]; then HAS_APP=0; else HAS_APP=1; fi
check $HAS_APP "已有打好的 .app" \
    "找不到 $APP。" \
    "先跑 ./scripts/package-app.sh"

DEV_ID_DISPLAY="${DEV_ID:-<Developer ID Application: 你的名字 (TEAMID)>}"
PROFILE_DISPLAY="${PROFILE:-<你的公证凭据档案名>}"

echo
cat <<EOF
公证流程（共 5 步）：

  1. 用 Developer ID 证书重新签名（Hardened Runtime + entitlements + 安全时间戳）
       IELTS_SIGN_IDENTITY="$DEV_ID_DISPLAY" \\
       IELTS_SIGNATURE_CHANNEL=developer-id \\
       ./scripts/build-app.sh
       codesign --force --sign "$DEV_ID_DISPLAY" --identifier $BUNDLE_ID \\
         --options runtime --entitlements "$ENTITLEMENTS" --timestamp "$APP"
     （公证要求安全时间戳，所以这一步用 --timestamp 而不是本地打包的 --timestamp=none）

  2. 压成 zip —— 必须用 ditto，zip 命令会破坏签名所需的扩展属性
       ditto -c -k --keepParent "$APP" "$ZIP"

  3. 提交公证并等结果（通常几分钟）
       xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE_DISPLAY" --wait
     失败时用 xcrun notarytool log <submission-id> --keychain-profile "$PROFILE_DISPLAY"
     看具体是哪个二进制不合规。

  4. 把公证票据钉进 .app（钉过之后对方离线也能通过校验）
       xcrun stapler staple "$APP"

  5. 用系统自己的判定确认真的成了
       spctl -a -vvv -t exec "$APP"
     期望看到 accepted，且 source=Notarized Developer ID
     （现在这份自签名的包在这里是 rejected，那是正常的、也是必然的）

  公证完成后别忘了更新 $BASELINE，并重新授权辅助功能。
EOF

if [[ "$MODE" == "dry-run" ]]; then
    echo
    echo "（--dry-run：以上命令一条都没有执行，也没有改动任何文件。）"
    exit 0
fi

if [[ $MISSING -ne 0 ]]; then
    echo
    echo "❌ 前置条件没满足，不执行公证。"
    echo "   下一步：把上面标了 ⚠️ 的几条按提示补齐，再跑一次 --execute。"
    exit 1
fi

echo
echo "▶︎ 1/5 用 Developer ID 重新签名…"
IELTS_SIGN_IDENTITY="$DEV_ID" IELTS_SIGNATURE_CHANNEL=developer-id "$ROOT/scripts/build-app.sh"
codesign --force --sign "$DEV_ID" --identifier "$BUNDLE_ID" \
         --options runtime --entitlements "$ENTITLEMENTS" --timestamp "$APP"

echo "▶︎ 2/5 压缩…"
mkdir -p "$(dirname "$ZIP")"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▶︎ 3/5 提交公证（可能要等几分钟）…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▶︎ 4/5 钉票据…"
xcrun stapler staple "$APP"

echo "▶︎ 5/5 用系统判定确认…"
spctl -a -vvv -t exec "$APP"

echo
echo "✅ 公证完成。"
echo "   下一步：把新的指定要求写进 $BASELINE 并提交，"
echo "   然后到 系统设置 › 隐私与安全性 › 辅助功能 重新勾选一次。"
