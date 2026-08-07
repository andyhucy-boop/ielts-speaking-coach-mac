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
# 「这次比较不是空转」由构建号那两条断言守住：
#   · 两次的 CFBundleVersion 必须确实是要求的那两个不同的号
#     —— 这条直接验「IELTS_BUILD_NUMBER 真的被写进了包」，也是唯一能拦住
#        「两次其实用了同一个号」的断言。
# 还留了一条「两次的 CDHash 必须不同」，它验「签的确实是两个不同的包」，
# 但它实际上永远是绿的（原因见下一段），别指望它拦住什么。
#
# 为什么不能只留 CDHash 那条（2026-08-07 实测）：build-app.sh 会把打包时刻
# （IELTSBuildDate，精确到秒）写进 Info.plist，所以哪怕两次构建号一字不差，
# CDHash 照样不同（实测同为 90001 的两次打包得到 25115b9b… 与 aa04fe6b…）。
# 也就是说 CDHash 那条断言永远是绿的，单靠它守不住「两次是同一个号」。
#
# ── 职责划分：真正的闸门不在本脚本里（2026-08-08 复审后补记，勿删）────────────
#
# build-app.sh 每打一次包，自己就会验两件事：「指定要求」的形状对不对（identifier +
# certificate leaf），以及它跟 packaging/expected-designated-requirement.txt 是否逐字相同。
# 任何一件不对，那次打包当场 exit 1，本脚本在 run_build 里就停了。
# 反过来，两次打包都成功 ⇒ 两次的 designated 都逐字等于基线 ⇒ 必然彼此相等。
#
# 所以下面「两次是否一致」和「是否与基线相符」这两条断言，在正常路径下不可达：
# 把它们整段删掉，不会有任何场景因此变红。这一点是 2026-08-08 用「删掉再跑」实测确认的
# ——正常路径照样 ✅ 退 0，ad-hoc 突变照样停在 run_build 退 1，输出一字不差。
# 按本项目对空转测试的判据，它们就是空转。留着它们是当 build-app.sh 失守时的第二道防线
# （最现实的路径：将来给 build-app.sh 加一个「重签时跳过基线比对」的开关），
# **不是**本脚本的守门员——别照着它们的存在推断「这里在守门」。
#
# 为什么不把职责挪过来（即让 build-app.sh 少验、由本脚本来判）：
# build-app.sh 的「与基线逐字比对」比「两次互相比」严格得多。两次互相比只能发现
# 「两次不一样」，发现不了「两次一样地漂了」——而证书换了一张时正是后者。
# 而且它挂在 build-app.sh 上，意味着每一次打包都过闸，不用等谁想起来跑本脚本。
#
# 那本脚本到底验到了什么：它负责制造「两次打包的内容确实不同」这个前提，
# 再让 build-app.sh 的闸门在这两个确实不同的包上各跑一次。TCC 真正关心的性质
# 是「指定要求与二进制内容无关」，它就是这么被验到的——判定由 build-app.sh 做，
# 有差异的输入由本脚本提供。因此本脚本自己真正有约束力的断言只有构建号那两条
# ——它们保证这个前提确实成立；其余几条要么是恒绿的交叉验证，要么是下面说的第二道防线。
#
# ── 突变验证的实测结果（2026-08-08，与计划 Step 3 的 Expected 不符，以实测为准）──
#
# 把 build-app.sh 的 --sign "$SIGN_IDENTITY" 改成 --sign - 后重跑本脚本：
# 计划原稿写的 Expected 是「停在 ❌ 两次打包的「指定要求」不一致，退出非零」，
# 实际停在 run_build 的「❌ 第一次打包没成功」——build-app.sh 的形状自检先一步 exit 1
# （它贴出的是 `实际读到：# designated => cdhash H"…"`；那串哈希每打一次包都不一样，
# 正是 ad-hoc 的毛病本身），第二次打包根本没开始，下面那条 DR1 != DR2 一次都没执行。
# 退出码确实是 1，但被这次突变验到的是 build-app.sh 的闸门，不是本脚本的断言
# ——也就是说，突变 A 并没有覆盖本脚本的核心断言。
#
# 要让下面两条真的打印出来，必须同时拆掉 build-app.sh 的形状自检与基线比对、再配 ad-hoc
# 签名。实测那时两条都会红（那一次两个包分别是 cdhash H"757ce5d6…" 与 H"0d48a20e…"，
# 具体哈希每次重跑都不同，能复现的是「两次互不相同」这件事）——
# 说明这两条逻辑本身是对的，只是在当前的职责划分下永远轮不到它们。
#
# 突变 B（把 SECOND_BUILD_NUMBER 改成和第一个一样）也和计划原稿的 Expected 不同：
# 原稿写的是「停在 ❌ 两次打包的 CDHash 一模一样」，实测停在「❌ 两次打包用的是同一个构建号」
# ——CDHash 那条根本没红，原因就是上面写的 IELTSBuildDate。这正是当初补上构建号那两条断言
# 的理由；换句话说，「比较不是空转」这件事是靠构建号那两条守住的，不是靠 CDHash 那条。

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
        echo "❌ 第${ordinal}次打包没成功，后面的比较不做了。"
        echo "   下面是 scripts/build-app.sh 的完整输出，它自己的自检会说清是哪一项不对："
        sed 's/^/   │ /' "$log"
        echo "   下一步：先照上面那些提示把打包修好，再重跑本脚本。"
        echo "   另外：如果上面那段里是「指定要求」相关的 ❌（形状不对、或与基线不一致），"
        echo "   那本脚本要拦的问题已经被拦住了，就照它给的办法处理；本脚本后面那两条"
        echo "   同名断言不会再打印——它们排在打包之后，这一次走不到（见文件开头「职责划分」）。"
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

# 第二道防线，正常路径下不可达（原因见文件开头「职责划分」，别当它在守门）。
# 它能红只有一种情形：build-app.sh 的形状自检被拿掉，同时签名退化成了 ad-hoc。
if [[ "$DR1" != "$DR2" ]]; then
    echo "❌ 两次打包的「指定要求」不一致 —— 这正是要拦住的事。"
    echo "   第一次：$DR1"
    echo "   第二次：$DR2"
    echo "   发生了什么：签名不稳定，最常见的原因是用了 ad-hoc 签名（codesign -s -）。"
    echo "   后果：每次重新打包，用户的辅助功能授权都会失效，要回系统设置重新勾。"
    echo "   下一步：确认 build-app.sh 用的是固定证书「IELTS Coach Dev」，不是 -。"
    FAILED=1
fi

# 同样是第二道防线，正常路径下不可达：能走到这里，说明 build-app.sh 刚刚已经拿
# 同一个值跟同一个基线逐字比过了。它比上一条稍有用一点——将来若真给 build-app.sh 加了
# 「跳过基线比对」的开关，还剩这条能拦住漂移。
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

echo "✅ 连打两次，两个内容确实不同的包都通过了 build-app.sh 的「指定要求」闸门，"
echo "   复核两次的值也逐字一致、与基线相符："
echo "   $DR2"
echo "   两次的构建号分别是 $VERSION1 / $VERSION2，CDHash 分别是 $HASH1 / $HASH2"
echo "   （构建号与 CDHash 两两都不同，说明比的是两个不同的包，不是拿同一个包自己比自己）"
echo "   说明：判定由 build-app.sh 做，本脚本负责让两次打包的内容确实不同；"
echo "   上面那句「复核」在正常路径下必然成立，别把它当成守门的那一道（见开头「职责划分」）。"
