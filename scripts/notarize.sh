#!/bin/bash
set -euo pipefail

# >>> 帮助 >>>
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
#
# 有一条顺序躲不开：换成 Developer ID 会改变签名的「指定要求」，而 build-app.sh
# 拿它跟 packaging/expected-designated-requirement.txt 逐字比对，不一致就 exit 1。
# 所以基线必须先更新、再重签，反过来重签那一步永远跑不过去。
# --execute 的第 1 步就是核对这件事：它用你的证书在一份临时副本上试签，
# 把该写进基线的那一行原样算给你——但不替你改仓库里的文件。
# <<< 帮助 <<<

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
            echo "❌ 不认识的参数「${arg}」。"
            echo "   下一步：只能传 --dry-run（默认）、--execute 或 --help。"
            exit 2
            ;;
    esac
done

if [[ "$MODE" == "help" ]]; then
    # 用成对的标记框出帮助文本，不用行号。计划里写的是 sed -n '3,20p'，
    # 那个范围会把下面 APP_NAME/BUNDLE_ID/ROOT… 几行 shell 赋值一起打进帮助里；
    # 而且行号这种东西一改脚本就会悄悄错位。
    # testHelpPrintsTheUsageWithoutLeakingShellCode 守着。
    sed -n '/^# >>> 帮助 >>>$/,/^# <<< 帮助 <<<$/p' "$0" | sed '1d;$d'
    exit 0
fi

echo "════════════════════════════════════════════════════════════"
echo " 公证（模式：${MODE}）"
echo "════════════════════════════════════════════════════════════"
echo
echo "⚠️  换成 Developer ID 证书会改变签名的「指定要求」。"
echo "   发生了什么：指定要求里带着证书信息，换了证书它就变了，"
echo "   系统会把重签后的 App 当成另一个程序——本机已授予的辅助功能授权会失效。"
echo "   下一步（这两件事的先后不能颠倒）："
echo "     1.〔重签之前〕把新的指定要求写进 packaging/expected-designated-requirement.txt 并提交。"
echo "        build-app.sh 用同一个文件当闸门，基线没换，重签那一步会被它当场 exit 1 挡掉，"
echo "        后面压包、提交公证几步永远到不了。--execute 的第 1 步会替你算出该写哪一行。"
echo "     2.〔重签之后〕到 系统设置 › 隐私与安全性 › 辅助功能，删掉旧条目，重新勾选一次。"
echo "   这一次失效躲不掉，但只发生一次，而且只影响你自己这台开发机。"
echo

# ── 前置条件 ────────────────────────────────────────────────
# 顺序有意义：先查最难补的（证书要加入 Apple Developer Program，按年付费、还要等审核），
# 再查随手就能补的（.app 重打一次就有）。

MISSING=0

# $1=是否满足(0/1)  $2=名称  $3=发生了什么  $4=下一步
# 「发生了什么」和「下一步」两段都得打出来——
# testEveryPreconditionSaysWhatHappenedAndWhatToDoNext 逐条查。
check() {
    if [[ "$1" -eq 0 ]]; then
        echo "✅ $2"
    else
        echo "⚠️  $2"
        echo "   发生了什么：$3"
        echo "   下一步：$4"
        MISSING=1
    fi
}

echo "前置条件（本期预期就是缺 Developer ID 和公证凭据，那不算出错）："

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
    "找不到 ${APP}。" \
    "先跑 ./scripts/package-app.sh"

DEV_ID_DISPLAY="${DEV_ID:-<Developer ID Application: 你的名字 (TEAMID)>}"
PROFILE_DISPLAY="${PROFILE:-<你的公证凭据档案名>}"

echo
cat <<EOF
公证流程（共 6 步）：

  1. 先把签名基线换成这张 Developer ID 的（顺序不能反）
       --execute 会用你的证书在一份临时副本上试签一次，算出新的「指定要求」，
       跟 $BASELINE 逐字比。
       不一致时它把该写进去的那一行原样打给你，你写进文件、提交，再跑一次。
       为什么必须排在重签前面：build-app.sh 用同一个文件当闸门，基线没换，
       下面第 2 步会被它 exit 1 挡掉，第 3 步以后永远到不了。

  2. 用 Developer ID 证书重新签名（Hardened Runtime + entitlements + 安全时间戳）
       IELTS_SIGN_IDENTITY="$DEV_ID_DISPLAY" \\
       IELTS_SIGNATURE_CHANNEL=developer-id \\
       ./scripts/build-app.sh
       codesign --force --sign "$DEV_ID_DISPLAY" --identifier $BUNDLE_ID \\
         --options runtime --entitlements "$ENTITLEMENTS" --timestamp "$APP"
     （公证要求安全时间戳，所以这一步用 --timestamp 而不是本地打包的 --timestamp=none）

  3. 压成 zip —— 必须用 ditto，zip 命令会破坏签名所需的扩展属性
       ditto -c -k --keepParent "$APP" "$ZIP"

  4. 提交公证并等结果（通常几分钟）
       xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE_DISPLAY" --wait
     失败时用 xcrun notarytool log <submission-id> --keychain-profile "$PROFILE_DISPLAY"
     看具体是哪个二进制不合规。

  5. 把公证票据钉进 .app（钉过之后对方离线也能通过校验）
       xcrun stapler staple "$APP"

  6. 用系统自己的判定确认真的成了
       spctl -a -vvv -t exec "$APP"
     期望看到 accepted，且 source=Notarized Developer ID
     （现在这份自签名的包在这里是 rejected，那是正常的、也是必然的）

──── 完成之后还有两件事 ────
  · 把第 1 步更新过的 $BASELINE 提交进仓库。
  · 到 系统设置 › 隐私与安全性 › 辅助功能，删掉旧条目、重新勾选一次。
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
echo "▶︎ 1/6 核对签名基线…"

# 为什么要先单独试签一份副本：换证书必然改变签名的「指定要求」，而 build-app.sh
# 会拿它跟基线逐字比对，不一致就 exit 1。不先核对就直接往下走的话，第 2 步必然
# 死在那道闸门上，而且用户看到的是 build-app.sh 的报错，看不出「其实是顺序反了」。
#
# 只签一份临时副本，不碰 .build 里那个 .app；--timestamp=none 所以不联网。
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ielts-notarize-probe.XXXXXX")"
trap 'rm -rf "$PROBE_DIR"' EXIT
cp -R "$APP" "$PROBE_DIR/probe.app"
codesign --force --sign "$DEV_ID" --identifier "$BUNDLE_ID" \
         --options runtime --entitlements "$ENTITLEMENTS" \
         --timestamp=none "$PROBE_DIR/probe.app"

NEW_DESIGNATED="$(codesign -d -r- "$PROBE_DIR/probe.app" 2>&1 | grep designated || true)"
if [[ -z "$NEW_DESIGNATED" ]]; then
    echo "❌ 读不出试签之后的「指定要求」。"
    echo "   发生了什么：codesign -d -r- 没吐出 designated 那一行，说明这次试签没真正生效。"
    echo "   下一步：手动跑一次上面第 2 步里的 codesign 看它报什么错。"
    echo "   最常见的原因是证书在、私钥不在（PKCS12 只导进了一半）。"
    exit 1
fi

if [[ ! -f "$BASELINE" ]]; then
    echo "❌ 找不到签名基线文件 ${BASELINE}。"
    echo "   发生了什么：packaging/ 目录不完整。缺了它，build-app.sh 会把下次签出来的东西"
    echo "   直接当成基线记下来——万一那时签名已经退化成 ad-hoc，这道闸门就永远绿灯了。"
    echo "   下一步：git checkout -- packaging/expected-designated-requirement.txt 恢复它，再跑一次。"
    exit 1
fi

OLD_DESIGNATED="$(cat "$BASELINE")"
if [[ "$NEW_DESIGNATED" != "$OLD_DESIGNATED" ]]; then
    echo
    echo "❌ 先更新签名基线，再公证——现在这个顺序反了，直接重签一定会被 build-app.sh 拦下。"
    echo "   发生了什么：签名的「指定要求」里带着证书信息，换成这张 Developer ID 之后它变了。"
    echo "   build-app.sh 拿它跟基线文件逐字比对，不一致就 exit 1；"
    echo "   所以基线更新之前，上面第 2 步（重签）不可能跑得过去。"
    echo "   基线现在是：      $OLD_DESIGNATED"
    echo "   换证书之后会是：  $NEW_DESIGNATED"
    echo "   下一步（做完这三件事再跑一次 --execute）："
    echo "     1. 记录新基线——下面这一行是刚刚用你的证书试签算出来的，不是猜的："
    echo "          printf '%s\\n' '$NEW_DESIGNATED' > $BASELINE"
    echo "     2. 提交它：git add packaging/expected-designated-requirement.txt && git commit"
    echo "     3. 公证完、把新包装上之后，到 系统设置 › 隐私与安全性 › 辅助功能，"
    echo "        删掉旧条目、重新勾选一次（这次失效躲不掉，但只发生一次）。"
    exit 1
fi
echo "✅ 基线已经指向这张证书，重签不会被闸门拦下。"

echo "▶︎ 2/6 用 Developer ID 重新签名…"
IELTS_SIGN_IDENTITY="$DEV_ID" IELTS_SIGNATURE_CHANNEL=developer-id "$ROOT/scripts/build-app.sh"
codesign --force --sign "$DEV_ID" --identifier "$BUNDLE_ID" \
         --options runtime --entitlements "$ENTITLEMENTS" --timestamp "$APP"

echo "▶︎ 3/6 压缩…"
mkdir -p "$(dirname "$ZIP")"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▶︎ 4/6 提交公证（可能要等几分钟）…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▶︎ 5/6 钉票据…"
xcrun stapler staple "$APP"

echo "▶︎ 6/6 用系统判定确认…"
spctl -a -vvv -t exec "$APP"

echo
echo "✅ 公证完成。"
echo "   下一步：把第 1 步更新过的 $BASELINE 提交进仓库（如果还没提交），"
echo "   然后到 系统设置 › 隐私与安全性 › 辅助功能 删掉旧条目、重新勾选一次。"
