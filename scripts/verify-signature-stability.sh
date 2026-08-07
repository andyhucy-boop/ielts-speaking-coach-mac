#!/bin/bash
set -euo pipefail

# 连打两次包，验证签名的「指定要求」完全一致。
#
# 为什么这是本阶段最要紧的一条：macOS 的 TCC（辅助功能授权）记的就是这个字符串。
# 它一变，系统就把新包当成另一个程序，用户之前勾的辅助功能权限当场失效，
# 得回系统设置重新勾一次。对这个产品来说这是最恼人的失败模式——
# 它不报错、不崩溃，只是「今天怎么又不能自动开练了」。
#
# 两次打包故意用不同的构建号，让包的内容确实不同。
# 不这么做的话两次打出一模一样的包，比较当然一致，等于什么都没验。
#
# 「这次比较不是空转」由两条断言一起守，缺一不可：
#   · 两次的 CFBundleVersion 必须确实是要求的那两个不同的号
#     —— 这条直接验「IELTS_BUILD_NUMBER 真的被写进了包」，也是唯一能拦住
#        「两次其实用了同一个号」的断言。
#   · 两次的 CDHash 必须不同 —— 这条验「签的确实是两个不同的包」。
#
# 为什么不能只留 CDHash 那条（2026-08-07 实测）：build-app.sh 会把打包时刻
# （IELTSBuildDate，精确到秒）写进 Info.plist，所以哪怕两次构建号一字不差，
# CDHash 照样不同（实测同为 90001 的两次打包得到 25115b9b… 与 aa04fe6b…）。
# 也就是说 CDHash 那条断言永远是绿的，单靠它守不住「两次是同一个号」。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="IELTS Speaking Coach"
APP="$ROOT/.build/$APP_NAME.app"
BASELINE="$ROOT/packaging/expected-designated-requirement.txt"

# 两个号只要不同即可，取远离真实构建号的值，避免和 git 提交数撞上。
FIRST_BUILD_NUMBER=90001
SECOND_BUILD_NUMBER=90002

# 这里刻意不写 grep '^designated'（与 build-app.sh 保持一致）：ad-hoc 签名下
# codesign 输出的是 `# designated => cdhash H"…"`，前面带一个井号（2026-08-07 实测）。
# 用行首锚定的话，恰恰在「签名退化成 ad-hoc」这个本脚本存在的头号场景里读成空串，
# 报出来的会是「读不出指定要求」——把人指向错误的方向。
read_designated()     { codesign -d -r- "$APP" 2>&1 | grep 'designated' || true; }
read_cdhash()         { codesign -dvvv  "$APP" 2>&1 | grep '^CDHash=' | head -1 || true; }
read_bundle_version() { plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist" 2>/dev/null || true; }

# 打一次包。成功时不刷屏，失败时把 build-app.sh 的完整输出原样贴出来再退出。
#
# 不直接写 `build-app.sh >/dev/null`：build-app.sh 所有「发生了什么 + 下一步做什么」
# 的提示都走 stdout，重定向到 /dev/null 会连同错误一起吞掉，
# 再配上 set -e，用户看到的就是「▶︎ 第一次打包…」之后一声不响地退出——
# 本项目明令禁止的静默失败。
run_build() {
    local ordinal="$1"
    local number="$2"
    local log
    log="$(mktemp -t ielts-signature-stability)"

    echo "▶︎ 第${ordinal}次打包（构建号 ${number}）…"
    if ! IELTS_BUILD_NUMBER="$number" "$ROOT/scripts/build-app.sh" >"$log" 2>&1; then
        echo "❌ 第${ordinal}次打包本身就没成功，签名稳不稳定也就无从验起。"
        echo "   下面是 scripts/build-app.sh 的完整输出，它自己的自检会说清是哪一项不对："
        sed 's/^/   │ /' "$log"
        echo "   下一步：先照上面那些提示把打包修好，再重跑本脚本。"
        rm -f "$log"
        exit 1
    fi
    rm -f "$log"
}

run_build "一" "$FIRST_BUILD_NUMBER"
DR1="$(read_designated)"; HASH1="$(read_cdhash)"; VERSION1="$(read_bundle_version)"

run_build "二" "$SECOND_BUILD_NUMBER"
DR2="$(read_designated)"; HASH2="$(read_cdhash)"; VERSION2="$(read_bundle_version)"

FAILED=0

if [[ -z "$DR1" || -z "$DR2" ]]; then
    echo "❌ 有一次没读出「指定要求」。"
    echo "   发生了什么：包可能没真正签上名，这次比较得不出任何结论。"
    echo "   下一步：单独跑 codesign -d -r- \"$APP\" 看它输出了什么。"
    FAILED=1
fi

if [[ "$VERSION1" != "$FIRST_BUILD_NUMBER" || "$VERSION2" != "$SECOND_BUILD_NUMBER" ]]; then
    echo "❌ 构建号没有按要求写进包里。"
    echo "   要求的是 $FIRST_BUILD_NUMBER / $SECOND_BUILD_NUMBER，包里读到的是「$VERSION1」/「$VERSION2」。"
    echo "   发生了什么：build-app.sh 没把 IELTS_BUILD_NUMBER 写进 Info.plist 的 CFBundleVersion，"
    echo "   这两个包不是按预期打出来的，后面的比较不算数。"
    echo "   下一步：检查 build-app.sh 里读 IELTS_BUILD_NUMBER 的那一段，与 Info.plist 里的 CFBundleVersion。"
    FAILED=1
fi

if [[ "$VERSION1" == "$VERSION2" ]]; then
    echo "❌ 两次打包用的是同一个构建号（都是 $VERSION1）。"
    echo "   发生了什么：两次打的其实是同一个版本，这次比较什么都没验证到。"
    echo "   下一步：把本脚本开头的 FIRST_BUILD_NUMBER 与 SECOND_BUILD_NUMBER 改回两个不同的号。"
    FAILED=1
fi

if [[ "$HASH1" == "$HASH2" ]]; then
    echo "❌ 两次打包的 CDHash 一模一样（$HASH1）。"
    echo "   发生了什么：两次签的是内容完全相同的包，这次比较什么都没验证到。"
    echo "   下一步：确认 build-app.sh 真的把 IELTS_BUILD_NUMBER 写进了 Info.plist 的 CFBundleVersion。"
    FAILED=1
fi

if [[ "$DR1" != "$DR2" ]]; then
    echo "❌ 两次打包的「指定要求」不一致 —— 这正是要拦住的事。"
    echo "   第一次：$DR1"
    echo "   第二次：$DR2"
    echo "   发生了什么：签名不稳定，最常见的原因是用了 ad-hoc 签名（codesign -s -）。"
    echo "   后果：每次重新打包，用户的辅助功能授权都会失效，要回系统设置重新勾。"
    echo "   下一步：确认 build-app.sh 用的是固定证书「IELTS Coach Dev」，不是 -。"
    FAILED=1
fi

if [[ -f "$BASELINE" && "$DR2" != "$(cat "$BASELINE")" ]]; then
    echo "❌ 「指定要求」与仓库里记录的基线不一致。"
    echo "   基线：$(cat "$BASELINE")"
    echo "   本次：$DR2"
    echo "   发生了什么：这台机器打出来的包，系统会当成跟基线那个不同的程序，"
    echo "   用户之前给的辅助功能授权会失效。"
    echo "   下一步：见 build-app.sh 里同名检查打印的两条处理办法（A 修证书 / B 更新基线并重新授权）。"
    FAILED=1
fi

if [[ $FAILED -ne 0 ]]; then exit 1; fi

echo "✅ 连打两次，「指定要求」完全一致，且与基线相符："
echo "   $DR2"
echo "   两次的构建号分别是 $VERSION1 / $VERSION2，CDHash 分别是 $HASH1 / $HASH2"
echo "   （构建号与 CDHash 两两都不同，说明这次比较是有效的，不是拿同一个包自己比自己）"
