# Phase 10：打包与分发

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付一个**能给别人**的 `.app`：有关于页（版本、数据目录、许可、致谢）、有首次使用引导、开了 Hardened Runtime 并带定稿的 entitlements、有一套「将来要公证时照着跑就行」的脚本（**本期不购买 Developer ID，不实际执行公证**）。同时把两件事从「应该没问题」变成「每次都自动验」：

1. **签名的「指定要求」跨打包稳定**——加了 Hardened Runtime 与 entitlements 之后仍然一模一样。它一变，用户的辅助功能授权当场失效，得回系统设置重新勾。这是这个产品最恼人的失败模式，因为它不报错、不崩溃，只是「今天怎么又不能自动开练了」。
2. **数据目录整个拷到另一台电脑就能接着用**（成品标准第 10 条）。

**Architecture:** 保持 SPM 单一构建系统，不引入 `.xcodeproj`。打包仍由 `scripts/build-app.sh` 组装 `.app` 并签名；本阶段把它从「能签出来」升级成「签完立刻自检四件事，任何一件不对就退出非零」。关于页与首次引导是纯 SwiftUI，逻辑（版本解析、诊断文本、引导步骤计算）全部拆成可单元测试的值类型放 `IELTSCoachUI`，与设备无关的「数据可搬迁审计」放 `IELTSCoachCore`。公证与分发是四个 shell 脚本，由一个不依赖任何产品代码的测试 target `PackagingTests` 守住契约。

**Tech Stack:** Swift 6.3.3、SPM、SwiftUI、XCTest、`codesign`、`ditto`、`xcrun notarytool`（仅预留，不执行）。无第三方依赖，且本阶段新增一条测试守住「无第三方依赖」这个事实。

---

## Global Constraints

- 最低系统版本 `macOS 14.0`
- **Bundle ID 固定为 `com.ielts.speakingcoach`，任何阶段都不得更改**——辅助功能授权绑定它
- `IELTSCoachCore` **只允许依赖 Foundation**。需要 AppKit / AVFoundation / PDFKit 的代码放 UI 层或单独 target
- `IELTSCoachUI` 可依赖 Core、ChatGPTBridge、`IELTSCoachAudio`（Phase 5 加的）、`IELTSCoachMCP` 不参与界面、SwiftUI
- 所有面向用户的文案必须是中文，且同时说明「**发生了什么**」和「**下一步做什么**」。这条对关于页、引导页、脚本输出一视同仁
- **禁止静默失败，禁止无限等待**
- 目标 ChatGPT 应用固定 `com.openai.codex`
- 界面必须走设计令牌（`Palette` / `Spacing` / `Radius`），视图里不得出现字面颜色、字号、圆角。唯一视觉依据是 `docs/superpowers/DESIGN-SYSTEM.md`
- 涉及外部应用能力的判断，一律以**在运行中的应用上实测**为准
- 测试用 XCTest

---

## 本阶段明确不做的事

写下来防止范围扩大，也防止实现者「顺手多做一点」：

| 不做 | 为什么 |
|---|---|
| **不重做 App 图标** | Phase 3 Task 1 已经做掉（`scripts/make-icon.swift` + `make-icon.sh`）。本阶段只是继续调用它，一行都不改 |
| **不购买 Developer ID、不实际公证** | 设计文档第 10 节已定。本阶段只把架构和脚本预留好 |
| **不做 `.dmg`** | `.zip` 已经能把 `.app` 完整交给别人且不破坏签名（`ditto` 保留扩展属性）。`.dmg` 只是更好看，不解决任何实际问题 |
| **不做自动更新（Sparkle 之类）** | 需要引入第三方依赖 + 一个能长期挂着的更新服务器。这是个自用工具，换版本就是重新拷一个 `.app` |
| **不改 `state.json` 的 schema** | `schemaVersion: 3` 与上游/Windows 版兼容（设计文档 4.6）。本阶段新增的「是否看过引导」是**本机**状态，不进数据目录，理由见 Task 8 |
| **不新增侧边栏条目** | 侧边栏固定十项，Phase 3 有一条 `testSidebarHasAllTenItems` 守着，那条测试是对的。**关于页放在苹果菜单里**（`⌘` 菜单的「关于 …」），这是 Mac 应用的标准位置，不占侧边栏 |
| **不开 App Sandbox** | 沙盒会切断「用辅助功能驱动别的应用」和「读用户随手挑的题库文件」，产品直接不可用。公证**不要求**沙盒，只有 Mac App Store 要求。详见 Task 1 |

---

## 前置依赖（本阶段消费什么，由谁产出）

**如果下面任何一条不成立，先停下来报告，不要假装它存在。**

| 依赖 | 来自 | 本阶段怎么用 |
|---|---|---|
| `Palette` / `Spacing` / `Radius`；`CoachCard` / `PrimaryActionCard` / `SectionHeader` / `EmptyStateView` | Phase 3 Task 7 | 关于页与引导页全部用它们搭，不自己写样式 |
| `enum PermissionState { case ready, needsAccessibility, needsChatGPT, unknown }`、`PermissionStatus.evaluate(readiness:) -> PermissionState`、`PermissionStatus.systemSettingsURL` | Phase 3 Task 2 | 引导的「环境」步骤与关于页的权限行 |
| `PermissionGateView(state:messages:onRecheck:onSkip:)` | Phase 3 Task 2 | **复用**为引导「环境」步骤的内容，不另写一套说同一件事的文案 |
| `@Observable final class AppState`（`state: CoachState`、`permission: PermissionState`、`permissionMessages: [String]`、`reload()`、`recheckPermission()`） | Phase 3 Task 3 | `RootView` 决定要不要显示引导 |
| `RootView` | Phase 3 Task 3 | 本阶段改它的顶层分支：把「权限没给就挡一下」换成完整的首次引导 |
| `scripts/build-app.sh`、`scripts/make-icon.sh` | Phase 3 Task 1 | 前者本阶段重写，后者原样调用 |
| 自签名证书 `IELTS Coach Dev` 在 login 钥匙串里 | Phase 3 前置条件 | 签名身份。**没有它整个阶段无法开工** |
| `CoachSettings.recordingEnabled` / `recordingConsentAt` | 已在 Core 里（`Sources/IELTSCoachCore/Model/CoachState.swift`） | 引导的「录音开关」步骤写它 |
| `PracticeSession.reportPath` / `recordingPath` 里存的是**相对于数据目录**的路径 | Phase 3 / 4 / 5 的写入代码 | Task 4 的审计就是来验证这个约定有没有被破坏的。**若审计一上来就报一堆问题，说明约定已经被破坏了，那是真 bug，不是审计写错了** |
| `ieltscoach://` 的处理（`onOpenURL`）与 `Info.plist` 里的 `CFBundleURLTypes` | Phase 9 Task 11 | **Phase 9 已经把两半都做了**，`build-app.sh` 里已经有 `CFBundleURLTypes` 那一段和一条校验。本阶段重写 `build-app.sh` 时**必须把它们一起搬过去**（Task 1 Step 2 的 Info.plist 与自检里已经带上了）。若 Phase 9 未完成，注册后点链接会打开 App 但不跳转——已知且可接受 |
| `NSMicrophoneUsageDescription` 的存在性校验 | Phase 5 Task 10 | 同上，本阶段重写脚本时不得丢掉这条校验。丢了不会报错，只会在真机上变成「一开录音就闪退、崩溃报告看不出原因」 |

---

## 前置事实（2026-08-06 在本机实测，不是推断）

这几条决定了本阶段的做法，实测命令与输出都在下面，实现者可以自己复现。

| 事实 | 怎么测的 | 结论 |
|---|---|---|
| **加 Hardened Runtime + entitlements 不改变「指定要求」** | 把已有的 `.app` 复制两份，各自用 `codesign --force --options runtime --entitlements … --sign "IELTS Coach Dev" --identifier com.ielts.speakingcoach` 重签 | 两份的 designated 都仍是 `identifier "com.ielts.speakingcoach" and certificate leaf = H"4bffcd37377a383d9d75460f2c2c9d85174fc82a"`，与加 Hardened Runtime **之前**完全一致 |
| **改了 `Info.plist` 内容，CDHash 确实会变** | 其中一份先 `PlistBuddy -c "Set :CFBundleVersion 999"` 再签 | 两份 CDHash 不同（`5e202846…` / `ee17b4ca…`）。**这条是「两次打包比较不是空转」的依据**——不制造差异的话，两次打出同一个包，比较当然一致 |
| Hardened Runtime 标志确实打上了 | `codesign -dvvv` | `flags=0x10000(runtime)`、`Runtime Version=26.5.0` |
| 签名在 Hardened Runtime 下仍然有效 | `codesign --verify --strict --verbose=2` | `valid on disk` + `satisfies its Designated Requirement` |
| **可执行文件只链接系统库** | `otool -L .build/IELTS Speaking Coach.app/Contents/MacOS/IELTSCoachApp` | 全部是 `/usr/lib/*`、`/System/Library/Frameworks/*`、`/usr/lib/swift/*`。**因此不需要 `disable-library-validation`**，Hardened Runtime 默认的库校验不会拦任何东西 |
| **自签名的包会被 Gatekeeper 拒** | `spctl -a -vvv -t exec` | `rejected`、`origin=IELTS Coach Dev`。这是没公证的必然结果，关于页与「如何打开」说明必须如实告诉用户 |
| `notarytool` / `stapler` 本机已有 | `xcrun --find notarytool` / `xcrun --find stapler` | 都在 Xcode 里。**将来缺的只是证书与凭据，不是工具** |

另有两条**不要浪费时间去找**的东西：

- **辅助功能没有对应的 `Info.plist` 用途说明键。** 不存在 `NSAccessibilityUsageDescription` 这种东西，系统不读它，写了也没用。辅助功能是 TCC 里由用户手动勾选的，弹的是系统固定文案的对话框。
- **AX 驱动别的应用不需要任何 entitlement。** 它由 TCC（辅助功能）管，不由 Hardened Runtime 管。**唯一**需要因 Hardened Runtime 而补的 entitlement 是麦克风（`com.apple.security.device.audio-input`）。

---

## File Structure

```
LICENSE                                        新增
packaging/                                     新增目录，必须提交进仓库
├── IELTSCoach.entitlements                    entitlements 定稿
├── expected-designated-requirement.txt         签名基线（打包时逐字比对）
└── open-instructions.txt                       随分发包附上的中文「如何打开」
scripts/
├── build-app.sh                               Modify：Hardened Runtime + entitlements + Info.plist 定稿 + 四项自检
├── make-icon.sh / make-icon.swift              不动（Phase 3 已完成）
├── verify-signature-stability.sh              新增：连打两次，比对 designated
├── package-app.sh                             新增：产出可以直接发给别人的 zip
├── notarize.sh                                新增：公证脚本，默认 dry-run，本期不执行
└── verify-portability.sh                      新增：模拟「换了一台电脑」
Sources/
├── IELTSCoachCore/Storage/
│   └── DataPortabilityAudit.swift             新增：数据目录可搬迁审计（纯 Foundation）
├── IELTSCoachUI/About/
│   ├── AppMetadata.swift                      新增：版本、构建、签名通道
│   ├── DiagnosticsReport.swift                新增：可复制的诊断文本（不含练习内容）
│   ├── AboutViewModel.swift                   新增：关于页的行、致谢、许可
│   └── AboutView.swift                        新增：关于页（独立窗口）
├── IELTSCoachUI/Onboarding/
│   ├── OnboardingFlow.swift                   新增：引导步骤计算（纯逻辑）
│   ├── OnboardingProgressStore.swift          新增：「看过引导没有」存本机 UserDefaults
│   └── WelcomeFlowView.swift                  新增：引导界面
├── IELTSCoachUI/RootView.swift                Modify：顶层分支改走引导
├── IELTSCoachApp/main.swift                   Modify：关于窗口 + 苹果菜单
└── coach/
    ├── PortabilityCommand.swift               新增：coach portability
    └── main.swift                             Modify：注册新子命令
Tests/
├── IELTSCoachCoreTests/DataPortabilityAuditTests.swift    新增
├── IELTSCoachUITests/AppMetadataTests.swift               新增
├── IELTSCoachUITests/DiagnosticsReportTests.swift         新增
├── IELTSCoachUITests/AboutViewModelTests.swift            新增
├── IELTSCoachUITests/OnboardingFlowTests.swift            新增
└── PackagingTests/                                        新增 test target（不依赖任何产品代码）
    ├── NotarizeScriptTests.swift
    └── PackagingContractTests.swift
Package.swift                                  Modify：加 PackagingTests
```

### 关于本计划里 View 的写法

**视图模型给完整代码，`View` 只给验收要求不给布局代码——这是刻意的，不是省略。** 理由与 Phase 3 计划第 79–86 行完全相同：布局是需要看着调的东西，把一份没人看过的 SwiftUI 布局逐字写进计划，实现者照抄之后大概率还要推翻重来。所以每个 `View` 的任务里写明「必须显示什么、空状态说什么、失败时说什么」，具体怎么摆由实现者定，由设计令牌与 Task 11 的人工验收把关。

**唯一例外是 `Sources/IELTSCoachApp/main.swift`**：它不是布局，是 Scene 与菜单的结构，摆错了关于页根本打不开。所以那一段给完整代码。

若实现者认为某处要求不清楚到无法动手，**应当停下来问，而不是猜**。

---

## Task 1: entitlements 与 Info.plist 定稿，打开 Hardened Runtime

**Files:**
- Create: `packaging/IELTSCoach.entitlements`
- Modify: `scripts/build-app.sh`

**Interfaces:**
- Consumes: `scripts/make-icon.sh`（Phase 3 产出，原样调用）；钥匙串里的证书 `IELTS Coach Dev`
- Produces:
  - 已签名的 `.build/IELTS Speaking Coach.app`，带 `flags=0x10000(runtime)` 与麦克风 entitlement
  - `Info.plist` 里四个供关于页读取的自定义键：`IELTSBuildCommit`、`IELTSBuildDate`、`IELTSSigningIdentity`、`IELTSSignatureChannel`
  - `build-app.sh` 支持两个环境变量：`IELTS_BUILD_NUMBER`（覆盖构建号）、`IELTS_SIGN_IDENTITY` / `IELTS_SIGNATURE_CHANNEL`（供 `notarize.sh` 用 Developer ID 重签时复用同一套组装逻辑）

### entitlements 为什么只有一条

**只加需要的，一条都不多加。** 每多一条 entitlement 就多削弱一分 Hardened Runtime，而 Hardened Runtime 是公证的硬性前提。逐条说明为什么其余的都不加：

| entitlement | 加不加 | 理由 |
|---|---|---|
| `com.apple.security.device.audio-input` | **加** | Phase 5 的麦克风录音。Hardened Runtime 打开后，没有这条的 App 一碰麦克风就被系统直接拒掉，用户打开「保存我的回答录音」时会失败，而且失败得很难看懂 |
| `com.apple.security.app-sandbox` | **不加** | 沙盒会切断辅助功能驱动别的应用、也切断读用户随手挑的题库文件。产品直接不可用。**公证不要求沙盒**，只有 Mac App Store 要求 |
| `com.apple.security.cs.disable-library-validation` | **不加** | 实测 `otool -L` 显示可执行文件只链接 `/usr/lib`、`/System/Library/Frameworks`、`/usr/lib/swift`，全是系统签名的库，库校验不会拦任何东西。加了等于白白削弱。**遇到 Hardened Runtime 报错时最容易被顺手粘上来的就是这一条，Task 9 有测试专门拦它** |
| `com.apple.security.cs.allow-jit`、`allow-unsigned-executable-memory`、`disable-executable-page-protection` | **不加** | SwiftUI 应用不 JIT、不生成可执行内存 |
| `com.apple.security.automation.apple-events` | **不加** | 本项目实测排除了 AppleScript 通道（设计文档 2.2：新目标的 AppleScript 字典是继承来的空壳），全部走 AX API，而 AX 不经 Apple Events。**将来若真要发 Apple Event，必须同时加这条 entitlement 与 `NSAppleEventsUsageDescription`，缺一个都会在 Hardened Runtime 下被拒** |

- [ ] **Step 1: 写 entitlements 文件**

`packaging/IELTSCoach.entitlements`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!--
      唯一一条 entitlement：麦克风。
      Hardened Runtime 打开后，没有它 App 一碰麦克风就会被系统直接拒掉
      （Phase 5 的「保存我的回答录音」开关会失败，且失败信息很难看懂）。

      为什么没有别的：
      · 不开 App Sandbox —— 沙盒会切断辅助功能驱动 ChatGPT、也切断读任意题库文件，
        产品直接不可用。公证不要求沙盒，只有 Mac App Store 要求。
      · 不加 disable-library-validation —— 实测 otool -L 显示只链接系统库，
        库校验不会拦任何东西，加了只是白白削弱。
      · 不加 apple-events —— 本项目全部走 AX API，不发 Apple Event（设计文档 2.2）。
      · 辅助功能不需要任何 entitlement，它由 TCC 管，不由 Hardened Runtime 管。
    -->
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

Run: `plutil -lint packaging/IELTSCoach.entitlements`
Expected: `packaging/IELTSCoach.entitlements: OK`

- [ ] **Step 2: 重写 `scripts/build-app.sh`**

完整替换原文件：

```bash
#!/bin/bash
set -euo pipefail

# 组装 .app 包并签名。
#
# 为什么必须用固定的签名身份而不是 ad-hoc（codesign -s -）：
# TCC（辅助功能授权）记的是签名的「指定要求」。ad-hoc 绑的是二进制指纹 cdhash，
# 每次编译都变，用户得反复去系统设置重新勾选。固定证书绑「标识 + 证书」，
# 编译多少次都不变。
#
# 组装完先自检两件事（Phase 5 Task 10 / Phase 9 Task 11 留下来的，重写脚本时勿丢）：
#   · Info.plist 里有 NSMicrophoneUsageDescription
#   · Info.plist 里有 CFBundleURLTypes 且 scheme 是 ieltscoach
#
# 签完之后立刻自检四件事，任何一件不对都直接退出非零：
#   1. 签名本身有效（codesign --verify --strict）
#   2. 带了 Hardened Runtime 标志
#   3. 带了麦克风 entitlement（没有它，Hardened Runtime 下录音会被系统拒掉）
#   4. 「指定要求」与 packaging/expected-designated-requirement.txt 逐字一致
# 第 4 条是本产品最恼人失败模式的守门员：它一变，用户的辅助功能授权就没了，
# 而且不会有任何报错，只是「今天怎么又不能自动开练了」。

APP_NAME="IELTS Speaking Coach"
BUNDLE_ID="com.ielts.speakingcoach"
APP_VERSION="1.0.0"

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

echo "▶︎ 编译…"
swift build -c release --product IELTSCoachApp

echo "▶︎ 组装 .app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/release/IELTSCoachApp" "$APP/Contents/MacOS/IELTSCoachApp"

echo "▶︎ 生成图标…"
"$ROOT/scripts/make-icon.sh"
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

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
            <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
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

# ↓ 这两条来自 Phase 5 Task 10 与 Phase 9 Task 11。本任务整体重写了这个脚本，
#   一不小心就会把它们丢掉——而 plutil -lint 只管 plist 合不合法，管不了某个键在不在。
#   丢了不会有任何报错，只会在真机上变成两种极难排查的症状。

# 缺 NSMicrophoneUsageDescription：App 第一次申请麦克风权限时直接闪退，
# 崩溃报告里看不出跟这个键有任何关系。
MIC_USAGE="$(plutil -extract NSMicrophoneUsageDescription raw "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ -z "$MIC_USAGE" ]; then
    echo "❌ Info.plist 里缺少 NSMicrophoneUsageDescription。"
    echo "   后果：App 一申请麦克风权限就会闪退，且崩溃信息看不出原因。"
    echo "   下一步：在上面那段 Info.plist heredoc 里补回这个键，"
    echo "   内容要用中文说明「录音用来做什么、存在哪里、能不能删」。"
    exit 1
fi

# 缺 CFBundleURLTypes：LaunchServices 不知道谁该处理 ieltscoach://，
# MCP 的 open_dashboard 会永远打不开窗口，而 NSWorkspace.open 只是返回 false，一句话都不说。
REGISTERED_SCHEME="$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw \
    "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ "$REGISTERED_SCHEME" != "ieltscoach" ]; then
    echo "❌ Info.plist 里没有正确注册 ieltscoach:// 这个 URL scheme（读到的是「$REGISTERED_SCHEME」）。"
    echo "   后果：MCP 的 open_dashboard 会永远打不开窗口，而且不报错。"
    echo "   下一步：检查上面 Info.plist heredoc 里 CFBundleURLTypes 那一段是否完整。"
    exit 1
fi

echo "▶︎ 签名（Hardened Runtime + entitlements）…"
if ! security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    echo "❌ 找不到签名证书「$SIGN_IDENTITY」。"
    echo "   下一步：按 docs/superpowers/plans/2026-08-05-phase3-gui-shell.md「前置条件」一节重新创建，"
    echo "   否则每次编译后辅助功能授权都会失效，需反复去系统设置重新勾选。"
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

if ! codesign --verify --strict --verbose=2 "$APP" 2>&1 | grep -q "satisfies its Designated Requirement"; then
    echo "❌ 签名校验没通过。"
    echo "   下一步：跑 codesign --verify --strict --verbose=4 \"$APP\" 看具体是哪一项不满足。"
    exit 1
fi

if ! codesign -dvvv "$APP" 2>&1 | grep -qE 'flags=0x[0-9a-f]+\(.*runtime'; then
    echo "❌ 签出来的包没有 Hardened Runtime 标志。"
    echo "   发生了什么：codesign 的 --options runtime 没生效。"
    echo "   下一步：确认上面那条 codesign 命令里的 --options runtime 还在，然后重打。"
    exit 1
fi

if ! codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "com.apple.security.device.audio-input"; then
    echo "❌ 签名里没带上麦克风 entitlement。"
    echo "   发生了什么：Hardened Runtime 打开后，没有这条 entitlement 的 App 一碰麦克风就会被系统直接拒掉，"
    echo "   用户开「保存我的回答录音」时会失败，而且失败得很难看懂。"
    echo "   下一步：检查 $ENTITLEMENTS 的内容，以及签名命令里的 --entitlements 参数。"
    exit 1
fi

ACTUAL_DR="$(codesign -d -r- "$APP" 2>&1 | grep '^designated' || true)"
if [[ -z "$ACTUAL_DR" ]]; then
    echo "❌ 读不出签名的「指定要求」。"
    echo "   下一步：跑 codesign -d -r- \"$APP\" 看它到底输出了什么。"
    exit 1
fi

if [[ ! -f "$BASELINE" ]]; then
    printf '%s\n' "$ACTUAL_DR" > "$BASELINE"
    echo "ℹ️  首次记录签名基线到 $BASELINE"
    echo "   下一步：把这个文件提交进仓库。以后每次打包都会跟它逐字比对，"
    echo "   一旦变了就说明辅助功能授权会失效，脚本会当场拦下来。"
elif [[ "$ACTUAL_DR" != "$(cat "$BASELINE")" ]]; then
    echo "❌ 签名的「指定要求」和仓库里记录的基线不一致。"
    echo "   基线：$(cat "$BASELINE")"
    echo "   本次：$ACTUAL_DR"
    echo "   发生了什么：系统会把这次打出来的 App 当成另一个程序，"
    echo "   之前授予的辅助功能权限会失效，用户得回系统设置重新勾一次。"
    echo "   下一步（二选一）："
    echo "     A. 你不是故意换证书：确认 login 钥匙串里的「$SIGN_IDENTITY」证书还在、没被重新生成，修好后重打。"
    echo "     B. 你是故意换证书（例如换成 Developer ID 准备公证）：把新值写进"
    echo "        $BASELINE 并提交，然后到 系统设置 › 隐私与安全性 › 辅助功能 里"
    echo "        删掉旧条目、重新勾选一次。"
    exit 1
fi

echo "✅ 已生成 $APP"
echo "   版本 $APP_VERSION（构建 $BUILD_NUMBER，提交 $BUILD_COMMIT，通道 $SIGNATURE_CHANNEL）"
echo "   $ACTUAL_DR"
```

- [ ] **Step 3: 打一次包，确认自检全过**

Run: `chmod +x scripts/build-app.sh && ./scripts/build-app.sh`
Expected: 走完组装期两项 + 签名后四项自检，最后打印 `✅ 已生成 …` 与
`designated => identifier "com.ielts.speakingcoach" and certificate leaf = H"…"`。
并且**首次运行会生成 `packaging/expected-designated-requirement.txt`**，内容就是那一行。

Run: `codesign -dvvv ".build/IELTS Speaking Coach.app" 2>&1 | grep -E "flags|Runtime Version"`
Expected: 含 `flags=0x10000(runtime)` 与 `Runtime Version=`

Run: `codesign -d --entitlements - --xml ".build/IELTS Speaking Coach.app" 2>/dev/null`
Expected: XML 里有 `com.apple.security.device.audio-input`

- [ ] **Step 4: 确认 App 在 Hardened Runtime 下真的还能驱动 ChatGPT**

Run: `open ".build/IELTS Speaking Coach.app"`
Expected: App 打开后显示「环境就绪」（即 `preflight()` 成功找到 ChatGPT、辅助功能权限有效、惰性 AX 树能唤醒）。

**这一步不产生任何 ChatGPT 对话**——`preflight()` 只做检查，不新建会话、不发消息、不启动语音。

若这里变成「没有辅助功能权限」：先看 Step 5 的判断，不要急着重新授权。

- [ ] **Step 5: 突变验证（改脚本，看自检会不会红）**

**突变 A —— 摘掉 Hardened Runtime：**
把 `codesign` 命令里的 `--options runtime \` 整行删掉，重跑 `./scripts/build-app.sh`。
Expected: 停在 `❌ 签出来的包没有 Hardened Runtime 标志。`，退出码非零。改回后重跑必须通过。

**突变 B —— 摘掉 entitlements：**
把 `--entitlements "$ENTITLEMENTS" \` 整行删掉，重跑。
Expected: 停在 `❌ 签名里没带上麦克风 entitlement。`，退出码非零。改回后重跑必须通过。

**把两次的实际输出写进报告。** 这两条守的是「自检不是摆设」——一个只会打印 ✅ 的自检等于没有自检，而这类空转在本项目已经消灭过 15 处。

- [ ] **Step 6: 提交**

```bash
git add packaging/IELTSCoach.entitlements packaging/expected-designated-requirement.txt scripts/build-app.sh
git commit -m "feat(packaging): Hardened Runtime、entitlements 与 Info.plist 定稿"
```

---

## Task 2: 签名稳定性回归脚本

**Files:**
- Create: `scripts/verify-signature-stability.sh`

**Interfaces:**
- Consumes: `scripts/build-app.sh`（认 `IELTS_BUILD_NUMBER`）、`packaging/expected-designated-requirement.txt`
- Produces: `scripts/verify-signature-stability.sh`，退出 0 表示「连打两次包，designated 完全一致，且与基线相符，且这次比较不是空转的」

**这是本阶段最要紧的一条。** macOS 的 TCC（辅助功能授权）记的就是「指定要求」这个字符串。它一变，系统把新包当成另一个程序，用户之前勾的权限当场失效。这个失败不报错、不崩溃，用户的感受只是「今天怎么又不能自动开练了」——所以必须由脚本每次替他检查。

**为什么两次要用不同的构建号：** 不制造差异的话，两次打出来的是同一个包，designated 当然一致，等于什么都没验。脚本因此额外断言「两次的 CDHash 必须不同」——这一条不成立时，比较本身是空转的，脚本要报错。

- [ ] **Step 1: 写脚本**

`scripts/verify-signature-stability.sh`：

```bash
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

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="IELTS Speaking Coach"
APP="$ROOT/.build/$APP_NAME.app"
BASELINE="$ROOT/packaging/expected-designated-requirement.txt"

read_designated() { codesign -d -r- "$APP" 2>&1 | grep '^designated' || true; }
read_cdhash()     { codesign -dvvv  "$APP" 2>&1 | grep '^CDHash=' | head -1 || true; }

echo "▶︎ 第一次打包（构建号 90001）…"
IELTS_BUILD_NUMBER=90001 "$ROOT/scripts/build-app.sh" >/dev/null
DR1="$(read_designated)"; HASH1="$(read_cdhash)"

echo "▶︎ 第二次打包（构建号 90002，内容与第一次确实不同）…"
IELTS_BUILD_NUMBER=90002 "$ROOT/scripts/build-app.sh" >/dev/null
DR2="$(read_designated)"; HASH2="$(read_cdhash)"

FAILED=0

if [[ -z "$DR1" || -z "$DR2" ]]; then
    echo "❌ 有一次没读出「指定要求」。"
    echo "   下一步：单独跑 codesign -d -r- \"$APP\" 看它输出了什么。"
    FAILED=1
fi

if [[ "$HASH1" == "$HASH2" ]]; then
    echo "❌ 两次打包的 CDHash 一模一样（$HASH1）。"
    echo "   发生了什么：两次打出来的是同一个包，这次比较什么都没验证到。"
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
    echo "   下一步：见 build-app.sh 里同名检查打印的两条处理办法（A 修证书 / B 更新基线并重新授权）。"
    FAILED=1
fi

if [[ $FAILED -ne 0 ]]; then exit 1; fi

echo "✅ 连打两次，「指定要求」完全一致，且与基线相符："
echo "   $DR2"
echo "   两次 CDHash 分别是 $HASH1 / $HASH2（不同，说明这次比较是有效的）"
```

- [ ] **Step 2: 跑一次，确认通过**

Run: `chmod +x scripts/verify-signature-stability.sh && ./scripts/verify-signature-stability.sh`
Expected: 打印 `✅ 连打两次，「指定要求」完全一致…`，退出 0。

- [ ] **Step 3: 突变验证（两条，都必须做）**

**突变 A —— 把签名换成 ad-hoc：**
把 `scripts/build-app.sh` 里的 `--sign "$SIGN_IDENTITY" \` 改成 `--sign - \`，重跑 `./scripts/verify-signature-stability.sh`。
Expected: designated 变成 `cdhash H"…"` 形式且两次互不相同，脚本停在 `❌ 两次打包的「指定要求」不一致`，退出非零。改回后重跑必须通过。

**这条守的就是本产品最恼人的失败模式**：ad-hoc 签名每次编译都变，用户每次都要回系统设置重新勾辅助功能。

**突变 B —— 让两次打包变成同一个包：**
把 `verify-signature-stability.sh` 里第二次的 `IELTS_BUILD_NUMBER=90002` 改成 `90001`，重跑。
Expected: 停在 `❌ 两次打包的 CDHash 一模一样`，退出非零。改回后重跑必须通过。

**这条守的是「比较本身不能是空转的」**——两次打出一模一样的包，designated 当然一致，那样的绿灯毫无意义。

把两次突变的实际输出写进报告。

- [ ] **Step 4: 提交**

```bash
git add scripts/verify-signature-stability.sh
git commit -m "feat(packaging): 签名指定要求的稳定性回归脚本"
```

---

## Task 3: 版本与签名通道（AppMetadata）

**Files:**
- Create: `Sources/IELTSCoachUI/About/AppMetadata.swift`
- Create: `Tests/IELTSCoachUITests/AppMetadataTests.swift`

**Interfaces:**
- Consumes: `Bundle.main.infoDictionary`（生产环境）；Task 1 写进 `Info.plist` 的 `IELTSBuildCommit` / `IELTSBuildDate` / `IELTSSigningIdentity` / `IELTSSignatureChannel`
- Produces:
  - `enum SignatureChannel: String, Equatable, Sendable, CaseIterable { case selfSigned = "self-signed", developerID = "developer-id", unknown }`
    - `SignatureChannel.from(_ raw: String?) -> SignatureChannel`
    - `var title: String` / `var explanation: String` / `var nextStep: String`
  - `struct AppMetadata: Equatable, Sendable`，字段 `displayName`、`bundleIdentifier`、`shortVersion`、`buildNumber`、`buildCommit`、`buildDate`、`signingIdentity`、`channel`
    - `static let unknownValue = "未知（开发运行）"`
    - `static func from(infoDictionary: [String: Any]?) -> AppMetadata`
    - `static var current: AppMetadata`
    - `var versionLine: String`

**为什么要单独拆一个类型：** `swift run IELTSCoachApp` 直接跑时**没有 App bundle**，`Bundle.main.infoDictionary` 里什么都没有。关于页在这种情况下必须仍然显示得像样，而不是一片空白或者 `Optional(nil)`。这段「缺什么就说缺什么」的逻辑是纯函数，可以完整测试；`View` 只负责摆。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/AppMetadataTests.swift`：

```swift
import XCTest
@testable import IELTSCoachUI

final class AppMetadataTests: XCTestCase {
    private func fullDictionary() -> [String: Any] {
        [
            "CFBundleDisplayName": "IELTS Speaking Coach",
            "CFBundleIdentifier": "com.ielts.speakingcoach",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "42",
            "IELTSBuildCommit": "a1b2c3d",
            "IELTSBuildDate": "2026-08-06T09:00:00Z",
            "IELTSSigningIdentity": "IELTS Coach Dev",
            "IELTSSignatureChannel": "self-signed"
        ]
    }

    func testReadsEveryFieldFromACompleteDictionary() {
        let metadata = AppMetadata.from(infoDictionary: fullDictionary())
        XCTAssertEqual(metadata.displayName, "IELTS Speaking Coach")
        XCTAssertEqual(metadata.bundleIdentifier, "com.ielts.speakingcoach")
        XCTAssertEqual(metadata.shortVersion, "1.0.0")
        XCTAssertEqual(metadata.buildNumber, "42")
        XCTAssertEqual(metadata.buildCommit, "a1b2c3d")
        XCTAssertEqual(metadata.buildDate, "2026-08-06T09:00:00Z")
        XCTAssertEqual(metadata.signingIdentity, "IELTS Coach Dev")
        XCTAssertEqual(metadata.channel, .selfSigned)
    }

    func testMissingDictionaryProducesReadableChineseInsteadOfBlanks() {
        // swift run 直接跑时没有 App bundle，infoDictionary 是 nil。
        // 关于页在这种情况下不能出现空白行、也不能露出 "nil" / "Optional"。
        let metadata = AppMetadata.from(infoDictionary: nil)
        for value in [metadata.displayName, metadata.bundleIdentifier, metadata.shortVersion,
                      metadata.buildNumber, metadata.buildCommit, metadata.buildDate,
                      metadata.signingIdentity] {
            XCTAssertFalse(value.isEmpty, "缺字段时不能返回空串")
            XCTAssertFalse(value.contains("nil"), "不能把 nil 直接显示给用户：\(value)")
            XCTAssertFalse(value.contains("Optional"), "不能把 Optional 直接显示给用户：\(value)")
        }
        XCTAssertEqual(metadata.channel, .unknown)
    }

    func testOnlyTheAbsentKeysFallBack() {
        var dictionary = fullDictionary()
        dictionary.removeValue(forKey: "IELTSBuildCommit")
        let metadata = AppMetadata.from(infoDictionary: dictionary)
        XCTAssertEqual(metadata.buildCommit, AppMetadata.unknownValue)
        XCTAssertEqual(metadata.shortVersion, "1.0.0", "别的字段不该被连坐")
    }

    func testEmptyStringCountsAsMissing() {
        // plist 里把值写成空串，跟没写是一回事：界面上都是空白一行。
        var dictionary = fullDictionary()
        dictionary["IELTSSigningIdentity"] = "   "
        let metadata = AppMetadata.from(infoDictionary: dictionary)
        XCTAssertEqual(metadata.signingIdentity, AppMetadata.unknownValue)
    }

    func testNonStringValuesAreStillDisplayable() {
        // plist 里 CFBundleVersion 被写成 <integer> 是常见事故，不能因此变成「未知」。
        var dictionary = fullDictionary()
        dictionary["CFBundleVersion"] = 99
        let metadata = AppMetadata.from(infoDictionary: dictionary)
        XCTAssertEqual(metadata.buildNumber, "99")
    }

    func testVersionLineCombinesVersionAndBuild() {
        let metadata = AppMetadata.from(infoDictionary: fullDictionary())
        XCTAssertEqual(metadata.versionLine, "1.0.0（构建 42）")
    }

    func testUnknownChannelWhenValueIsGarbage() {
        var dictionary = fullDictionary()
        dictionary["IELTSSignatureChannel"] = "随便写的"
        XCTAssertEqual(AppMetadata.from(infoDictionary: dictionary).channel, .unknown)
    }

    func testEverySignatureChannelExplainsItselfAndGivesANextStep() {
        // 三种通道对用户的含义完全不同（能不能直接双击打开）。
        // 少写一种，用户在别人的电脑上被 Gatekeeper 拦下时就没有任何线索。
        for channel in SignatureChannel.allCases {
            XCTAssertFalse(channel.title.isEmpty, "\(channel) 没有标题")
            XCTAssertFalse(channel.explanation.isEmpty, "\(channel) 没说发生了什么")
            XCTAssertFalse(channel.nextStep.isEmpty, "\(channel) 没说下一步做什么")
        }
    }

    func testSelfSignedTellsTheRecipientHowToGetPastGatekeeper() {
        // 实测：自签名未公证的包 spctl 判定为 rejected。
        // 对方双击打不开时必须能从这句话里知道怎么办。
        let nextStep = SignatureChannel.selfSigned.nextStep
        XCTAssertTrue(nextStep.contains("系统设置"), "没告诉用户去哪儿：\(nextStep)")
        XCTAssertTrue(nextStep.contains("仍要打开"), "没告诉用户点什么：\(nextStep)")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter AppMetadataTests`
Expected: 编译失败 —— `AppMetadata`、`SignatureChannel` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/About/AppMetadata.swift`：

```swift
import Foundation

/// 这份 App 是怎么签的，以及这对拿到它的人意味着什么。
/// 取值由 `scripts/build-app.sh` 写进 Info.plist 的 `IELTSSignatureChannel`。
public enum SignatureChannel: String, Equatable, Sendable, CaseIterable {
    case selfSigned = "self-signed"
    case developerID = "developer-id"
    case unknown

    public static func from(_ raw: String?) -> SignatureChannel {
        guard let raw, let channel = SignatureChannel(rawValue: raw) else { return .unknown }
        return channel
    }

    public var title: String {
        switch self {
        case .selfSigned: return "自签名（未经 Apple 公证）"
        case .developerID: return "Developer ID 签名，已通过 Apple 公证"
        case .unknown: return "无签名信息（从源码直接运行）"
        }
    }

    /// 发生了什么。
    public var explanation: String {
        switch self {
        case .selfSigned:
            return "这份 App 用作者本机生成的证书签名，没有购买 Apple 开发者账号做公证。"
                + "Apple 对所有未公证的 App 都会拦一下，这与它本身是否安全无关。"
        case .developerID:
            return "这份 App 用 Apple 签发的 Developer ID 证书签名，并且通过了 Apple 的公证。"
        case .unknown:
            return "现在跑的是从源码直接启动的开发版本，没有打包成 .app，因此读不到签名信息。"
        }
    }

    /// 下一步做什么。
    public var nextStep: String {
        switch self {
        case .selfSigned:
            return "拷给别人时，对方第一次打开会被系统拦下。"
                + "让他打开 系统设置 › 隐私与安全性，在「安全性」一节找到被阻止的这一条，点「仍要打开」，再确认一次。"
        case .developerID:
            return "对方双击即可打开，不会被系统拦下。"
        case .unknown:
            return "要得到可以拷给别人的版本，运行 scripts/package-app.sh。"
        }
    }
}

/// 关于页与诊断信息要显示的「这是哪一份 App」。
///
/// **为什么每个字段都要有兜底：** `swift run IELTSCoachApp` 直接跑时没有 App bundle，
/// `Bundle.main.infoDictionary` 是 nil。关于页这时不能变成一片空白 ——
/// 空白页会让用户以为程序坏了（DESIGN-SYSTEM.md 第 4 节的原则，对关于页同样成立）。
public struct AppMetadata: Equatable, Sendable {
    public static let unknownValue = "未知（开发运行）"

    public let displayName: String
    public let bundleIdentifier: String
    public let shortVersion: String
    public let buildNumber: String
    public let buildCommit: String
    public let buildDate: String
    public let signingIdentity: String
    public let channel: SignatureChannel

    public init(displayName: String, bundleIdentifier: String, shortVersion: String,
                buildNumber: String, buildCommit: String, buildDate: String,
                signingIdentity: String, channel: SignatureChannel) {
        self.displayName = displayName; self.bundleIdentifier = bundleIdentifier
        self.shortVersion = shortVersion; self.buildNumber = buildNumber
        self.buildCommit = buildCommit; self.buildDate = buildDate
        self.signingIdentity = signingIdentity; self.channel = channel
    }

    public static func from(infoDictionary: [String: Any]?) -> AppMetadata {
        func value(_ key: String) -> String {
            guard let raw = infoDictionary?[key] else { return unknownValue }
            // String(describing:) 兼顾 plist 里被写成 <integer> 的值（常见事故），
            // 也保证 String 原样返回。
            let text = String(describing: raw).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? unknownValue : text
        }
        return AppMetadata(
            displayName: value("CFBundleDisplayName"),
            bundleIdentifier: value("CFBundleIdentifier"),
            shortVersion: value("CFBundleShortVersionString"),
            buildNumber: value("CFBundleVersion"),
            buildCommit: value("IELTSBuildCommit"),
            buildDate: value("IELTSBuildDate"),
            signingIdentity: value("IELTSSigningIdentity"),
            channel: SignatureChannel.from(infoDictionary?["IELTSSignatureChannel"] as? String))
    }

    public static var current: AppMetadata { from(infoDictionary: Bundle.main.infoDictionary) }

    public var versionLine: String { "\(shortVersion)（构建 \(buildNumber)）" }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter AppMetadataTests`
Expected: PASS（9 个测试）

- [ ] **Step 5: 突变验证**

把 `from(infoDictionary:)` 里的
`return text.isEmpty ? unknownValue : text`
改成
`return text`
重跑：`testEmptyStringCountsAsMissing` 必须变红。改回后确认全绿，把两次输出写进报告。

**这条守的是「界面上出现一行只有标签、没有内容的空白」**——用户看到那种行不会觉得「这个字段没填」，只会觉得「这软件坏了」。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/About/AppMetadata.swift Tests/IELTSCoachUITests/AppMetadataTests.swift
git commit -m "feat(ui): 版本与签名通道信息"
```

---

## Task 4: 数据目录可搬迁审计 + `coach portability`

**Files:**
- Create: `Sources/IELTSCoachCore/Storage/DataPortabilityAudit.swift`
- Create: `Sources/coach/PortabilityCommand.swift`
- Modify: `Sources/coach/main.swift`
- Create: `Tests/IELTSCoachCoreTests/DataPortabilityAuditTests.swift`

**Interfaces:**
- Consumes: `CoachState`（`sessions: [PracticeSession]`、`questionSources: [QuestionSource]`）、`PracticeSession.reportPath` / `.recordingPath`、`QuestionSource.sourceUrl`、`DataDirectory`（`root`、`stateFile`、`reportsDirectory`、`recordingsDirectory`）、`StateStore.load()`
- Produces:
  - `struct PortabilityFinding: Equatable, Sendable, Identifiable`
    - `var id: String { location }`、`let location: String`、`let value: String`、`let problem: String`、`let nextStep: String`
    - `init(location:value:problem:nextStep:)`
    - `var message: String`
  - `enum DataPortabilityAudit`
    - `static func audit(state: CoachState) -> [PortabilityFinding]`
    - `static func audit(state: CoachState, directory: DataDirectory, fileManager: FileManager = .default) -> [PortabilityFinding]`
  - 命令行 `coach portability`

**这一条兑现成品标准第 10 条。** 数据目录能不能整个拷到另一台电脑接着用，取决于一件事：**里面存的路径是不是全都相对于数据目录本身**。`PracticeSession.reportPath` 的注释写着 `reports/<id>.json`，但没有任何东西在强制它——某个阶段顺手写成 `URL.path` 就会变成绝对路径，而那时**什么都不会报错**，只有换机器的那天才会发现历史复盘全打不开。这正是本项目最危险的那类失败：静默的、要到很久以后才暴露的。

**为什么放在 Core：** 它只依赖 Foundation（`FileManager` 属于 Foundation），可以在没有界面、没有 ChatGPT 的环境里完整测试；命令行与关于页共用同一份判断。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachCoreTests/DataPortabilityAuditTests.swift`：

```swift
import XCTest
@testable import IELTSCoachCore

final class DataPortabilityAuditTests: XCTestCase {
    private var directory: DataDirectory!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "portability-\(UUID().uuidString)")
        directory = DataDirectory(root: root)
        try directory.createIfNeeded()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
        directory = nil
    }

    // MARK: - 造数据

    private func session(_ id: String, report: String, recording: String = "") -> PracticeSession {
        PracticeSession(id: id, questionId: "q1", focusPart: .part1,
                        startedAt: "2026-08-06T00:00:00Z", endedAt: "2026-08-06T00:10:00Z",
                        goal: "", transcript: [], reportPath: report, recordingPath: recording)
    }

    private func state(_ sessions: [PracticeSession],
                       sources: [QuestionSource] = []) -> CoachState {
        var value = CoachState.empty()
        value.sessions = sessions
        value.questionSources = sources
        return value
    }

    private func writeFile(_ relativePath: String) throws {
        let url = directory.root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    // MARK: - 干净的数据目录

    func testRelativePathsWithExistingFilesProduceNoFindings() throws {
        try writeFile("reports/s1.json")
        try writeFile("recordings/s1.m4a")
        let value = state([session("s1", report: "reports/s1.json", recording: "recordings/s1.m4a")])
        XCTAssertTrue(DataPortabilityAudit.audit(state: value, directory: directory).isEmpty)
    }

    func testEmptyPathsAreNotFindings() throws {
        // 练习还没生成复盘、或者没开录音时，这两个字段本来就是空的。
        // 把它当成错误会让用户每次打开都看到一屏红字，最后学会忽略所有告警 ——
        // 那时真正的问题也一起被忽略了。
        let value = state([session("s1", report: "", recording: "")])
        XCTAssertTrue(DataPortabilityAudit.audit(state: value, directory: directory).isEmpty)
        XCTAssertTrue(DataPortabilityAudit.audit(state: value).isEmpty)
    }

    // MARK: - 不可搬迁的写法

    func testAbsoluteReportPathIsReportedWithItsExactLocation() {
        let value = state([
            session("s1", report: "reports/s1.json"),
            session("s2", report: "/Users/someone/Library/Application Support/IELTS Speaking Coach/reports/s2.json")
        ])
        let findings = DataPortabilityAudit.audit(state: value)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].location, "sessions[1].reportPath")
        XCTAssertTrue(findings[0].message.contains("下一步"), "每条问题都必须说下一步做什么")
    }

    func testTildePathIsReported() {
        let value = state([session("s1", report: "~/Documents/s1.json")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value).count, 1)
    }

    func testFileURLIsReported() {
        let value = state([session("s1", report: "file:///tmp/s1.json")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value).count, 1)
    }

    func testPathEscapingTheDataDirectoryIsReported() {
        let value = state([session("s1", report: "../elsewhere/s1.json")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value).count, 1)
    }

    func testAbsoluteRecordingPathIsReported() {
        let value = state([session("s1", report: "reports/s1.json",
                                   recording: "/Users/someone/Music/s1.m4a")])
        let findings = DataPortabilityAudit.audit(state: value)
        XCTAssertEqual(findings.map(\.location), ["sessions[0].recordingPath"])
    }

    func testLocalQuestionSourceURLIsReportedButHTTPSIsFine() {
        let local = QuestionSource(title: "季度题库", sourceUrl: "/Users/someone/Downloads/题库.pdf",
                                   importedAt: "2026-08-06T00:00:00Z",
                                   importLevel: "full-question", questionCount: 10)
        let remote = QuestionSource(title: "线上题库", sourceUrl: "https://example.com/bank.json",
                                    importedAt: "2026-08-06T00:00:00Z",
                                    importLevel: "full-question", questionCount: 10)
        let findings = DataPortabilityAudit.audit(state: state([], sources: [local, remote]))
        XCTAssertEqual(findings.map(\.location), ["questionSources[0].sourceUrl"],
                       "https 链接换机器照样打得开，不该报；本机文件路径才是问题")
    }

    // MARK: - 文件到底在不在

    func testMissingReportFileIsReportedByTheDirectoryAudit() {
        // 路径写法没问题，但文件没跟着拷过来 —— 换机器后点开历史复盘会是一片空白。
        let value = state([session("s1", report: "reports/s1.json")])
        XCTAssertTrue(DataPortabilityAudit.audit(state: value).isEmpty,
                      "只看 state 时看不出文件在不在，这一层不该报")
        let findings = DataPortabilityAudit.audit(state: value, directory: directory)
        XCTAssertEqual(findings.map(\.location), ["sessions[0].reportPath"])
        XCTAssertTrue(findings[0].problem.contains("找不到"), "要说清是文件不见了，不是路径写错了")
    }

    func testMissingRecordingFileIsReportedByTheDirectoryAudit() throws {
        try writeFile("reports/s1.json")
        let value = state([session("s1", report: "reports/s1.json", recording: "recordings/s1.m4a")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value, directory: directory)
                        .map(\.location), ["sessions[0].recordingPath"])
    }

    func testAbsolutePathIsNotAlsoReportedAsMissing() {
        // 同一个字段只能报一次，否则用户会以为有两个不同的问题要修。
        let value = state([session("s1", report: "/tmp/nowhere/s1.json")])
        XCTAssertEqual(DataPortabilityAudit.audit(state: value, directory: directory).count, 1)
    }

    // MARK: - 报全，而不是只报第一条

    func testEveryProblemIsReportedNotJustTheFirst() {
        let value = state([
            session("s1", report: "/abs/a.json", recording: "~/b.m4a"),
            session("s2", report: "file:///c.json")
        ])
        XCTAssertEqual(Set(DataPortabilityAudit.audit(state: value).map(\.location)),
                       ["sessions[0].reportPath", "sessions[0].recordingPath", "sessions[1].reportPath"])
    }

    func testFindingIDsAreUnique() {
        let value = state([
            session("s1", report: "/abs/a.json", recording: "/abs/b.m4a"),
            session("s2", report: "/abs/c.json")
        ])
        let ids = DataPortabilityAudit.audit(state: value).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "列表渲染要用 id，重复会错乱")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter DataPortabilityAuditTests`
Expected: 编译失败 —— `DataPortabilityAudit`、`PortabilityFinding` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachCore/Storage/DataPortabilityAudit.swift`：

```swift
import Foundation

/// 一条「换台电脑就会断」的问题。
public struct PortabilityFinding: Equatable, Sendable, Identifiable {
    /// 位置即唯一键：同一个字段只报一次。
    public var id: String { location }
    /// 精确到字段，例如 "sessions[3].reportPath"。含糊的位置等于没报。
    public let location: String
    public let value: String
    /// 发生了什么。
    public let problem: String
    /// 下一步做什么。
    public let nextStep: String

    public init(location: String, value: String, problem: String, nextStep: String) {
        self.location = location; self.value = value
        self.problem = problem; self.nextStep = nextStep
    }

    /// 界面和命令行都用这一句，保证「发生了什么 + 下一步做什么」不会只讲一半。
    public var message: String { "\(location)：\(problem) 下一步：\(nextStep)" }
}

/// 检查数据目录能不能原样拷到另一台电脑接着用（成品标准第 10 条）。
///
/// **判据只有一条：里面存的路径必须全都相对于数据目录本身。**
/// 一旦某处存成绝对路径，在原机器上一切正常，什么都不会报错 ——
/// 只有换机器的那天才会发现历史复盘全打不开。这属于本项目最危险的那类失败：
/// 静默的、要到很久以后才暴露的。
public enum DataPortabilityAudit {

    /// 只看 `state.json` 里的路径写法，不碰磁盘。
    public static func audit(state: CoachState) -> [PortabilityFinding] {
        var findings: [PortabilityFinding] = []
        for (index, session) in state.sessions.enumerated() {
            if let finding = checkRelativePath(session.reportPath,
                                               at: "sessions[\(index)].reportPath",
                                               what: "这次练习的复盘文件") {
                findings.append(finding)
            }
            if let finding = checkRelativePath(session.recordingPath,
                                               at: "sessions[\(index)].recordingPath",
                                               what: "这次练习的录音文件") {
                findings.append(finding)
            }
        }
        for (index, source) in state.questionSources.enumerated() {
            if let finding = checkSourceURL(source.sourceUrl,
                                            at: "questionSources[\(index)].sourceUrl") {
                findings.append(finding)
            }
        }
        return findings
    }

    /// 在路径写法之外，再检查引用到的文件是不是真的在数据目录里。
    /// 路径写法没问题但文件没跟着拷过来，换机器后点开历史复盘会是一片空白。
    public static func audit(state: CoachState, directory: DataDirectory,
                             fileManager: FileManager = .default) -> [PortabilityFinding] {
        var findings = audit(state: state)
        let alreadyReported = Set(findings.map(\.location))

        func checkExists(_ path: String, at location: String, what: String) {
            // 写法本身已经报过的，不再重复报「找不到」——
            // 同一个字段报两条，用户会以为有两个不同的问题要修。
            guard !alreadyReported.contains(location) else { return }
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let url = directory.root.appending(path: trimmed)
            guard !fileManager.fileExists(atPath: url.path) else { return }
            findings.append(PortabilityFinding(
                location: location, value: trimmed,
                problem: "记录里指着 \(what)「\(trimmed)」，但数据目录里找不到这个文件。",
                nextStep: "确认拷贝数据目录时把 reports/ 和 recordings/ 两个子目录整个带上了；"
                    + "若这个文件本来就被删过，可以在训练记录里删掉这一条，其余记录不受影响。"))
        }

        for (index, session) in state.sessions.enumerated() {
            checkExists(session.reportPath, at: "sessions[\(index)].reportPath", what: "复盘文件")
            checkExists(session.recordingPath, at: "sessions[\(index)].recordingPath", what: "录音文件")
        }
        return findings
    }

    // MARK: - 私有

    private static func checkRelativePath(_ raw: String, at location: String,
                                          what: String) -> PortabilityFinding? {
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空字符串是合法的：练习还没生成复盘 / 没开录音时这两个字段本来就是空的。
        guard !path.isEmpty else { return nil }

        let advice = "把它改写成相对于数据目录的路径（形如 reports/<会话id>.json 或 recordings/<会话id>.m4a），"
            + "并检查写入这个字段的代码——存绝对路径在本机不会报任何错，只有换电脑那天才会暴露。"

        if path.hasPrefix("file://") {
            return PortabilityFinding(
                location: location, value: path,
                problem: "\(what)存的是 file:// 开头的完整 URL，里面带着这台电脑的用户名与目录结构。",
                nextStep: advice)
        }
        if path.hasPrefix("/") {
            return PortabilityFinding(
                location: location, value: path,
                problem: "\(what)存的是绝对路径，换台电脑后这个位置根本不存在。",
                nextStep: advice)
        }
        if path.hasPrefix("~") {
            return PortabilityFinding(
                location: location, value: path,
                problem: "\(what)存的是以 ~ 开头的路径，它不会被当成家目录展开，会被当成一个叫「~」的文件夹。",
                nextStep: advice)
        }
        if path.split(separator: "/").contains("..") {
            return PortabilityFinding(
                location: location, value: path,
                problem: "\(what)的路径里有 ..，指到了数据目录外面，拷贝数据目录时不会被带走。",
                nextStep: advice)
        }
        return nil
    }

    private static func checkSourceURL(_ raw: String, at location: String) -> PortabilityFinding? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        // https 链接换机器照样打得开，不是问题；本机文件路径才是。
        guard value.hasPrefix("/") || value.hasPrefix("file://") else { return nil }
        return PortabilityFinding(
            location: location, value: value,
            problem: "题库来源记的是这台电脑上的文件路径，换台电脑后点开是空的。",
            nextStep: "这条不影响已经导入的题目，可以不管；"
                + "若希望干净，重新导入一次题库并让来源只记文件名，不记完整路径。")
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter DataPortabilityAuditTests`
Expected: PASS（13 个测试）

- [ ] **Step 5: 突变验证（两条）**

**突变 A：** 把 `checkRelativePath` 里的
`guard !path.isEmpty else { return nil }`
改成
`guard !path.isEmpty || true else { return nil }`（即取消空值豁免）
重跑：`testEmptyPathsAreNotFindings` 必须变红。

**这条守的是「误报比漏报更致命」**：把「练习还没出复盘」当成数据损坏，用户每次打开关于页都看到一屏红字，几天之后他会学会无视所有告警——那时真正的问题也一起被无视了。

**突变 B：** 把 `audit(state:directory:fileManager:)` 里 `checkExists` 的整个 `findings.append(...)` 删掉（改成什么都不做）。
重跑：`testMissingReportFileIsReportedByTheDirectoryAudit` 与 `testMissingRecordingFileIsReportedByTheDirectoryAudit` 必须变红。

改回后确认全绿，把两次输出写进报告。

- [ ] **Step 6: 接上命令行**

`Sources/coach/PortabilityCommand.swift`：

```swift
import Foundation
import IELTSCoachCore

enum PortabilityCommand {
    static func run() -> Int32 {
        let directory = DataDirectory.resolve()
        let state: CoachState
        do {
            state = try StateStore(directory: directory).load()
        } catch {
            print("❌ \(error.localizedDescription)")
            return 1
        }

        print("数据目录：\(directory.root.path)")
        print("题库 \(state.questions.count) 题，练习记录 \(state.sessions.count) 次，"
            + "错题 \(state.issues.count) 条，词汇 \(state.vocabulary.count) 条")

        let findings = DataPortabilityAudit.audit(state: state, directory: directory)
        guard !findings.isEmpty else {
            print("✅ 这个目录可以整个拷到另一台电脑接着用，没发现任何依赖本机路径的地方。")
            return 0
        }
        print("\n⚠️  发现 \(findings.count) 处换电脑后会断掉的地方：")
        for finding in findings { print("   • \(finding.message)") }
        return 1
    }
}
```

`Sources/coach/main.swift`：用法文本里加一行，`switch` 里加一个分支。

```swift
      coach portability             检查数据目录能否原样搬到另一台电脑
```

```swift
case "portability":
    exit(PortabilityCommand.run())
```

- [ ] **Step 7: 验证命令行**

Run: `swift build && IELTS_SPEAKING_DATA_DIR="$(mktemp -d)" ./.build/debug/coach portability`
Expected: 打印数据目录路径与全 0 的统计，最后 `✅ 这个目录可以整个拷到另一台电脑接着用…`，退出码 0

- [ ] **Step 8: 提交**

```bash
git add Sources/IELTSCoachCore/Storage/DataPortabilityAudit.swift Sources/coach/PortabilityCommand.swift Sources/coach/main.swift Tests/IELTSCoachCoreTests/DataPortabilityAuditTests.swift
git commit -m "feat(core): 数据目录可搬迁审计与 coach portability"
```

---

## Task 5: 诊断信息（可复制，且不含练习内容）

**Files:**
- Create: `Sources/IELTSCoachUI/About/DiagnosticsReport.swift`
- Create: `Tests/IELTSCoachUITests/DiagnosticsReportTests.swift`

**Interfaces:**
- Consumes: `AppMetadata`（Task 3）、`PermissionState`（Phase 3）、`CoachState`、`PortabilityFinding`（Task 4）
- Produces:
  - `struct DiagnosticsInput: Sendable`，字段 `metadata: AppMetadata`、`dataDirectory: URL`、`systemVersion: String`、`permission: PermissionState`、`state: CoachState`、`portabilityFindingCount: Int`；`init(metadata:dataDirectory:systemVersion:permission:state:portabilityFindingCount:)`
  - `enum DiagnosticsReport { static func text(_ input: DiagnosticsInput) -> String }`

**为什么要有这个东西：** 「ChatGPT 改版导致自动化失效」是已知且不可避免的风险（ROADMAP 第 6 节）。真出问题时，用户需要能一键复制一段话发出来，而这段话必须**足够说明问题、又不带走任何练习内容**——逐字稿、错题原句、词汇、姓名都不能出现在里面。只报数量，不报内容。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/DiagnosticsReportTests.swift`：

```swift
import Foundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

final class DiagnosticsReportTests: XCTestCase {
    private let secretAnswer = "MY-SECRET-ANSWER-ABOUT-MY-FAMILY"
    private let secretIssue = "I-VERY-LIKE-IT-SECRET"
    private let secretWord = "SECRET-VOCAB-WORD"
    private let secretName = "SECRET-LEARNER-NAME"

    private func metadata() -> AppMetadata {
        AppMetadata(displayName: "IELTS Speaking Coach",
                    bundleIdentifier: "com.ielts.speakingcoach",
                    shortVersion: "1.0.0", buildNumber: "42",
                    buildCommit: "a1b2c3d", buildDate: "2026-08-06T09:00:00Z",
                    signingIdentity: "IELTS Coach Dev", channel: .selfSigned)
    }

    private func loadedState() -> CoachState {
        var state = CoachState.empty(displayName: secretName)
        state.questions = [
            Question(id: "q1", part: 1, topic: "Home", prompt: "Do you live in a house?"),
            Question(id: "q2", part: 2, topic: "Skills", prompt: "Describe a useful skill.")
        ]
        state.sessions = [
            PracticeSession(id: "s1", questionId: "q1", focusPart: .part1,
                            startedAt: "2026-08-06T00:00:00Z", endedAt: "2026-08-06T00:10:00Z",
                            goal: "",
                            transcript: [PracticeSession.TranscriptTurn(
                                role: "user", text: secretAnswer, capturedAt: "2026-08-06T00:01:00Z")],
                            reportPath: "reports/s1.json", recordingPath: "")
        ]
        state.issues = [IssueRecord(id: "i1", learnerSaid: secretIssue, correction: "c",
                                    whyItMatters: "w", occurrences: 3,
                                    sourceSessionIds: ["s1"], lastSeenAt: "2026-08-06T00:00:00Z")]
        state.vocabulary = [VocabularyRecord(id: "v1", basicWord: secretWord,
                                             betterExpression: "b", collocation: "c",
                                             priority: "high", sourceSessionIds: ["s1"])]
        state.targets = [RetrainingTarget(targetKey: "t1", label: "L", status: "new",
                                          evidence: [], sourceSessionId: "s1", createdAt: "t")]
        return state
    }

    private func input(permission: PermissionState = .ready,
                       findings: Int = 0) -> DiagnosticsInput {
        DiagnosticsInput(metadata: metadata(),
                         dataDirectory: URL(fileURLWithPath: "/Users/tester/Library/Application Support/IELTS Speaking Coach"),
                         systemVersion: "macOS 26.5.2",
                         permission: permission,
                         state: loadedState(),
                         portabilityFindingCount: findings)
    }

    func testContainsWhatSomeoneWouldNeedToDiagnoseIt() {
        let text = DiagnosticsReport.text(input())
        for needle in ["1.0.0", "42", "a1b2c3d", "com.ielts.speakingcoach",
                       "macOS 26.5.2",
                       "/Users/tester/Library/Application Support/IELTS Speaking Coach"] {
            XCTAssertTrue(text.contains(needle), "诊断信息里缺了「\(needle)」：\n\(text)")
        }
    }

    func testNeverLeaksPracticeContent() {
        // 这段话是要发给别人看的。数量可以给，内容一个字都不能带出去。
        let text = DiagnosticsReport.text(input())
        for secret in [secretAnswer, secretIssue, secretWord, secretName] {
            XCTAssertFalse(text.contains(secret),
                           "诊断信息把练习内容带出去了：「\(secret)」\n\(text)")
        }
    }

    func testReportsCountsInsteadOfContent() {
        let text = DiagnosticsReport.text(input())
        XCTAssertTrue(text.contains("2 题"), "题库数量应该给：\n\(text)")
        XCTAssertTrue(text.contains("1 次"), "练习次数应该给：\n\(text)")
        XCTAssertTrue(text.contains("1 条"), "错题/词汇数量应该给：\n\(text)")
    }

    func testEveryPermissionStateIsExplainedInChinese() {
        // 诊断信息里出现 "needsAccessibility" 这种枚举名，对用户等于没写。
        for state in [PermissionState.ready, .needsAccessibility, .needsChatGPT, .unknown] {
            let text = DiagnosticsReport.text(input(permission: state))
            XCTAssertFalse(text.contains("needsAccessibility"), "\(state) 露出了枚举名")
            XCTAssertFalse(text.contains("needsChatGPT"), "\(state) 露出了枚举名")
            XCTAssertFalse(text.contains("unknown"), "\(state) 露出了枚举名")
        }
    }

    func testUnreadyPermissionAlwaysCarriesANextStep() {
        for state in [PermissionState.needsAccessibility, .needsChatGPT, .unknown] {
            let text = DiagnosticsReport.text(input(permission: state))
            XCTAssertTrue(text.contains("下一步"), "\(state) 没告诉用户下一步做什么：\n\(text)")
        }
    }

    func testPortabilityProblemsAreSurfacedWithANextStep() {
        let clean = DiagnosticsReport.text(input(findings: 0))
        XCTAssertTrue(clean.contains("没有发现问题"))

        let dirty = DiagnosticsReport.text(input(permission: .ready, findings: 3))
        XCTAssertTrue(dirty.contains("3"), "要说清有几处")
        XCTAssertTrue(dirty.contains("下一步"), "有问题就必须给下一步")
    }

    func testNoLineIsBlankOrEndsWithADanglingLabel() {
        // 「版本：」后面空着，比不写还糟：用户会以为程序坏了。
        let text = DiagnosticsReport.text(input())
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty, "有空行：\n\(text)")
            XCTAssertFalse(line.hasSuffix("："), "有标签后面没内容：「\(line)」")
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter DiagnosticsReportTests`
Expected: 编译失败 —— `DiagnosticsReport`、`DiagnosticsInput` 未定义

- [ ] **Step 3: 实现**

`Sources/IELTSCoachUI/About/DiagnosticsReport.swift`：

```swift
import Foundation
import IELTSCoachCore

public struct DiagnosticsInput: Sendable {
    public let metadata: AppMetadata
    public let dataDirectory: URL
    public let systemVersion: String
    public let permission: PermissionState
    public let state: CoachState
    public let portabilityFindingCount: Int

    public init(metadata: AppMetadata, dataDirectory: URL, systemVersion: String,
                permission: PermissionState, state: CoachState,
                portabilityFindingCount: Int) {
        self.metadata = metadata; self.dataDirectory = dataDirectory
        self.systemVersion = systemVersion; self.permission = permission
        self.state = state; self.portabilityFindingCount = portabilityFindingCount
    }
}

/// 一段可以一键复制、直接发给别人的诊断文本。
///
/// **只报数量，不报内容。** 逐字稿、错题原句、词汇、姓名都不进这段文字 ——
/// 用户复制它的时候不会逐字检查里面有什么，所以这个边界只能由代码保证。
public enum DiagnosticsReport {
    public static func text(_ input: DiagnosticsInput) -> String {
        var lines: [String] = []
        lines.append("IELTS Speaking Coach 诊断信息")
        lines.append("版本：\(input.metadata.versionLine)")
        lines.append("提交：\(input.metadata.buildCommit)")
        lines.append("构建时间：\(input.metadata.buildDate)")
        lines.append("签名：\(input.metadata.channel.title)（身份：\(input.metadata.signingIdentity)）")
        lines.append("标识：\(input.metadata.bundleIdentifier)")
        lines.append("系统：\(input.systemVersion)")
        lines.append("数据目录：\(input.dataDirectory.path)")
        lines.append("数据量：题库 \(input.state.questions.count) 题 · "
            + "练习记录 \(input.state.sessions.count) 次 · "
            + "错题 \(input.state.issues.count) 条 · "
            + "词汇 \(input.state.vocabulary.count) 条 · "
            + "重训目标 \(input.state.targets.count) 个")
        lines.append("辅助功能：\(permissionText(input.permission))")
        if input.portabilityFindingCount == 0 {
            lines.append("数据可搬迁检查：没有发现问题")
        } else {
            lines.append("数据可搬迁检查：发现 \(input.portabilityFindingCount) 处问题。"
                + "下一步：在关于页点「查看详情」，按每条给的提示逐条处理。")
        }
        lines.append("——以上只有数量，不含任何练习内容。要看具体内容请直接打开数据目录。")
        return lines.joined(separator: "\n")
    }

    private static func permissionText(_ state: PermissionState) -> String {
        switch state {
        case .ready:
            return "已授权，自动化可用"
        case .needsAccessibility:
            return "未授权，只能半自动运行。下一步：系统设置 › 隐私与安全性 › 辅助功能，把本 App 加进去并勾选。"
        case .needsChatGPT:
            return "判断不了——本机没找到 ChatGPT（新版桌面应用）。下一步：先安装它，再回来重新检查。"
        case .unknown:
            return "环境检查没通过，原因不在已知的几种里。下一步：在关于页点「重新检查」，把它显示的原始消息一并发出来。"
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter DiagnosticsReportTests`
Expected: PASS（7 个测试）

- [ ] **Step 5: 突变验证**

在 `text(_:)` 里加一行
`lines.append("学员：\(input.state.learner.displayName)")`
重跑：`testNeverLeaksPracticeContent` 必须变红。删掉后确认全绿。

**这条守的是隐私边界不是靠自觉维持的**。「顺手把姓名也带上，好认一点」是一个非常自然的改动，而这段文字的用途就是发给别人看。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/About/DiagnosticsReport.swift Tests/IELTSCoachUITests/DiagnosticsReportTests.swift
git commit -m "feat(ui): 可复制的诊断信息"
```

---

## Task 6: 关于页视图模型、致谢与许可

**Files:**
- Create: `LICENSE`
- Create: `Sources/IELTSCoachUI/About/AboutViewModel.swift`
- Create: `Tests/IELTSCoachUITests/AboutViewModelTests.swift`

**Interfaces:**
- Consumes: `AppMetadata`、`SignatureChannel`（Task 3）、`PermissionState`（Phase 3）、`PortabilityFinding`（Task 4）
- Produces:
  - `struct AboutRow: Equatable, Identifiable, Sendable { let id: String; let label: String; let value: String; let hint: String }`
  - `struct Acknowledgement: Equatable, Identifiable, Sendable { var id: String { name }; let name: String; let role: String; let license: String; let url: String }`
  - `enum AboutViewModel`
    - `static func rows(metadata: AppMetadata, dataDirectory: URL, permission: PermissionState, portabilityFindings: [PortabilityFinding]) -> [AboutRow]`
    - `static let acknowledgements: [Acknowledgement]`
    - `static let licenseNotice: String`

### 许可怎么定

仓库现在没有 `LICENSE` 文件。**默认取「保留所有权利、个人自用」**，理由：这是个自用工具（成品标准第 4 节明确「不做云同步、不做多用户」，ROADMAP 决策记录写的是「先自用，架构预留分发能力」）。把编译好的副本给朋友，在这个条款下是作者自己在行使权利，完全没问题。

**若用户想开源，只需要改两处**：`LICENSE` 文件本身，和 `AboutViewModel.licenseNotice`。这一条列进本阶段需要用户确认的事项（见文末「需要用户参与的环节」）。

商标声明必须有，而且必须准确——这个 App 会被交到别人手上，不能让人误以为它是 OpenAI 或雅思主办方的产品。

- [ ] **Step 1: 写 `LICENSE`**

仓库根目录 `LICENSE`：

```
版权所有 © 2026 IELTS Speaking Coach 的作者。保留所有权利。

本工具为个人自用而写。作者可以把编译好的副本给任何人，收到副本的人可以自用；
未授予公开再分发、修改或商业使用的许可。

本工具与 OpenAI 无隶属关系，也不隶属于任何雅思考试主办方
（British Council、IDP、Cambridge Assessment English）。
"IELTS" 与 "ChatGPT" 是各自权利人的商标，此处仅用于说明本工具的用途。

本工具不内置任何商业题库，只带原创样例；你的题库由你自己导入。
本工具不调用 OpenAI 的任何接口，复盘由你自己的 ChatGPT 账号在本机生成。

本工具按现状提供，不作任何明示或默示的担保。
```

- [ ] **Step 2: 写失败的测试**

`Tests/IELTSCoachUITests/AboutViewModelTests.swift`：

```swift
import Foundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

final class AboutViewModelTests: XCTestCase {
    private let dataDirectory = URL(
        fileURLWithPath: "/Users/tester/Library/Application Support/IELTS Speaking Coach")

    private func metadata(channel: SignatureChannel = .selfSigned) -> AppMetadata {
        AppMetadata(displayName: "IELTS Speaking Coach",
                    bundleIdentifier: "com.ielts.speakingcoach",
                    shortVersion: "1.0.0", buildNumber: "42",
                    buildCommit: "a1b2c3d", buildDate: "2026-08-06T09:00:00Z",
                    signingIdentity: "IELTS Coach Dev", channel: channel)
    }

    private func rows(channel: SignatureChannel = .selfSigned,
                      permission: PermissionState = .ready,
                      findings: [PortabilityFinding] = []) -> [AboutRow] {
        AboutViewModel.rows(metadata: metadata(channel: channel),
                            dataDirectory: dataDirectory,
                            permission: permission,
                            portabilityFindings: findings)
    }

    func testEveryRowHasBothALabelAndAValue() {
        // 只有标签没有内容的一行，会让人以为程序坏了。
        for row in rows() {
            XCTAssertFalse(row.label.isEmpty, "\(row.id) 缺标签")
            XCTAssertFalse(row.value.isEmpty, "\(row.id) 缺内容")
        }
    }

    func testRowIDsAreUnique() {
        let ids = rows().map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "ForEach 用 id 渲染，重复会错乱")
    }

    func testDataDirectoryRowShowsTheRealPathAndSaysItIsPortable() {
        let row = rows().first { $0.id == "dataDirectory" }
        XCTAssertEqual(row?.value, dataDirectory.path)
        XCTAssertTrue(row?.hint.contains("拷") ?? false,
                      "数据目录这行必须告诉用户「换电脑时拷这个文件夹」，那是这一行存在的全部意义")
    }

    func testBundleIdentifierRowExplainsWhyItNeverChanges() {
        let row = rows().first { $0.id == "bundle" }
        XCTAssertEqual(row?.value, "com.ielts.speakingcoach")
        XCTAssertFalse(row?.hint.isEmpty ?? true,
                       "这一行要解释为什么这个标识永远不变——它是辅助功能授权的锚")
    }

    func testSelfSignedSignatureRowTellsTheRecipientHowToOpenIt() {
        let row = rows(channel: .selfSigned).first { $0.id == "signature" }
        let hint = row?.hint ?? ""
        XCTAssertTrue(hint.contains("系统设置"), "没说去哪儿：\(hint)")
        XCTAssertTrue(hint.contains("仍要打开"), "没说点什么：\(hint)")
    }

    func testDeveloperIDSignatureRowDoesNotScareTheUser() {
        let hint = rows(channel: .developerID).first { $0.id == "signature" }?.hint ?? ""
        XCTAssertFalse(hint.contains("仍要打开"),
                       "已公证的包双击就能开，不该还教人绕 Gatekeeper")
    }

    func testPermissionRowCarriesANextStepWhenNotGranted() {
        let granted = rows(permission: .ready).first { $0.id == "permission" }
        XCTAssertFalse(granted?.value.isEmpty ?? true)

        for state in [PermissionState.needsAccessibility, .needsChatGPT, .unknown] {
            let row = rows(permission: state).first { $0.id == "permission" }
            XCTAssertTrue(row?.hint.contains("下一步") ?? false,
                          "\(state) 没告诉用户下一步做什么")
        }
    }

    func testPortabilityRowSaysOKWhenCleanAndCountsWhenNot() {
        let clean = rows().first { $0.id == "portability" }
        XCTAssertTrue(clean?.value.contains("没有发现问题") ?? false)

        let finding = PortabilityFinding(location: "sessions[0].reportPath", value: "/abs/a.json",
                                         problem: "绝对路径。", nextStep: "改成相对路径。")
        let dirty = rows(findings: [finding, finding]).first { $0.id == "portability" }
        XCTAssertTrue(dirty?.value.contains("2") ?? false, "要说清有几处")
        XCTAssertTrue(dirty?.hint.contains("sessions[0].reportPath") ?? false,
                      "至少要把第一条的位置显示出来，否则用户不知道去哪儿看")
    }

    func testDevelopmentRunStillProducesCompleteRows() {
        // swift run 直接跑（没有 App bundle）时，关于页照样得能看。
        let rows = AboutViewModel.rows(metadata: AppMetadata.from(infoDictionary: nil),
                                       dataDirectory: dataDirectory,
                                       permission: .ready, portabilityFindings: [])
        XCTAssertFalse(rows.isEmpty)
        for row in rows { XCTAssertFalse(row.value.isEmpty, "\(row.id) 在开发运行时变成了空白") }
    }

    // MARK: - 致谢与许可

    func testAcknowledgementsCreditTheUpstreamProject() {
        let upstream = AboutViewModel.acknowledgements
            .first { $0.name.contains("ielts-speaking-coach") }
        XCTAssertNotNil(upstream, "本项目的功能范围、复盘规范与 state.json 结构都来自上游，出处必须写明")
        XCTAssertFalse(upstream?.url.isEmpty ?? true, "上游要给得出链接")
    }

    func testAcknowledgementsStateTheOpenAIDisclaimer() {
        let joined = AboutViewModel.acknowledgements
            .map { "\($0.name)\($0.role)\($0.license)" }.joined()
        XCTAssertTrue(joined.contains("无隶属关系"),
                      "这个 App 会被交到别人手上，必须写明与 OpenAI 无隶属关系")
    }

    func testEveryAcknowledgementIsComplete() {
        for item in AboutViewModel.acknowledgements {
            XCTAssertFalse(item.name.isEmpty, "致谢条目缺名字")
            XCTAssertFalse(item.role.isEmpty, "「\(item.name)」没说它在这个项目里是干什么的")
            XCTAssertFalse(item.license.isEmpty, "「\(item.name)」没写许可情况")
        }
    }

    func testAcknowledgementIDsAreUnique() {
        let ids = AboutViewModel.acknowledgements.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testLicenseNoticeCoversTrademarksAndRedistribution() {
        let notice = AboutViewModel.licenseNotice
        XCTAssertFalse(notice.isEmpty)
        XCTAssertTrue(notice.contains("商标"), "许可说明里要有商标声明")
        XCTAssertTrue(notice.contains("再分发"), "许可说明里要说清能不能再分发")
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter AboutViewModelTests`
Expected: 编译失败 —— `AboutViewModel` 未定义

- [ ] **Step 4: 实现**

`Sources/IELTSCoachUI/About/AboutViewModel.swift`：

```swift
import Foundation
import IELTSCoachCore

public struct AboutRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let value: String
    /// 补充说明。凡是用户可能要做点什么的行，这里必须含「下一步」。
    public let hint: String

    public init(id: String, label: String, value: String, hint: String) {
        self.id = id; self.label = label; self.value = value; self.hint = hint
    }
}

public struct Acknowledgement: Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    /// 它在这个项目里到底起了什么作用。只写名字等于没致谢。
    public let role: String
    public let license: String
    public let url: String

    public init(name: String, role: String, license: String, url: String) {
        self.name = name; self.role = role; self.license = license; self.url = url
    }
}

public enum AboutViewModel {

    public static func rows(metadata: AppMetadata, dataDirectory: URL,
                            permission: PermissionState,
                            portabilityFindings: [PortabilityFinding]) -> [AboutRow] {
        [
            AboutRow(id: "version", label: "版本", value: metadata.versionLine,
                     hint: "构建于 \(metadata.buildDate)，提交 \(metadata.buildCommit)。"),
            AboutRow(id: "bundle", label: "标识", value: metadata.bundleIdentifier,
                     hint: "系统的辅助功能授权绑定这个标识，因此它在任何版本里都不会变。"
                         + "看到授权莫名失效时，先确认这一行还是它。"),
            AboutRow(id: "signature", label: "签名", value: metadata.channel.title,
                     hint: "\(metadata.channel.explanation) \(metadata.channel.nextStep)"),
            AboutRow(id: "permission", label: "辅助功能", value: permissionValue(permission),
                     hint: permissionHint(permission)),
            AboutRow(id: "dataDirectory", label: "数据目录", value: dataDirectory.path,
                     hint: "你的题库、练习记录、复盘、录音全在这个文件夹里。"
                         + "换电脑时把它整个拷过去就能接着用；备份就是拷贝它。"),
            portabilityRow(portabilityFindings)
        ]
    }

    private static func permissionValue(_ state: PermissionState) -> String {
        switch state {
        case .ready: return "已授权"
        case .needsAccessibility: return "未授权（半自动模式）"
        case .needsChatGPT: return "无法判断"
        case .unknown: return "检查未通过"
        }
    }

    private static func permissionHint(_ state: PermissionState) -> String {
        switch state {
        case .ready:
            return "本 App 用它来替你操作 ChatGPT：新建会话、点开语音、发考官提示词、取回复盘。"
        case .needsAccessibility:
            return "没有它就只能半自动：提示词要你自己粘、复盘要你自己 ⌘C。"
                + "下一步：系统设置 › 隐私与安全性 › 辅助功能，把本 App 加进去并勾选，回来点「重新检查」。"
        case .needsChatGPT:
            return "本机没找到 ChatGPT（新版桌面应用）。注意 ChatGPT Classic 没有语音，不是这里要的那个。"
                + "下一步：装好新版 ChatGPT.app 之后回来点「重新检查」。"
        case .unknown:
            return "环境检查没通过，原因不在已知的几种里。"
                + "下一步：点「重新检查」看原始消息；若看不懂，用「复制诊断信息」把它整段发出来。"
        }
    }

    private static func portabilityRow(_ findings: [PortabilityFinding]) -> AboutRow {
        guard let first = findings.first else {
            return AboutRow(id: "portability", label: "数据可搬迁检查",
                            value: "没有发现问题",
                            hint: "这个目录可以整个拷到另一台电脑接着用。")
        }
        let more = findings.count > 1 ? "（共 \(findings.count) 处，这里只列第一条）" : ""
        return AboutRow(id: "portability", label: "数据可搬迁检查",
                        value: "发现 \(findings.count) 处问题",
                        hint: "\(first.message)\(more)")
    }

    // MARK: - 致谢

    public static let acknowledgements: [Acknowledgement] = [
        Acknowledgement(
            name: "lindsey-labs/ielts-speaking-coach",
            role: "上游项目。本工具的功能范围、复盘规范与 state.json 结构都来自它。"
                + "本工具是 macOS 原生重写，没有复制它的任何代码。",
            license: "未使用其代码，因此不受其许可证约束；此处仅作出处致谢。",
            url: "https://github.com/lindsey-labs/ielts-speaking-coach"),
        Acknowledgement(
            name: "SF Symbols",
            role: "界面里的全部图标。",
            license: "Apple 提供。可在应用界面中使用，不得改造成自有字体，也不得用作商标。",
            url: "https://developer.apple.com/sf-symbols/"),
        Acknowledgement(
            name: "SF Pro（macOS 系统字体）",
            role: "界面里的全部文字。",
            license: "随系统提供，未打包进本 App。",
            url: ""),
        Acknowledgement(
            name: "OpenAI ChatGPT",
            role: "本工具驱动你本机已安装的 ChatGPT 应用完成练习与复盘，"
                + "不调用 OpenAI 的任何接口，也不产生额外费用。",
            license: "本工具与 OpenAI 无隶属关系，也未获其背书。",
            url: ""),
        Acknowledgement(
            name: "第三方依赖",
            role: "没有。整个工程只用 Swift 标准库与系统框架。",
            license: "不适用。",
            url: "")
    ]

    /// 与仓库根目录的 LICENSE 保持一致。要改就两处一起改。
    public static let licenseNotice = """
        版权所有 © 2026 IELTS Speaking Coach 的作者。保留所有权利。

        本工具为个人自用而写。作者可以把编译好的副本给任何人，收到副本的人可以自用；\
        未授予公开再分发、修改或商业使用的许可。

        本工具与 OpenAI 无隶属关系，也不隶属于任何雅思考试主办方\
        （British Council、IDP、Cambridge Assessment English）。\
        "IELTS" 与 "ChatGPT" 是各自权利人的商标，此处仅用于说明本工具的用途。

        本工具按现状提供，不作任何明示或默示的担保。
        """
}
```

**若实现过程中发现工程里其实复制了上游的任何代码**（比如逐字移植的算法、逐字照抄的提示词文本），**必须停下来**：去核对上游仓库的 LICENSE，把 `acknowledgements` 里那一条的 `license` 改成真实的许可证名，并确认本项目的分发方式与之相容。这不是形式问题，是许可证问题。

- [ ] **Step 5: 运行，确认通过**

Run: `swift test --filter AboutViewModelTests`
Expected: PASS（14 个测试）

- [ ] **Step 6: 突变验证（两条）**

**突变 A：** 把 `SignatureChannel.selfSigned.nextStep` 的返回值改成 `""`。
重跑：`testSelfSignedSignatureRowTellsTheRecipientHowToOpenIt`（Task 6）与 `testSelfSignedTellsTheRecipientHowToGetPastGatekeeper`（Task 3）必须同时变红。

**这条守的是这个阶段的交付定义本身**：交付物是「一个能给别人的 `.app`」。实测过 `spctl` 判定为 `rejected`——对方双击一定打不开。少了这句话，这个 `.app` 就只是「能给别人，但别人打不开」。

**突变 B：** 把 `portabilityRow` 里 `guard let first = findings.first else { ... }` 的两个分支对调（有问题时返回「没有发现问题」）。
重跑：`testPortabilityRowSaysOKWhenCleanAndCountsWhenNot` 必须变红。

改回后确认全绿，把输出写进报告。

- [ ] **Step 7: 提交**

```bash
git add LICENSE Sources/IELTSCoachUI/About/AboutViewModel.swift Tests/IELTSCoachUITests/AboutViewModelTests.swift
git commit -m "feat(ui): 关于页视图模型、致谢与许可"
```

---

## Task 7: 关于页界面与菜单接入

**Files:**
- Create: `Sources/IELTSCoachUI/About/AboutView.swift`
- Modify: `Sources/IELTSCoachApp/main.swift`

**Interfaces:**
- Consumes: `AboutViewModel.rows(...)`、`AboutViewModel.acknowledgements`、`AboutViewModel.licenseNotice`、`AppMetadata.current`、`DiagnosticsReport.text(_:)`、`DataPortabilityAudit.audit(state:directory:)`、`DataDirectory.resolve()`、`StateStore.load()`、`PermissionStatus.evaluate(readiness:)`、设计令牌与 `CoachCard` / `SectionHeader`
- Produces:
  - `enum AboutWindow { static let id = "about" }`
  - `struct AboutMenuButton: View`（`public init()`）
  - `struct AboutView: View`（`public init()`）

**关于页是独立窗口，拿不到主窗口的 `AppState`，所以它自己读一次。** 这是只读页，重复读一次 `state.json` 的代价可以忽略；换成到处传 `AppState` 反而会把主窗口的生命周期和一个偶尔打开的小窗绑死。

**不要往侧边栏加第 11 项。** 侧边栏固定十项，Phase 3 的 `testSidebarHasAllTenItems` 守着它，那条测试是对的。关于页在苹果菜单里（`关于 IELTS Speaking Coach`），这是 Mac 应用的标准位置。

- [ ] **Step 1: 改 `Sources/IELTSCoachApp/main.swift`**

这一段给完整代码——它不是布局，是 Scene 与菜单的结构，摆错了关于页根本打不开。

```swift
import IELTSCoachUI
import SwiftUI

struct CoachApp: App {
    var body: some Scene {
        WindowGroup("IELTS Speaking Coach") { RootView() }
            .defaultSize(width: 1100, height: 720)
            .commands {
                // 替换系统默认的「关于 …」，指向我们自己的窗口。
                // 放在苹果菜单里是 Mac 应用的标准位置——不要为它在侧边栏加第 11 项。
                CommandGroup(replacing: .appInfo) { AboutMenuButton() }
            }

        Window("关于 IELTS Speaking Coach", id: AboutWindow.id) { AboutView() }
            .windowResizability(.contentSize)
    }
}

CoachApp.main()
```

- [ ] **Step 2: 写 `AboutView.swift`**

`AboutWindow` 与 `AboutMenuButton` 给完整代码（结构性的）：

```swift
import AppKit
import SwiftUI

public enum AboutWindow {
    public static let id = "about"
}

/// 苹果菜单里的「关于 …」。
public struct AboutMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        Button("关于 IELTS Speaking Coach") { openWindow(id: AboutWindow.id) }
    }
}
```

`AboutView` 只给验收要求，布局由实现者定：

| 必须做到 | 判据 |
|---|---|
| 顶部显示 App 名称与版本行 | 文案取 `AppMetadata.current.versionLine`，不得写死 |
| 逐行显示 `AboutViewModel.rows(...)` 的六行 | 每行显示 `label` / `value` / `hint`；`hint` 为空时不显示空行 |
| 「在访达中显示」按钮 | 点了调 `NSWorkspace.shared.activateFileViewerSelecting([dataDirectory])`；数据目录不存在时先 `try? DataDirectory.resolve().createIfNeeded()` |
| 「复制诊断信息」按钮 | 把 `DiagnosticsReport.text(...)` 写进 `NSPasteboard.general`，并给一句「已复制」的即时反馈（否则用户不知道点没点上） |
| 「重新检查」按钮 | 重新跑 `preflight()` + 可搬迁审计，刷新页面 |
| 致谢区 | 逐条显示 `acknowledgements` 的 `name` / `role` / `license`；`url` 非空时才显示可点的链接 |
| 许可区 | 显示 `AboutViewModel.licenseNotice` 全文，可选中复制 |
| 读 `state.json` 失败时 | **不能空白**。显示中文错误全文 + 数据目录路径 + 「重试」按钮。其余各行（版本、签名、权限）仍要正常显示——读不到训练数据不影响它们 |
| 全部走设计令牌 | 视图里不得出现字面颜色、字号、圆角 |
| 图标只用 SF Symbols | 不得用 emoji |
| 窗口尺寸 | 内容自适应，`.windowResizability(.contentSize)`；文字放大到系统最大档时不截断、不重叠 |

**这一页有一个容易踩的坑：** 它在 `swift run IELTSCoachApp` 下运行时 `AppMetadata` 全是「未知（开发运行）」，看上去像坏了。**这不是 bug**，Task 3 的测试专门保证了它显示得像样。要看真实版本号，得跑 `./scripts/build-app.sh` 之后打开 `.app`。

- [ ] **Step 3: 编译与人工验证**

Run: `swift build && swift test`
Expected: 构建通过，全部测试绿

Run: `./scripts/build-app.sh && open ".build/IELTS Speaking Coach.app"`
Expected: 菜单栏 `IELTS Speaking Coach › 关于 IELTS Speaking Coach` 能打开关于窗口；六行都有内容；版本显示 `1.0.0（构建 N）`；签名那行显示「自签名（未经 Apple 公证）」并给出「系统设置 › … › 仍要打开」的说明；数据目录那行显示真实路径且「在访达中显示」能打开 Finder。

Run: 在关于页点「复制诊断信息」，然后 `pbpaste`
Expected: 打印出诊断文本；**逐行读一遍，确认里面没有任何练习内容**（这是 Task 5 测试之外的一次人眼复核）

- [ ] **Step 4: 提交**

```bash
git add Sources/IELTSCoachUI/About/AboutView.swift Sources/IELTSCoachApp/main.swift
git commit -m "feat(ui): 关于页与菜单接入"
```

---

## Task 8: 首次使用引导

**Files:**
- Create: `Sources/IELTSCoachUI/Onboarding/OnboardingFlow.swift`
- Create: `Sources/IELTSCoachUI/Onboarding/OnboardingProgressStore.swift`
- Create: `Sources/IELTSCoachUI/Onboarding/WelcomeFlowView.swift`
- Modify: `Sources/IELTSCoachUI/RootView.swift`
- Create: `Tests/IELTSCoachUITests/OnboardingFlowTests.swift`

**Interfaces:**
- Consumes: `PermissionState`、`PermissionStatus.systemSettingsURL`、`PermissionGateView(state:messages:onRecheck:onSkip:)`（全部来自 Phase 3 Task 2）、`AppState`、`CoachState.questions`、`CoachSettings`、`StateStore.mutate`
- Produces:
  - `enum OnboardingStep: String, CaseIterable, Identifiable, Sendable { case welcome, environment, questionBank, recordingChoice, ready }`
    - `var title: String` / `var body: String` / `var primaryActionTitle: String` / `var canSkip: Bool`
  - `enum OnboardingFlow`
    - `static let currentVersion = 1`
    - `static func steps(permission: PermissionState, questionCount: Int, hasCompletedBefore: Bool) -> [OnboardingStep]`
    - `static func shouldPresent(permission: PermissionState, questionCount: Int, hasCompletedBefore: Bool) -> Bool`
  - `protocol OnboardingProgressStore: AnyObject { func completedVersion() -> Int; func markCompleted(version: Int) }`
  - `final class UserDefaultsOnboardingStore: OnboardingProgressStore`，`static let key = "com.ielts.speakingcoach.onboardingCompletedVersion"`，`init(defaults: UserDefaults = .standard)`
  - `struct WelcomeFlowView: View`

### 两条决定了这个任务全部形状的设计判断

**一、「看过引导没有」这个标记存在本机 `UserDefaults`，不存进数据目录。**

这不是偷懒，是这一整个阶段的核心命题的直接推论。数据目录里应该**只放换机器时要跟着走的东西**；而「引导看过没有」恰恰是**不该**跟着走的：换了机器，辅助功能授权是本机 TCC 的，必须重给一次。要是把这个标记写进 `state.json`，新机器上的用户一进来就没有引导，直接撞上一堵「点开始练习却报错」的墙——而他手上的数据看起来一切正常，根本想不到问题出在权限。

**二、走过引导的人，只有一种情况会再看到它：辅助功能权限不在了。**

（换了机器、系统升级后 TCC 被重置、或者用户自己取消了勾选。）这时只显示「环境」那一步。其余步骤不再打扰：题库空不空首页已经有空状态引导，录音开关在设置里随时能改。

**「环境」这一步永远可跳过**，跳过就直接进主界面跑半自动模式（设计文档第 7 节：授权可跳过）。跳过之后如果权限仍然缺，**下次启动还会再问一次**——这是刻意的：没有辅助功能权限，这个产品的核心自动化就是残的，每次开机温和地提醒一次（且一键可跳过）比默默残废好。

- [ ] **Step 1: 写失败的测试**

`Tests/IELTSCoachUITests/OnboardingFlowTests.swift`：

```swift
import Foundation
import XCTest
@testable import IELTSCoachUI

final class OnboardingFlowTests: XCTestCase {

    private func steps(permission: PermissionState, questions: Int,
                       completed: Bool) -> [OnboardingStep] {
        OnboardingFlow.steps(permission: permission, questionCount: questions,
                             hasCompletedBefore: completed)
    }

    // MARK: - 全新安装

    func testFreshInstallWalksThroughEverything() {
        XCTAssertEqual(steps(permission: .needsAccessibility, questions: 0, completed: false),
                       [.welcome, .environment, .questionBank, .recordingChoice, .ready])
    }

    func testFreshInstallSkipsTheImportStepWhenQuestionsAreAlreadyThere() {
        // 这正是「把数据目录拷过来的人」在新机器上第一次开 App 的样子：
        // 题库在，练习记录也在，再让他导一次题库是在浪费他时间、也让人怀疑数据没拷成功。
        XCTAssertEqual(steps(permission: .needsAccessibility, questions: 217, completed: false),
                       [.welcome, .environment, .recordingChoice, .ready])
    }

    func testFreshInstallStillExplainsThePermissionEvenWhenAlreadyGranted() {
        // 权限已经给了也要过一遍这一步：用户有权知道这个 App 拿辅助功能去干什么。
        XCTAssertTrue(steps(permission: .ready, questions: 5, completed: false)
                        .contains(.environment))
    }

    func testFirstStepIsAlwaysWelcomeAndLastIsAlwaysReady() {
        for permission in [PermissionState.ready, .needsAccessibility, .needsChatGPT, .unknown] {
            for count in [0, 100] {
                let result = steps(permission: permission, questions: count, completed: false)
                XCTAssertEqual(result.first, .welcome, "\(permission)/\(count) 的第一步不是欢迎")
                XCTAssertEqual(result.last, .ready, "\(permission)/\(count) 的最后一步不是完成")
            }
        }
    }

    // MARK: - 已经走过引导的人

    func testReturningUserWithEverythingReadySeesNothing() {
        XCTAssertTrue(steps(permission: .ready, questions: 217, completed: true).isEmpty)
        XCTAssertTrue(steps(permission: .ready, questions: 0, completed: true).isEmpty,
                      "题库空不该再弹引导——首页的空状态已经在引导他导入了")
    }

    func testReturningUserWithoutAccessibilitySeesOnlyTheEnvironmentStep() {
        // 换机器场景：数据拷过来了，题库和记录都在，但辅助功能授权是本机的，必须重给。
        // 少了这一步，用户会打开一个「看起来一切正常、点开始练习却报错」的 App。
        XCTAssertEqual(steps(permission: .needsAccessibility, questions: 217, completed: true),
                       [.environment])
    }

    func testReturningUserWithoutChatGPTSeesTheEnvironmentStep() {
        XCTAssertEqual(steps(permission: .needsChatGPT, questions: 217, completed: true),
                       [.environment])
    }

    func testReturningUserWithAnUnrecognizedFailureSeesTheEnvironmentStep() {
        // 不能因为「没认出来」就当成就绪放过去——那会让用户点进去撞一堵没有线索的墙。
        XCTAssertEqual(steps(permission: .unknown, questions: 217, completed: true),
                       [.environment])
    }

    func testShouldPresentAgreesWithSteps() {
        for permission in [PermissionState.ready, .needsAccessibility, .needsChatGPT, .unknown] {
            for count in [0, 217] {
                for completed in [true, false] {
                    let hasSteps = !steps(permission: permission, questions: count,
                                          completed: completed).isEmpty
                    XCTAssertEqual(
                        OnboardingFlow.shouldPresent(permission: permission, questionCount: count,
                                                     hasCompletedBefore: completed),
                        hasSteps,
                        "\(permission)/\(count)/\(completed) 两者对不上")
                }
            }
        }
    }

    // MARK: - 每一步自己

    func testOnlyEnvironmentAndQuestionBankCanBeSkipped() {
        // welcome / ready 只是叙述，没有可跳过的东西；
        // recordingChoice 本身就是一个二选一（默认关也是一种选择），不该给「跳过」。
        XCTAssertEqual(Set(OnboardingStep.allCases.filter(\.canSkip)),
                       [.environment, .questionBank])
    }

    func testEveryStepHasChineseTitleBodyAndPrimaryAction() {
        for step in OnboardingStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step) 没标题")
            XCTAssertFalse(step.body.isEmpty, "\(step) 没正文")
            XCTAssertFalse(step.primaryActionTitle.isEmpty, "\(step) 没有主按钮文案")
        }
    }

    func testEnvironmentStepTellsUserWhatHappensIfTheySkip() {
        // 跳过是允许的（设计文档第 7 节），但必须让他知道跳过之后是什么样子。
        XCTAssertTrue(OnboardingStep.environment.body.contains("半自动"),
                      "没说清跳过之后会怎样：\(OnboardingStep.environment.body)")
    }

    func testRecordingStepSaysItIsOffByDefault() {
        // 录音默认关、开启需明确同意（ROADMAP 第 5 节）。这一步必须说清楚。
        let body = OnboardingStep.recordingChoice.body
        XCTAssertTrue(body.contains("默认"), "没说默认状态：\(body)")
        XCTAssertTrue(body.contains("本机"), "没说录音只存在本机：\(body)")
    }

    // MARK: - 进度的存放

    func testStoreRoundTripsWithinOneVersion() {
        let defaults = UserDefaults(suiteName: "onboarding-test-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let store = UserDefaultsOnboardingStore(defaults: defaults)

        XCTAssertEqual(store.completedVersion(), 0, "没记过就是 0，不能是别的什么")
        store.markCompleted(version: OnboardingFlow.currentVersion)
        XCTAssertEqual(store.completedVersion(), OnboardingFlow.currentVersion)
    }

    func testBumpingTheVersionMakesOldUsersSeeItAgain() {
        // 将来引导内容大改时，把 currentVersion 加 1，老用户会再看一次。
        // 不留这个口子的话，改了引导也没人看得到。
        let defaults = UserDefaults(suiteName: "onboarding-test-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let store = UserDefaultsOnboardingStore(defaults: defaults)
        store.markCompleted(version: 1)

        XCTAssertTrue(store.completedVersion() >= 1)
        XCTAssertFalse(store.completedVersion() >= 2, "版本号涨了就该重新引导")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter OnboardingFlowTests`
Expected: 编译失败 —— `OnboardingFlow`、`OnboardingStep`、`UserDefaultsOnboardingStore` 未定义

- [ ] **Step 3: 实现步骤与流程**

`Sources/IELTSCoachUI/Onboarding/OnboardingFlow.swift`：

```swift
import Foundation

public enum OnboardingStep: String, CaseIterable, Identifiable, Sendable {
    case welcome
    case environment
    case questionBank
    case recordingChoice
    case ready

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .welcome: return "欢迎"
        case .environment: return "让它能替你操作 ChatGPT"
        case .questionBank: return "先把你的题库导进来"
        case .recordingChoice: return "要不要录下你的回答？"
        case .ready: return "可以开练了"
        }
    }

    public var body: String {
        switch self {
        case .welcome:
            return "这个工具替你打理练习前后的杂事：想今天练什么、输考官提示词、"
                + "把复盘和错题归档、记住上次的毛病。说英语的部分还是你自己来。\n"
                + "接下来三步，一分钟就能弄完。"
        case .environment:
            return "本工具靠系统的「辅助功能」权限替你操作 ChatGPT：新建会话、点开语音、"
                + "把考官提示词发过去、练完取回复盘。它不读你别的应用，也不上传任何东西。\n"
                + "你可以先跳过。跳过之后运行在半自动模式：提示词要你自己粘贴，复盘要你自己按 ⌘C，"
                + "其余功能照常。随时可以回到「关于」页重新开启。"
        case .questionBank:
            return "本工具不内置商业题库，只带原创样例——你的题库由你自己导入。\n"
                + "支持 CSV、JSON 和文字版 PDF（雅思季度题库通常是 PDF）。\n"
                + "现在没有也没关系，之后在「训练题库」页随时能导。"
        case .recordingChoice:
            return "开启后，练习时会用麦克风录下你的回答，练完能回听自己的发音、语调和卡顿。\n"
                + "这个开关默认关闭。录音只存在本机的数据目录里，不上传，随时可以单条删除。\n"
                + "只录你自己的声音，不录 ChatGPT——考官问了什么由逐字稿给文字。"
        case .ready:
            return "首页已经给你排好今天练什么了，点「开始」就行。\n"
                + "练完会自动归档复盘、错题、词汇和下次的重点目标，你只要关掉窗口。"
        }
    }

    public var primaryActionTitle: String {
        switch self {
        case .welcome: return "开始设置"
        case .environment: return "打开系统设置去授权"
        case .questionBank: return "现在导入题库…"
        case .recordingChoice: return "保持关闭"
        case .ready: return "开始使用"
        }
    }

    /// welcome / ready 只是叙述，没有可跳过的东西；
    /// recordingChoice 本身就是一个二选一（保持关闭也是一种选择），给「跳过」反而含糊。
    public var canSkip: Bool {
        switch self {
        case .environment, .questionBank: return true
        case .welcome, .recordingChoice, .ready: return false
        }
    }
}

public enum OnboardingFlow {
    /// 引导内容大改时把它加 1，老用户会再看一次。
    /// 不留这个口子的话，改了引导也没人看得到。
    public static let currentVersion = 1

    public static func steps(permission: PermissionState, questionCount: Int,
                             hasCompletedBefore: Bool) -> [OnboardingStep] {
        guard hasCompletedBefore else {
            var steps: [OnboardingStep] = [.welcome, .environment]
            // 题库已经有题（多半是把数据目录拷过来的），就别再让他导一次——
            // 那会让人怀疑自己的数据没拷成功。
            if questionCount == 0 { steps.append(.questionBank) }
            steps.append(.recordingChoice)
            steps.append(.ready)
            return steps
        }
        // 已经走过引导的人，只有一种情况会再看到它：环境不就绪。
        // 最典型的就是换了一台电脑——数据拷过来了，但辅助功能授权是本机 TCC 的，必须重给。
        return permission == .ready ? [] : [.environment]
    }

    public static func shouldPresent(permission: PermissionState, questionCount: Int,
                                     hasCompletedBefore: Bool) -> Bool {
        !steps(permission: permission, questionCount: questionCount,
               hasCompletedBefore: hasCompletedBefore).isEmpty
    }
}
```

`Sources/IELTSCoachUI/Onboarding/OnboardingProgressStore.swift`：

```swift
import Foundation

/// 「引导看过没有」存在哪里。
///
/// **刻意存本机 UserDefaults，不进数据目录。**
/// 数据目录里只放换机器时要跟着走的东西，而这个标记恰恰不该跟着走：
/// 换了机器，辅助功能授权是本机 TCC 的，必须重给一次，引导应该再出现。
/// 把它写进 state.json 的话，新机器上的用户一进来就没有引导，
/// 直接撞上一堵「点开始练习却报错」的墙——而他手上的数据看起来一切正常。
public protocol OnboardingProgressStore: AnyObject {
    /// 从没走完过就返回 0。
    func completedVersion() -> Int
    func markCompleted(version: Int)
}

public final class UserDefaultsOnboardingStore: OnboardingProgressStore {
    public static let key = "com.ielts.speakingcoach.onboardingCompletedVersion"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func completedVersion() -> Int { defaults.integer(forKey: Self.key) }

    public func markCompleted(version: Int) { defaults.set(version, forKey: Self.key) }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter OnboardingFlowTests`
Expected: PASS（14 个测试）

- [ ] **Step 5: 突变验证（两条）**

**突变 A：** 把 `steps(...)` 最后一行
`return permission == .ready ? [] : [.environment]`
改成
`return []`
重跑：`testReturningUserWithoutAccessibilitySeesOnlyTheEnvironmentStep`、`testReturningUserWithoutChatGPTSeesTheEnvironmentStep`、`testReturningUserWithAnUnrecognizedFailureSeesTheEnvironmentStep` 三条必须同时变红。

**这条守的正是成品标准第 10 条真正落地的那一半**：把数据目录拷到新机器之后，题库和记录都在、界面一切正常，唯独辅助功能授权是本机的、必须重给。少了这一步，用户会对着一个「看起来好好的、点开始练习却报错」的 App 发呆。

**突变 B：** 把 `if questionCount == 0 { steps.append(.questionBank) }` 改成 `steps.append(.questionBank)`。
重跑：`testFreshInstallSkipsTheImportStepWhenQuestionsAreAlreadyThere` 必须变红。

改回后确认全绿，把输出写进报告。

- [ ] **Step 6: 写引导界面并接进 RootView**

`WelcomeFlowView` 只给验收要求：

| 必须做到 | 判据 |
|---|---|
| 按 `OnboardingFlow.steps(...)` 逐步走 | 有「上一步 / 下一步」，显示 `第 N 步 / 共 M 步` |
| 每步显示 `title` / `body` / 主按钮 `primaryActionTitle` | 逐字来自 `OnboardingStep`，不得在视图里另写一套文案 |
| `canSkip == true` 的步骤才显示「先跳过」 | 由 `step.canSkip` 决定，不要写死 |
| `.environment` 这一步 | **复用 `PermissionGateView`**（Phase 3 Task 2），把 `AppState.permission` 与 `permissionMessages` 传给它。不要另写一套说同一件事的界面 |
| `.environment` 的主按钮 | 调 `NSWorkspace.shared.open(PermissionStatus.systemSettingsURL)`；旁边要有「重新检查」调 `app.recheckPermission()`，检查到就绪后自动前进一步 |
| `.questionBank` 的主按钮 | 走 `NSOpenPanel`，复用「训练题库」页已有的导入逻辑（含 PDF）。导入完成后显示导入了几题与全部 warnings |
| `.recordingChoice` | 一个开关，默认关。**开启时必须完整走 Phase 5 那条路**，见下面那段补注；保持关闭时 `settings` 一个字节都不动 |
| 走完最后一步或跳过 | 调 `store.markCompleted(version: OnboardingFlow.currentVersion)`，然后进主界面 |
| 全部走设计令牌与 Phase 3 的组件 | 视图里不得出现字面颜色、字号、圆角 |
| 尊重「减弱动态效果」 | `@Environment(\.accessibilityReduceMotion)` 打开时禁用步骤间的过渡动画 |

> ### ⚠️ `.recordingChoice` 不许自己写一遍开关逻辑（2026-08-06 跨阶段复审补入）
>
> 初稿写的是「用 `StateStore.mutate` 写 `settings.recordingEnabled = true` 与
> `settings.recordingConsentAt = ISO8601DateFormatter().string(from: Date())`」。
> **这么做会造出 Phase 5 明令禁止的那个状态**：开关显示「开」、但麦克风权限根本没申请过，
> 于是用户练完一场发现什么都没录，而且完全无从查起。Phase 5 计划开头那节
> 「这个阶段有一件事任何自动化都绕不过去」第 2 条原话是
> 「权限没拿到时，界面上的开关**必须停在「关」**」。
>
> 另外它也绕开了 `RecordingConsent.enable`，等于把「同意时间戳怎么记」这条规则实现了两遍。
>
> **正确做法**（与 Phase 5 Task 8 的 `RecordingSettingsViewModel.setEnabled(_:)` 完全一致）：
>
> 1. 先问权限：`MicrophoneAuthorizing.currentStatus()`；`.notDetermined` 时 `await requestAccess()`
> 2. 拿到 `.granted` 才写盘，且写盘走
>    `try store.mutate { $0.settings = RecordingConsent.enable($0.settings, at: 时间戳) }`
> 3. 没拿到 `.granted` → **开关弹回「关」**，并把 `MicrophonePermissionState.guidance` 显示出来
>
> **更省事也更不容易出错的做法：直接把 Phase 5 的 `RecordingSettingsView` 嵌进这一步**，
> 它已经把上面三条连同占用提示一起做完了。这样引导页与设置窗口永远说同一句话。
>
> 若 Phase 5 尚未交付（`ls Sources/IELTSCoachCore/Recording/` 为空），
> **这一步整步跳过，不要用初稿那种写法顶上**——录音开关宁可暂时没有，也不能是假的。

`RootView` 的改动：把原来「`app.permission != .ready && !app.permissionSkipped` 就显示 `PermissionGateView`」这个顶层分支，换成

```
if OnboardingFlow.shouldPresent(permission: app.permission,
                                questionCount: app.state.questions.count,
                                hasCompletedBefore: store.completedVersion() >= OnboardingFlow.currentVersion)
   && !dismissedThisLaunch {
    WelcomeFlowView(...)
} else {
    NavigationSplitView { ... }
}
```

`dismissedThisLaunch` 是一个 `@State` 布尔量，作用是「这次启动里已经跳过了，别在权限还没给的情况下又弹回来」——**跳过之后本次启动内不再打扰，下次启动若权限仍缺会再问一次**，理由见本任务开头第二条。

- [ ] **Step 7: 人工验证引导**

```bash
defaults delete com.ielts.speakingcoach 2>/dev/null || true
./scripts/build-app.sh && open ".build/IELTS Speaking Coach.app"
```

`defaults delete` 把「看过引导」的标记清掉，等价于全新安装。

Expected:
1. 出现欢迎页，能一路走到「可以开练了」
2. 「环境」那一步点「打开系统设置」真的跳到 隐私与安全性 › 辅助功能
3. 「先跳过」能直接进主界面，且主界面可用（半自动模式）
4. 走完之后重新打开 App，**不再出现引导**
5. 到系统设置里把本 App 的辅助功能勾去掉，再打开 App：**只出现「环境」一步**，不是从欢迎页从头来

第 5 条就是换机器场景的本地等价物，务必真做一次。

- [ ] **Step 8: 提交**

```bash
git add Sources/IELTSCoachUI/Onboarding/ Sources/IELTSCoachUI/RootView.swift Tests/IELTSCoachUITests/OnboardingFlowTests.swift
git commit -m "feat(ui): 首次使用引导"
```

---

## Task 9: 分发包与公证脚本（本期不执行公证）

**Files:**
- Create: `packaging/open-instructions.txt`
- Create: `scripts/package-app.sh`
- Create: `scripts/notarize.sh`
- Create: `Tests/PackagingTests/NotarizeScriptTests.swift`
- Create: `Tests/PackagingTests/PackagingContractTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `scripts/build-app.sh`（认 `IELTS_SIGN_IDENTITY` / `IELTS_SIGNATURE_CHANNEL`）、`packaging/IELTSCoach.entitlements`、`packaging/expected-designated-requirement.txt`
- Produces:
  - `.build/dist/IELTS Speaking Coach.zip` + `.build/dist/如何打开.txt`
  - `scripts/notarize.sh`：`--dry-run`（默认）/ `--execute` / `--help`
  - 测试 target `PackagingTests`（**不依赖任何产品代码**）

**本期不购买 Developer ID，也不实际执行公证**（设计文档第 10 节）。这个脚本存在的意义是：把「将来要怎么做」写成**可以直接跑、而且有测试守着**的东西，而不是写成一段没人验证过的文档。文档会烂，能跑的脚本不会。

### 换 Developer ID 会让辅助功能授权失效一次——这必须写在脚本里

Developer ID 是另一张证书，「指定要求」里的 `certificate leaf = H"…"` 会跟着变。系统会把重签后的 App 当成另一个程序，本机的辅助功能授权当场失效，得回系统设置重新勾一次，并且要把新的指定要求写进 `packaging/expected-designated-requirement.txt`（否则 `build-app.sh` 会一直拦着不让打包）。

**这一次失效躲不掉，但它只发生一次，而且只影响开发者自己这台机器**——拿到公证版本的其他人本来就要自己授权一次。脚本必须在动手前把这段话打出来。

- [ ] **Step 1: 写「如何打开」说明**

`packaging/open-instructions.txt`：

```
IELTS Speaking Coach —— 第一次打开怎么弄

1. 把「IELTS Speaking Coach.app」拖进「应用程序」文件夹。

2. 双击它。系统大概率会说「无法打开，因为 Apple 无法验证其是否包含恶意软件」。

   发生了什么：这个 App 是用作者本机的证书签名的，没有购买 Apple 开发者账号
   做「公证」。Apple 对所有未公证的 App 都会这么提示，与它本身是否安全无关。

   下一步：打开「系统设置」›「隐私与安全性」，往下翻到「安全性」一节，
   会看到一行「已阻止使用 IELTS Speaking Coach」，点它旁边的「仍要打开」，
   再确认一次即可。

   （旧版 macOS 也可以在「应用程序」里按住 Control 点它 →「打开」→「打开」。
     macOS 15 起 Apple 收紧了这条路径，若找不到这个入口，就走上面的系统设置。）

3. 第一次打开会请你授予「辅助功能」权限。

   它用来替你操作 ChatGPT：新建会话、点开语音、把考官提示词发过去、
   练完取回复盘。不读你别的应用，也不上传任何东西。
   你可以先跳过，跳过后运行在半自动模式：提示词自己粘、复盘自己按 ⌘C。

4. 需要先装好新版 ChatGPT 桌面应用（不是 ChatGPT Classic，Classic 没有语音）。

5. 你的数据存在这里：
   ~/Library/Application Support/IELTS Speaking Coach/
   换电脑时把这个文件夹整个拷过去就能接着用。备份就是拷贝它。

6. 卸载：把 App 拖进废纸篓即可。上面那个数据文件夹要不要留，你自己决定。
```

- [ ] **Step 2: 写 `scripts/package-app.sh`**

```bash
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
```

- [ ] **Step 3: 写 `scripts/notarize.sh`**

```bash
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
    sed -n '3,20p' "$0"
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
```

- [ ] **Step 4: 加 `PackagingTests` target**

`Package.swift` 的 `targets:` 数组末尾加一行：

```swift
        .testTarget(name: "PackagingTests")
```

它**不依赖任何产品代码**——守的是脚本与工程配置的契约，不是 Swift 逻辑。

- [ ] **Step 5: 写失败的测试**

`Tests/PackagingTests/NotarizeScriptTests.swift`：

```swift
import XCTest

/// 守打包脚本的契约。不依赖任何产品代码。
final class NotarizeScriptTests: XCTestCase {

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)     // Tests/PackagingTests/NotarizeScriptTests.swift
            .deletingLastPathComponent()     // Tests/PackagingTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // 仓库根
    }

    private struct Result { let status: Int32; let output: String }

    /// 用干净的环境跑脚本。
    /// 不继承开发机上可能已经设好的 IELTS_* 变量——否则这些测试在
    /// 「配好了证书的机器」和「没配的机器」上会得出不同结论，那种测试等于没有。
    private func run(_ script: String, _ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.repositoryRoot.appending(path: script).path] + arguments
        process.currentDirectoryURL = Self.repositoryRoot
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                               "HOME": NSHomeDirectory()]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // 必须先读完再 wait，否则管道写满会死锁。
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus,
                      output: String(data: data, encoding: .utf8) ?? "")
    }

    func testDryRunSucceedsWithoutAnyDeveloperIDAtAll() throws {
        // 本期不买 Developer ID。dry-run 必须在这台什么都没配的机器上跑得通，
        // 否则这个「预留」就是一段没人验证过的死文档。
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        XCTAssertEqual(result.status, 0, "dry-run 应该退出 0：\n\(result.output)")
    }

    func testDefaultModeIsDryRunSoItNeverDoesAnythingByAccident() throws {
        let result = try run("scripts/notarize.sh", [])
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("一条都没有执行"),
                      "不带参数时必须是 dry-run，且要说清什么都没做：\n\(result.output)")
    }

    func testDryRunSpellsOutEveryStepOfTheProcedure() throws {
        // 这五步就是「将来怎么做」的全部内容。少一步，将来那天就要现查文档。
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        for needle in ["codesign", "--options runtime", "--entitlements",
                       "ditto -c -k", "notarytool submit", "stapler staple", "spctl"] {
            XCTAssertTrue(result.output.contains(needle),
                          "公证流程里缺了「\(needle)」：\n\(result.output)")
        }
    }

    func testDryRunWarnsThatSwitchingCertificateBreaksTheAccessibilityGrant() throws {
        // 这是换证书那天最容易被忘、后果又最烦人的一件事。
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        XCTAssertTrue(result.output.contains("辅助功能"),
                      "没警告辅助功能授权会失效：\n\(result.output)")
        XCTAssertTrue(result.output.contains("expected-designated-requirement.txt"),
                      "没提醒要同步更新签名基线，那会让 build-app.sh 从此一直报错：\n\(result.output)")
    }

    func testEveryMissingPreconditionComesWithANextStep() throws {
        let result = try run("scripts/notarize.sh", ["--dry-run"])
        XCTAssertTrue(result.output.contains("下一步"),
                      "缺东西时必须说下一步做什么：\n\(result.output)")
        XCTAssertTrue(result.output.contains("Developer ID"),
                      "至少要点名缺的是 Developer ID：\n\(result.output)")
    }

    func testExecuteWithoutCredentialsFailsLoudlyInsteadOfSilentlySkipping() throws {
        // 静默跳过是本项目最危险的失败形态：以为公证了，其实什么都没发生。
        let result = try run("scripts/notarize.sh", ["--execute"])
        XCTAssertNotEqual(result.status, 0,
                          "没有凭据却退出 0，等于静默跳过公证：\n\(result.output)")
        XCTAssertTrue(result.output.contains("不执行公证"),
                      "要说清它没做什么：\n\(result.output)")
    }

    func testUnknownArgumentIsRejectedRatherThanIgnored() throws {
        // 参数打错被忽略，用户会以为自己 --execute 了。
        let result = try run("scripts/notarize.sh", ["--yolo"])
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("下一步"))
    }
}
```

`Tests/PackagingTests/PackagingContractTests.swift`：

```swift
import XCTest

final class PackagingContractTests: XCTestCase {

    private var root: URL { NotarizeScriptTests.repositoryRoot }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
    }

    func testAllPackagingScriptsAreExecutable() {
        // Task 10 会往这个列表里补 verify-portability.sh。
        for script in ["build-app.sh", "verify-signature-stability.sh",
                       "package-app.sh", "notarize.sh", "make-icon.sh"] {
            let path = root.appending(path: "scripts/\(script)").path
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path),
                          "scripts/\(script) 没有可执行位——别人 clone 下来会直接跑不了")
        }
    }

    func testEntitlementsContainTheMicrophoneAndNothingElseUnjustified() throws {
        let entitlements = try text(at: "packaging/IELTSCoach.entitlements")
        XCTAssertTrue(entitlements.contains("com.apple.security.device.audio-input"),
                      "缺了麦克风 entitlement，Hardened Runtime 下录音会被系统直接拒掉")

        // 下面这几条是「Hardened Runtime 报错时最容易被顺手粘上来」的。
        // 每一条都会实打实削弱 Hardened Runtime，而本项目一条都不需要
        // （实测 otool -L 显示只链接系统库；沙盒会让辅助功能驱动整个失效）。
        for forbidden in ["com.apple.security.app-sandbox",
                          "com.apple.security.cs.disable-library-validation",
                          "com.apple.security.cs.allow-unsigned-executable-memory",
                          "com.apple.security.cs.disable-executable-page-protection",
                          "com.apple.security.cs.allow-dyld-environment-variables"] {
            XCTAssertFalse(entitlements.contains(forbidden),
                           "多了一条不该有的 entitlement：\(forbidden)。"
                           + "若它真的必要，先在计划里写明为什么，再改这条测试。")
        }
    }

    func testDesignatedRequirementBaselineIsRecordedAndNotAdHoc() throws {
        let baseline = try text(at: "packaging/expected-designated-requirement.txt")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertTrue(baseline.hasPrefix("designated =>"),
                      "基线文件格式不对，应当就是 codesign -d -r- 输出的那一行：\(baseline)")
        XCTAssertTrue(baseline.contains("identifier \"com.ielts.speakingcoach\""),
                      "基线里的 bundle id 变了。辅助功能授权绑的就是它，任何阶段都不得更改。")
        XCTAssertTrue(baseline.contains("certificate leaf"),
                      "基线里没有证书条件，说明用的不是固定证书。")
        XCTAssertFalse(baseline.lowercased().contains("cdhash"),
                       "基线是 cdhash 形式，说明用了 ad-hoc 签名——"
                       + "cdhash 每次编译都变，用户的辅助功能授权会反复失效。")
    }

    func testProjectStillHasNoThirdPartyDependencies() throws {
        // 关于页的致谢里写着「第三方依赖：没有」。加了依赖却不改那句话，
        // 就变成了一句假话，而且没人会注意到。
        let manifest = try text(at: "Package.swift")
        XCTAssertFalse(manifest.contains(".package("),
                       "工程新增了第三方依赖。下一步：要么撤掉它，"
                       + "要么把它加进 AboutViewModel.acknowledgements 并改掉「没有第三方依赖」那句话。")
    }

    func testOpenInstructionsCoverGatekeeperAndTheDataDirectory() throws {
        // 这份说明是随包发出去的，收件人只有它。少一条他就卡住了。
        let instructions = try text(at: "packaging/open-instructions.txt")
        XCTAssertTrue(instructions.contains("仍要打开"), "没写怎么绕过 Gatekeeper")
        XCTAssertTrue(instructions.contains("辅助功能"), "没写要授予什么权限")
        XCTAssertTrue(instructions.contains("Application Support/IELTS Speaking Coach"),
                      "没写数据存在哪儿——换电脑和备份都靠它")
    }
}
```

- [ ] **Step 6: 运行，确认失败**

Run: `swift test --filter PackagingTests`
Expected: 失败 —— 脚本还没 `chmod +x`、或 `PackagingTests` target 还没建好

- [ ] **Step 7: 让它们通过**

```bash
chmod +x scripts/package-app.sh scripts/notarize.sh
```

Run: `swift test --filter PackagingTests`
Expected: PASS（11 个测试）

Run: `./scripts/package-app.sh`
Expected: 产出 `.build/dist/IELTS Speaking Coach.zip` 与 `如何打开.txt`，自检通过，打印大小与 SHA256

Run: `./scripts/notarize.sh`
Expected: 打印全部五步，前置条件里 Developer ID 与凭据显示 ⚠️（本期就是没有），退出 0

Run: `./scripts/notarize.sh --execute; echo "exit=$?"`
Expected: 打印 `❌ 前置条件没满足，不执行公证。`，`exit=1`

- [ ] **Step 8: 突变验证（两条）**

**突变 A：** 把 `notarize.sh` 里 `--execute` 分支的
`if [[ $MISSING -ne 0 ]]; then … exit 1; fi`
整段删掉，重跑 `swift test --filter NotarizeScriptTests`。
Expected: `testExecuteWithoutCredentialsFailsLoudlyInsteadOfSilentlySkipping` 变红（脚本会带着空的 `$DEV_ID` 往下走）。改回后确认全绿。

**这条守的是本项目最危险的失败形态**：以为公证了，其实什么都没发生，直到把包发给别人才知道。

**突变 B：** 往 `packaging/IELTSCoach.entitlements` 里加一条
`<key>com.apple.security.cs.disable-library-validation</key><true/>`，
重跑 `swift test --filter PackagingContractTests`。
Expected: `testEntitlementsContainTheMicrophoneAndNothingElseUnjustified` 变红。删掉后确认全绿。

**这条守的是「Hardened Runtime 一报错就顺手粘一条 entitlement 上去」**——那是网上搜到的第一条建议，而本项目实测过 `otool -L` 只链接系统库，一条都不需要。

- [ ] **Step 9: 提交**

```bash
git add Package.swift packaging/open-instructions.txt scripts/package-app.sh scripts/notarize.sh Tests/PackagingTests/
git commit -m "feat(packaging): 分发包与公证脚本（预留，不执行）"
```

---

## Task 10: 「换了一台电脑」的自动化验证

**Files:**
- Create: `scripts/verify-portability.sh`
- Modify: `Tests/PackagingTests/PackagingContractTests.swift`

**Interfaces:**
- Consumes: `./.build/debug/coach portability`（Task 4）、`./.build/debug/coach questions list`、环境变量 `IELTS_SPEAKING_DATA_DIR`（`DataDirectory.resolve()` 认它）
- Produces: `scripts/verify-portability.sh`，退出 0 表示「拷过去能接着用，且这个结论不是蒙的」

**这一条兑现成品标准第 10 条。** 手工去另一台电脑上试一次是必要的（Task 11 会做），但那件事一年做不了几次；每天都在改代码的是这台机器，所以还需要一个能天天跑的版本。

**脚本的关键设计有两处，缺任何一处这个验证都是假的：**

1. **拷完之后把「原来那台机器」整个删掉。** 不删的话，就算代码里存的是绝对路径，它照样能读到原目录的文件，验证会通过——而真换机器时那些路径根本不存在。**这一步是这个脚本里唯一真正制造压力的地方。**
2. **必须带一个负例。** 造一份故意存了绝对路径的数据目录，断言 `coach portability` 一定要退出非零。没有负例的话，一个永远返回「没问题」的实现也能让脚本全绿。

- [ ] **Step 1: 写脚本**

`scripts/verify-portability.sh`：

```bash
#!/bin/bash
set -euo pipefail

# 验证「把数据目录拷到另一台电脑就能接着用」（成品标准第 10 条）。
#
# 关键设计有两处，缺任何一处这个验证都是假的：
#   1. 拷完之后把「原来那台机器」的目录整个删掉。不删的话，就算代码里存的是
#      绝对路径也能读到原目录，验证照样通过——而真换机器时那些路径根本不存在。
#   2. 必须带一个负例（故意存绝对路径的数据目录），断言检查一定要报错。
#      没有负例的话，一个永远返回「没问题」的实现也能让这个脚本全绿。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COACH="$ROOT/.build/debug/coach"

if [[ ! -x "$COACH" ]]; then
    echo "❌ 找不到 $COACH"
    echo "   下一步：先跑 swift build，再跑这个脚本。"
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# $1 = 目录，$2 = 写进 reportPath 的内容
make_fixture() {
    local dir="$1" report_path="$2"
    mkdir -p "$dir/reports" "$dir/recordings"
    printf '{"must_correct":[]}' > "$dir/reports/s1.json"
    printf 'fake-audio'          > "$dir/recordings/s1.m4a"
    cat > "$dir/state.json" <<STATE
{
  "schemaVersion": 3,
  "learner": { "displayName": "", "createdAt": "2026-08-06T00:00:00Z" },
  "currentSession": null,
  "sessions": [
    {
      "id": "s1",
      "questionId": "q1",
      "focusPart": "Part 1",
      "startedAt": "2026-08-06T00:00:00Z",
      "endedAt": "2026-08-06T00:10:00Z",
      "goal": "",
      "transcript": [],
      "reportPath": "$report_path",
      "recordingPath": "recordings/s1.m4a"
    }
  ],
  "targets": [],
  "issues": [],
  "vocabulary": [],
  "plan": null,
  "questions": [
    { "id": "q1", "part": 1, "topic": "Home", "prompt": "Do you live in a house or a flat?" }
  ],
  "questionSources": [],
  "settings": { "recordingEnabled": false, "recordingConsentAt": "" },
  "questionCursor": { "part1": 0, "part2": 0, "part3": 0 }
}
STATE
}

echo "▶︎ 正例：造一份全用相对路径的数据目录…"
ORIGINAL="$WORK/machine-a"
COPY="$WORK/machine-b"
make_fixture "$ORIGINAL" "reports/s1.json"

echo "▶︎ 拷到「另一台电脑」，然后把原来那台整个删掉…"
cp -R "$ORIGINAL" "$COPY"
rm -rf "$ORIGINAL"

echo "▶︎ 在「另一台电脑」上检查…"
if ! IELTS_SPEAKING_DATA_DIR="$COPY" "$COACH" portability; then
    echo "❌ 拷过去之后检查没通过。"
    echo "   发生了什么：数据目录里有依赖原机器的东西，换电脑就断。"
    echo "   下一步：看上面每一条给出的位置与提示，逐条修写入这些字段的代码。"
    exit 1
fi

echo "▶︎ 确认题库真的读得到…"
if ! IELTS_SPEAKING_DATA_DIR="$COPY" "$COACH" questions list | grep -qF "[q1]"; then
    echo "❌ 拷过去之后读不到题库。"
    echo "   下一步：确认 state.json 跟着拷过来了，且 DataDirectory.resolve() 认 IELTS_SPEAKING_DATA_DIR。"
    exit 1
fi

echo "▶︎ 确认复盘文件真的跟过来了…"
if [[ ! -f "$COPY/reports/s1.json" ]]; then
    echo "❌ reports/ 没跟着过来。下一步：检查这个脚本的 cp -R 是不是漏了子目录。"
    exit 1
fi

echo
echo "▶︎ 负例：造一份故意存绝对路径的数据目录，检查必须把它揪出来…"
BAD="$WORK/machine-bad"
make_fixture "$BAD" "$WORK/somewhere-else/reports/s1.json"
if IELTS_SPEAKING_DATA_DIR="$BAD" "$COACH" portability > "$WORK/bad.log" 2>&1; then
    echo "❌ 负例没有被检出。"
    echo "   发生了什么：数据目录里存着绝对路径，检查却说「没问题」——"
    echo "   这说明上面那个正例的绿灯毫无意义，它对任何实现都会亮。"
    echo "   下一步：检查 DataPortabilityAudit.audit 是不是被改成了永远返回空。"
    cat "$WORK/bad.log"
    exit 1
fi
if ! grep -q "下一步" "$WORK/bad.log"; then
    echo "❌ 负例报出来了，但没告诉用户下一步做什么。"
    cat "$WORK/bad.log"
    exit 1
fi

echo
echo "✅ 数据目录可以整个拷到另一台电脑接着用（成品标准第 10 条）。"
echo "   正例：删掉原目录后仍然读得到题库与复盘。"
echo "   负例：存了绝对路径的目录被正确揪出，并给出了下一步。"
```

- [ ] **Step 2: 跑一次，确认通过**

Run: `chmod +x scripts/verify-portability.sh && swift build && ./scripts/verify-portability.sh`
Expected: 正例与负例都通过，最后打印 `✅ 数据目录可以整个拷到另一台电脑接着用…`

- [ ] **Step 3: 把它加进可执行位检查**

在 `Tests/PackagingTests/PackagingContractTests.swift` 的 `testAllPackagingScriptsAreExecutable` 里，把 `"verify-portability.sh"` 加进列表，并删掉那条 `// Task 10 会往这个列表里补…` 的注释。

Run: `swift test --filter PackagingContractTests`
Expected: PASS

- [ ] **Step 4: 突变验证（两条）**

**突变 A —— 让「换机器」变成假的：**
把 `verify-portability.sh` 里的 `rm -rf "$ORIGINAL"` 删掉，然后把 `make_fixture "$ORIGINAL" "reports/s1.json"` 的第二个参数改成 `"$ORIGINAL/reports/s1.json"`（绝对路径），重跑。
Expected: 正例仍会被 `coach portability` 判为失败并退出 1（因为审计看的是路径写法，不是文件在不在）。**改回后**再验一次真正的对照：把审计里的绝对路径规则临时去掉（见突变 B），正例就会通过——这说明 `rm -rf` 那一步配合负例才是真正的压力来源。

**突变 B —— 让审计永远说没问题：**
把 `DataPortabilityAudit.audit(state:)` 的函数体改成 `return []`，重跑 `./scripts/verify-portability.sh`。
Expected: 停在 `❌ 负例没有被检出。`，退出 1。改回后重跑必须通过。

**这条守的是「这个脚本不是在自我恭维」**——没有负例的话，一个什么都不检查的实现照样能让它全绿，而那正是本项目消灭过 15 次的那种测试。

把两次输出写进报告。

- [ ] **Step 5: 提交**

```bash
git add scripts/verify-portability.sh Tests/PackagingTests/PackagingContractTests.swift
git commit -m "feat(packaging): 数据目录搬迁的自动化验证"
```

---

## Task 11: 真机验收（人工，不可由子代理代劳）

**Files:** 无代码改动。产出 `docs/phase10-acceptance.md`

前面所有测试证明的是「逻辑对」和「脚本会拦」。下面这些只有人能判断，而且其中三项**必须在第二台电脑上做**。

- [ ] **Step 1: 全量回归**

Run: `time swift test`
Expected: 全绿，总耗时 2 秒以内（Phase 3 Task 10 定的预算）。若 `PackagingTests` 把总时长顶到 2 秒以上，记录实际数字并说明是哪几条测试占的——不要为了好看去删断言。

Run: `./scripts/verify-portability.sh`
Expected: 正例与负例都通过

- [ ] **Step 2: 签名稳定性（本阶段最关键的一条）**

Run: `./scripts/verify-signature-stability.sh`
Expected: `✅ 连打两次，「指定要求」完全一致，且与基线相符`

然后**不重新授权**直接打开 App：

Run: `open ".build/IELTS Speaking Coach.app"`
Expected: 仍然显示「环境就绪」，不再要求去系统设置勾选。

**若又要求重新授权，立刻停下并报告。** 那说明加了 Hardened Runtime 之后签名不稳定了，整个打包方案要重做——这一条一票否决，后面的验收都没有意义。

- [ ] **Step 3: 关于页逐项核对**

| 看什么 | 判据 |
|---|---|
| 版本 | 与 `Info.plist` 里的 `CFBundleShortVersionString`、`CFBundleVersion` 一致 |
| 提交 | 与 `git rev-parse --short HEAD` 一致 |
| 标识 | `com.ielts.speakingcoach` |
| 签名 | 「自签名（未经 Apple 公证）」，且说清了别人怎么打开 |
| 辅助功能 | 与实际状态一致；去系统设置里取消勾选后点「重新检查」，这一行要跟着变 |
| 数据目录 | 路径正确，「在访达中显示」能打开对的文件夹 |
| 数据可搬迁检查 | 用你**真实的**数据目录跑，看它说什么。**若报了问题，把每一条都记下来——那是真 bug，不是审计写错了** |
| 致谢与许可 | 逐条读一遍，有没有说得不准的地方 |
| 复制诊断信息 | `pbpaste` 之后逐行读，确认没有任何练习内容、姓名、逐字稿 |

- [ ] **Step 4: 首次引导（清标记重来一遍）**

```bash
defaults delete com.ielts.speakingcoach 2>/dev/null || true
open ".build/IELTS Speaking Coach.app"
```

| 看什么 | 判据 |
|---|---|
| 欢迎 → 环境 → 录音 → 完成 | 因为你的题库非空，**不该出现「导入题库」那一步** |
| 每一步的文案 | 找一个不懂技术的人读一遍，他知不知道要干什么 |
| 「先跳过」 | 点了能直接进主界面，且主界面可用 |
| 走完之后重开 App | 不再出现引导 |
| 去系统设置取消辅助功能勾选，重开 App | **只出现「环境」一步**，不是从欢迎页重来 |

最后一条是换机器场景的本地等价物，务必真做。

- [ ] **Step 5: 把 `.app` 给别人（成品标准之外，但这是本阶段的交付定义）**

```bash
./scripts/package-app.sh
```

然后在**另一台 Mac**（或另一个 macOS 用户账号）上：

1. 通过会打上隔离属性的方式传过去（AirDrop、邮件、下载链接都行；`cp` 到共享盘不会打隔离属性，那样测不出 Gatekeeper）
2. 解压、拖进「应用程序」、双击
3. 按「如何打开.txt」的步骤走一遍

| 看什么 | 判据 |
|---|---|
| 是否被 Gatekeeper 拦下 | 应该会（自签名未公证，实测 `spctl` 判定 rejected） |
| 按说明能不能打开 | **能。若说明里的路径在这台机器的系统版本上不存在，把实际路径记下来并改说明** |
| 打开后 | 出现首次引导，程序坞图标不是白纸 |
| 授予辅助功能后 | 显示「环境就绪」 |

- [ ] **Step 6: 数据目录换机器（成品标准第 10 条，必须真做）**

在第一台机器上：

```bash
cp -R ~/Library/Application\ Support/IELTS\ Speaking\ Coach ~/Desktop/coach-data-backup
```

把 `coach-data-backup` 拷到第二台机器的 `~/Library/Application Support/IELTS Speaking Coach`，打开 App。

| 看什么 | 判据 |
|---|---|
| 题库 | 题目数量与第一台一致 |
| 训练记录 | 条数一致，点开任意一条能看到题目与逐字稿 |
| 复盘报告 | 能打开，内容完整 |
| 录音 | 若开过录音，点播放能出声 |
| 错题本 / 词汇本 / 重训目标 | 数字与第一台一致 |
| 引导 | **只出现「环境」一步**（辅助功能要在这台机器上重给），不是从欢迎页重来 |

**任何一项对不上都要如实记下来，连同 `coach portability` 的输出一起。**

- [ ] **Step 7: 麦克风在 Hardened Runtime 下真的能用**

在关于页/设置里打开「保存我的回答录音」，看系统有没有弹出麦克风授权对话框，点「允许」，然后真的录一小段。

**这一步是 entitlement 唯一的真机判据。** 少了 `com.apple.security.device.audio-input`，Hardened Runtime 会直接拒掉麦克风，而单元测试和 `codesign` 自检都只能证明「entitlement 写进去了」，证明不了「系统认」。

- [ ] **Step 8: 界面验收（对照 `DESIGN-SYSTEM.md` 第 6 节）**

关于页与引导页逐条走那十条清单。其中三条最容易被忽略：

- 打开系统「减弱动态效果」后，引导页的步骤切换是否无动画且功能正常
- 系统文字调到最大时，关于页是否不截断、不重叠（致谢那几段最长，最容易出问题）
- 关于页里有没有出现字面颜色、字号、圆角（翻一遍源码确认，不靠目测）

- [ ] **Step 9: 记录并提交**

把每一项的实际结果写进 `docs/phase10-acceptance.md`，含截图或原文。**包括不好的部分**——「哪里让我不想用」这类信息只有使用者有（成品标准第 5 节）。

```bash
git add docs/phase10-acceptance.md
git commit -m "docs: Phase 10 真机验收结果"
```

---

## 需要用户参与的环节（任何自动化都绕不过去）

集中列在这里，避免零散打断。

| 环节 | 在哪一步 | 用户要做什么 |
|---|---|---|
| **确认许可条款** | Task 6 开工前 | 默认「保留所有权利，个人自用」。若想开源（MIT 之类），现在说，改 `LICENSE` 与 `AboutViewModel.licenseNotice` 两处即可 |
| **确认版本号** | Task 1 | 计划里定为 `1.0.0`。若想用别的，改 `build-app.sh` 里的 `APP_VERSION` 一处 |
| 授予辅助功能权限 | Task 1 Step 4、Task 11 | 系统设置 › 隐私与安全性 › 辅助功能，勾选本 App |
| 允许麦克风 | Task 11 Step 7 | 弹窗点「允许」 |
| **第二台 Mac（或第二个用户账号）** | Task 11 Step 5、6 | 这两条**必须**在另一台机器上做。Gatekeeper 与 TCC 都是按机器算的，本机自己测不出来 |
| 界面观感判断 | Task 11 Step 3、4、8 | 关于页与引导页读起来顺不顺、说得清不清楚 |
| 公证（**本期不做**） | 将来 | 加入 Apple Developer Program（按年付费）→ 申请 Developer ID Application 证书 → `xcrun notarytool store-credentials` 存凭据 → `./scripts/notarize.sh --execute`。脚本会在动手前把「辅助功能授权会失效一次」和「要更新签名基线」两件事打出来 |

---

## Phase 10 完成标准

- [ ] `swift test` 全绿；新增测试 60 条左右，且**每一条关键逻辑都做过突变验证**，输出写进了报告
- [ ] `./scripts/build-app.sh` 产出的包带 `flags=0x10000(runtime)` 与麦克风 entitlement，且四项自检全过
- [ ] `./scripts/verify-signature-stability.sh` 通过：**连打两次，`codesign -d -r-` 的 designated 完全一致，且两次 CDHash 不同**（证明比较不是空转）
- [ ] `packaging/expected-designated-requirement.txt` 已提交，内容形如 `designated => identifier "com.ielts.speakingcoach" and certificate leaf = H"…"`，**不含 cdhash**
- [ ] 加了 Hardened Runtime 与 entitlements 之后，**授权过一次，重新打包不需要再授权**（真机验证）
- [ ] `packaging/IELTSCoach.entitlements` 只有麦克风一条，且有测试拦着不让加别的
- [ ] 关于页可从苹果菜单打开，六行信息齐全，「在访达中显示」「复制诊断信息」「重新检查」都能用
- [ ] 诊断信息里**没有任何练习内容**（测试守着 + 人眼复核过一次）
- [ ] 首次引导走得通；已走过引导的人只在环境不就绪时再看到它
- [ ] `./scripts/package-app.sh` 产出的 zip 解压后签名仍然有效，附带的「如何打开.txt」能让别人真的打开它
- [ ] `./scripts/notarize.sh` 的 dry-run 在**没有 Developer ID 的机器上**跑得通，打印全部五步，并警告换证书会让辅助功能授权失效
- [ ] `./scripts/verify-portability.sh` 通过，**且带负例**
- [ ] **成品标准第 10 条真机验证：把 `~/Library/Application Support/IELTS Speaking Coach/` 拷到第二台电脑，题库、训练记录、复盘、录音、错题本、词汇本全都对得上，接着就能用**
- [ ] `DESIGN-SYSTEM.md` 第 6 节十条清单在关于页与引导页上全部通过
- [ ] `docs/phase10-acceptance.md` 写完，含不好的部分

达成后，整个项目的十二条成品标准应当全部可当场演示。**若还剩哪一条演示不出来，写进验收报告，那是下一步的输入，不是可以含糊过去的事。**
