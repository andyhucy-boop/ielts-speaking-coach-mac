#!/bin/bash
set -euo pipefail

# 组装 .app 包并签名。
#
# 为什么必须用固定的自签名证书而不是 ad-hoc（codesign -s -）：
# TCC（辅助功能授权）记的是签名的「指定要求」。ad-hoc 绑的是二进制指纹 cdhash，
# 每次编译都变，用户得反复去系统设置重新勾选。自签名绑「标识 + 证书」，
# 编译多少次都不变。实测对比见计划的「前置条件」一节。
#
# 组装期自检两件事（Phase 5 Task 10 / Phase 9 Task 11 留下来的，勿删）：
#   · Info.plist 里有 CFBundleURLTypes 且 scheme 是 ieltscoach
#   · Info.plist 里有 NSMicrophoneUsageDescription
#
# 签名期自检四件事（Phase 10 Task 1 新增两件、加严一件），任何一件不对都退出非零：
#   1. 签名本身有效（codesign --verify --strict）
#   2. 带了 Hardened Runtime 标志
#   3. 带了麦克风 entitlement（没有它，Hardened Runtime 下录音会被系统拒掉）
#   4. 「指定要求」形状正确，且与 packaging/expected-designated-requirement.txt 逐字一致
# 第 4 条是本产品最恼人失败模式的守门员：它一变，用户的辅助功能授权就没了，
# 而且不会有任何报错，只是「今天怎么又不能自动开练了」。

APP_NAME="IELTS Speaking Coach"
BUNDLE_ID="com.ielts.speakingcoach"
APP_VERSION="1.3.0"

# 可被环境变量覆盖，供 notarize.sh 用 Developer ID 重签时复用同一套组装逻辑。
SIGN_IDENTITY="${IELTS_SIGN_IDENTITY:-IELTS Coach Dev}"
SIGNATURE_CHANNEL="${IELTS_SIGNATURE_CHANNEL:-self-signed}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
APP="$BUILD_DIR/$APP_NAME.app"
ENTITLEMENTS="$ROOT/packaging/IELTSCoach.entitlements"
BASELINE="$ROOT/packaging/expected-designated-requirement.txt"

if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "❌ 找不到 entitlements 文件：$ENTITLEMENTS"
    echo "   发生了什么：packaging/ 目录不完整。"
    echo "   下一步：确认这个文件在仓库里并已提交；缺了它，签出来的包在 Hardened Runtime 下用不了麦克风。"
    exit 1
fi

# 构建号默认取 git 提交数（单调递增）。
# IELTS_BUILD_NUMBER 存在时优先 —— verify-signature-stability.sh 靠它制造
# 「两次打包内容确实不同」的条件，否则那个比较是空转的。
if [[ -n "${IELTS_BUILD_NUMBER:-}" ]]; then
    BUILD_NUMBER="$IELTS_BUILD_NUMBER"
else
    BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
fi
BUILD_COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── 先跑测试，再打包 ────────────────────────────────────────────────
#
# **这一步以前没有。** 而这个脚本会「先删掉再拷贝」——打一次包就把每天在用的那份
# App 顶掉（见文件末尾的安装那一段）。改坏了也照样装上，要等到某天练到一半才发现。
#
# 还有一条更隐蔽的：「版本号必须和更新日志对得上」那道守卫
# （`PackagingContractTests`）只在跑测试时生效，而打包这一刻它本来是关着的。
#
# 留一个逃生口：某天一条不相干的红测试不该把人彻底挡在「拿不到任何新包」的门外。
# 用的时候屏幕上会明说这一次没验过。
if [ "${SKIP_TESTS:-0}" = "1" ]; then
    echo "⚠️  跳过了测试（SKIP_TESTS=1）。这次打出来的包没有经过验证。"
else
    echo "▶︎ 跑测试…（两千多条，二十秒出头；急着出包可以用 SKIP_TESTS=1 跳过）"
    if ! swift test; then
        echo ""
        echo "❌ 测试没过，**不打包**。"
        echo "   现在装着的那份 App 一个字节都没动，你可以照常用它。"
        echo "   下一步：把上面第一条红色的失败修掉再跑一次；"
        echo "   确实要带着这条失败出包的话：SKIP_TESTS=1 ./scripts/build-app.sh"
        exit 1
    fi
fi

echo "▶︎ 编译…"
swift build -c release --product IELTSCoachApp

echo "▶︎ 组装 .app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/release/IELTSCoachApp" "$APP/Contents/MacOS/IELTSCoachApp"

echo "▶︎ 生成图标…"
"$ROOT/scripts/make-icon.sh"
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# LICENSE 必须跟着 .app 走。
# 工程里有逐字沿用自上游 lindsey-labs/ielts-speaking-coach 的文本
# （AnswerUpgradePolicy 的规则正文、ExaminerPrompt 的英文契约句），上游是 MIT。
# MIT 的条件是把版权声明与 permission notice 的原文随副本一起交付——
# 交出去的是这个 .app，里面没有源码树，所以那份原文得在包里。
# 关于页也显示同一份（AboutViewModel.licenseNotice），但那要用户去点菜单才看得到，
# 而且关于页是 Task 7 才接上的；这里放一份文件，合规就不依赖任何一处 UI。
if [[ ! -f "$ROOT/LICENSE" ]]; then
    echo "❌ 仓库根目录找不到 LICENSE。"
    echo "   发生了什么：打不出合规的包——LICENSE 末尾的「第三方声明」里有上游 MIT 的原文，"
    echo "   MIT 要求它随每一份副本一起交付，缺了它这个 .app 就不该发给别人。"
    echo "   下一步：确认 LICENSE 还在仓库里并已提交，然后重打。"
    exit 1
fi
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"

# 注意：没有 NSAccessibilityUsageDescription 这种键，系统不读它。
# 辅助功能是 TCC 里由用户手动勾选的，弹的是系统固定文案，不是 App 能自定义的。
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
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 IELTS Speaking Coach 作者。与 OpenAI、British Council、IDP、Cambridge Assessment English 均无隶属关系。</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>开启「保存我的回答录音」后，用于录下你练习时的回答，便于回听。录音只存在本机，可随时删除。</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>com.ielts.speakingcoach.deeplink</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>CFBundleURLSchemes</key>
            <array><string>ieltscoach</string></array>
        </dict>
    </array>
    <key>IELTSBuildCommit</key><string>$BUILD_COMMIT</string>
    <key>IELTSBuildDate</key><string>$BUILD_DATE</string>
    <key>IELTSSigningIdentity</key><string>$SIGN_IDENTITY</string>
    <key>IELTSSignatureChannel</key><string>$SIGNATURE_CHANNEL</string>
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

# 光校验 plist 合法没用：少了 CFBundleURLTypes，plist 依然合法，
# 而 open_dashboard 会静默失效——NSWorkspace.open 返回 false，系统一句话都不说。
registered_scheme="$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw \
    "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ "$registered_scheme" != "ieltscoach" ]; then
    echo "❌ Info.plist 里没有正确注册 ieltscoach:// 这个 URL scheme（读到的是「${registered_scheme}」）。"
    echo "   下一步：检查 build-app.sh 里 CFBundleURLTypes 那一段是否完整。"
    echo "   不修的话，MCP 的 open_dashboard 会永远打不开窗口，而且不报错。"
    exit 1
fi
echo "✓ 已注册 URL scheme：$registered_scheme://"

# NSMicrophoneUsageDescription 一旦丢了，App 在第一次申请麦克风权限时会直接崩溃，
# 而崩溃报告里看不出跟这个键有任何关系。上面那段 heredoc 很容易在后续改动里被误伤，
# 所以这里当场验一次。
MIC_USAGE="$(plutil -extract NSMicrophoneUsageDescription raw "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ -z "$MIC_USAGE" ]; then
    echo "❌ Info.plist 里缺少 NSMicrophoneUsageDescription，或者它的值是空的。"
    echo "   后果：App 一申请麦克风权限就会闪退，且崩溃信息看不出原因。"
    echo "   下一步：在 build-app.sh 的 Info.plist heredoc 里补回这个键，"
    echo "   内容要用中文说明「录音用来做什么、存在哪里、能不能删」。"
    exit 1
fi
echo "✓ 麦克风用途说明：$MIC_USAGE"

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

# 不加 --deep：Apple 已不建议，且本包里没有嵌套代码，加了只会掩盖问题。
# --timestamp=none：本地打包不联网。公证路径由 notarize.sh 用 --timestamp 重签。
codesign --force \
         --sign "$SIGN_IDENTITY" \
         --identifier "$BUNDLE_ID" \
         --options runtime \
         --entitlements "$ENTITLEMENTS" \
         --timestamp=none \
         "$APP"

echo "▶︎ 自检…"

# 下面三段一律「先把输出收进变量，再在变量上匹配」，不用 `codesign … | grep -q`：
# grep -q 命中即退出会给 codesign 一个 SIGPIPE，配合本脚本开头的 pipefail，
# 通过的用例反而会被判成失败——那是最难查的一类假红。

VERIFY_OUT="$(codesign --verify --strict --verbose=2 "$APP" 2>&1 || true)"
case "$VERIFY_OUT" in
    *"satisfies its Designated Requirement"*)
        ;;
    *)
        echo "❌ 签名校验没通过。"
        echo "   实际读到：$VERIFY_OUT"
        echo "   下一步：跑 codesign --verify --strict --verbose=4 \"$APP\" 看具体是哪一项不满足。"
        exit 1
        ;;
esac

SIG_INFO="$(codesign -dvvv "$APP" 2>&1 || true)"
if ! grep -qE 'flags=0x[0-9a-f]+\(.*runtime' <<< "$SIG_INFO"; then
    echo "❌ 签出来的包没有 Hardened Runtime 标志。"
    echo "   发生了什么：codesign 的 --options runtime 没生效，将来送公证会被直接退回。"
    echo "   下一步：确认上面那条 codesign 命令里的 --options runtime 还在，然后重打。"
    exit 1
fi

SIGNED_ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
case "$SIGNED_ENTITLEMENTS" in
    *"com.apple.security.device.audio-input"*)
        ;;
    *)
        echo "❌ 签名里没带上麦克风 entitlement。"
        echo "   发生了什么：Hardened Runtime 打开后，没有这条 entitlement 的 App 一碰麦克风就会被系统直接拒掉，"
        echo "   用户开「保存我的回答录音」时会失败，而且失败得很难看懂。"
        echo "   下一步：检查 $ENTITLEMENTS 的内容，以及签名命令里的 --entitlements 参数。"
        exit 1
        ;;
esac

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

# 形状对了还不够：形状里那串 leaf 哈希换了一张证书照样对。
# 所以再跟仓库里记录的基线逐字比一次。
#
# 顺序是刻意的：**先验形状、再对基线**。反过来的话，万一哪天签名悄悄退化成 ad-hoc，
# 首次运行会把那条 cdhash 要求当成基线写进仓库，从此这道闸门永远绿灯。
if [[ ! -f "$BASELINE" ]]; then
    printf '%s\n' "$DESIGNATED" > "$BASELINE"
    echo "ℹ️  首次记录签名基线到 $BASELINE"
    echo "   下一步：把这个文件提交进仓库。以后每次打包都会跟它逐字比对，"
    echo "   一旦变了就说明辅助功能授权会失效，脚本会当场拦下来。"
elif [[ "$DESIGNATED" != "$(cat "$BASELINE")" ]]; then
    echo "❌ 签名的「指定要求」和仓库里记录的基线不一致。"
    echo "   基线：$(cat "$BASELINE")"
    echo "   本次：$DESIGNATED"
    echo "   发生了什么：系统会把这次打出来的 App 当成另一个程序，"
    echo "   之前授予的辅助功能权限会失效，用户得回系统设置重新勾一次。"
    echo "   下一步（二选一）："
    echo "     A. 你不是故意换证书：确认 login 钥匙串里的「${SIGN_IDENTITY}」证书还在、没被重新生成，修好后重打。"
    echo "     B. 你是故意换证书（例如换成 Developer ID 准备公证）：把新值写进"
    echo "        $BASELINE 并提交，然后到 系统设置 › 隐私与安全性 › 辅助功能 里"
    echo "        删掉旧条目、重新勾选一次。"
    exit 1
fi

echo "✅ 已生成 $APP"
echo "   版本 ${APP_VERSION}（构建 ${BUILD_NUMBER}，提交 ${BUILD_COMMIT}，通道 ${SIGNATURE_CHANNEL}）"
echo "   $DESIGNATED"

# ---------------------------------------------------------------------------
# 装到 ~/Applications
#
# **`.build/` 是构建产物目录，不是能住人的地方。** 2026-08-08 实测：
# 用户重启一次之后就找不到这个应用了——Spotlight 搜不到、Finder 也进不去。
# 三个原因叠在一起：
#   1. 目录名以点开头，Finder 默认隐藏，「系统设置 › 辅助功能」里点「+」浏览不到它
#   2. 构建目录不进 Spotlight 索引，所以搜「IELTS」什么都搜不出来
#   3. `rm -rf .build` 就没了——开发过程中这条命令跑过好几次
#
# 装到 ~/Applications（不是 /Applications：那里要管理员密码，而这是个人自用工具）。
# **辅助功能授权不会因为换位置而失效**：TCC 记的是签名的「指定要求」
# （identifier + 证书 leaf），不是路径——这一点上面那道闸门每次打包都在验。
INSTALLED="$HOME/Applications/$APP_NAME.app"
mkdir -p "$HOME/Applications"

# **正在运行的那个实例先说清楚。**
#
# 这个脚本存在的全部理由是「让你拿到新包去测」。而 2026-08-08 到 09 之间
# 已经因为「跑的是旧包」白测过两轮：改完提示词没重新打包一次，
# 重新打包了但用户点的是 Dock 里那个还亮着的旧进程一次。
#
# macOS 允许删掉正在运行的 .app（进程握着已经 unlink 的 inode 继续跑），
# 所以下面那个 rm -rf 不会失败、也不会有任何征兆——用户切回 Dock，
# 看到的是老界面、老行为，然后来报「没变呀」。
#
# 不自动杀进程：那是他正开着的窗口，可能正练到一半。只说清楚。
if pgrep -f "$INSTALLED/Contents/MacOS/" >/dev/null 2>&1; then
    echo "⚠️  「${APP_NAME}」正开着，而这次会把它整个替换掉。"
    echo "    Dock 里那个图标还是旧进程，点它打开的是**旧代码**——"
    echo "    本项目已经因为这件事白测过两轮。"
    echo "    下一步：先 ⌘Q 退出它，再重新打开（Spotlight 搜「IELTS」）。"
fi

# 先删后拷，不用 cp -R 覆盖：覆盖会把上一版残留的文件留在包里
# （比如某个版本有、下个版本删掉的资源），签名当场作废。
rm -rf "$INSTALLED"
if ! cp -R "$APP" "$INSTALLED"; then
    # **这里必须 exit 1。**
    #
    # 从前是 exit 0：脚本打印一行 ⚠️ 然后宣告成功。而文档与日常用的命令是
    #     ./scripts/build-app.sh && open ~/Applications/"IELTS Speaking Coach.app"
    # `&&` 看到 0 就往下走，`open` 打开的是上一版残留（或者因为上面那句
    # rm -rf 已经执行、压根打不开）。同一个脚本里「拷完签名坏了」走的是 exit 1，
    # 两条失败路径对调用方的含义完全一样：这一份没装上。
    echo "❌ 拷到 ~/Applications 失败。"
    echo "   .build 里那一份是好的、也已经签好名，只是没装到 ~/Applications。"
    echo "   下一步：直接从 .build 打开（open \"$APP\"），"
    echo "   或手动把它拖进「访达 › 前往 › 个人 › Applications」。"
    exit 1
fi

# 拷完再验一次签名：cp -R 在极少数情况下会破坏扩展属性，
# 而破坏了的包打开时只会报一句含糊的「已损坏」，查起来很费劲。
if ! codesign --verify --strict "$INSTALLED" 2>/dev/null; then
    echo "❌ 拷到 ~/Applications 之后签名坏了。"
    echo "   下一步：从 .build 那一份打开（open \"$APP\"），并把这条报错告诉开发者。"
    exit 1
fi

echo "✅ 已装到 $INSTALLED"
echo "   现在可以用 Spotlight（⌘空格）搜「IELTS」打开它，"
echo "   「系统设置 › 隐私与安全性 › 辅助功能」里点「+」也能浏览到这个位置。"
