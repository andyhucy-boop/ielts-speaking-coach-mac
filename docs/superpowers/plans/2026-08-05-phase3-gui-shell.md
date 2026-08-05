# Phase 3：图形界面骨架 + 三个页面

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付一个能双击打开的 `.app`，用户可以在界面里导入题库（含 PDF）、**点一下真的开始练习**、看复盘报告——全程不需要打开终端。

**Architecture:** 保持 SPM 单一构建系统。界面代码放在 library target `IELTSCoachUI` 里（可在 Xcode 打开 `Package.swift` 用 SwiftUI 预览，也可单元测试），可执行 target `IELTSCoachApp` 只负责组装 Scene。`.app` 包由 `scripts/build-app.sh` 组装并用固定的自签名证书签名——签名稳定是辅助功能授权不反复失效的前提。

**Tech Stack:** Swift 6.3.3、SPM、SwiftUI、XCTest、`codesign`。无第三方依赖。

## Global Constraints

- 最低系统版本 `macOS 14.0`
- **Bundle ID 固定为 `com.ielts.speakingcoach`，任何阶段都不得更改**——辅助功能授权绑定它
- `IELTSCoachCore` **只允许依赖 Foundation**
- `IELTSCoachUI` 可依赖 Core、ChatGPTBridge、SwiftUI
- 所有面向用户的错误信息必须是中文，且同时说明「发生了什么」和「下一步做什么」。**该标准已扩展到警告与界面文案**
- **禁止静默失败，禁止无限等待**
- 目标 ChatGPT 应用固定 `com.openai.codex`
- 测试用 XCTest
- 涉及外部应用能力的判断，一律以**在运行中的应用上实测**为准
- **界面必须遵循 `docs/superpowers/DESIGN-SYSTEM.md`。视图里不得出现字面颜色、字号、圆角——全部走令牌**

## 前置条件（已实测确认，2026-08-05）

| 事实 | 验证方式 |
|---|---|
| SwiftUI 可经 SPM 编译为可执行文件 | 建最小工程实测 `swift build` 通过 |
| 「界面放 library、瘦可执行文件」的拆法可行 | 同上，两个 target 分离编译通过 |
| 本机原无任何代码签名身份 | `security find-identity -v -p codesigning` → 0 valid |
| **已创建自签名证书 `IELTS Coach Dev`** | openssl 生成（EKU=codeSigning，10 年）→ PKCS12（须用 `-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1`，新版加密 macOS 读不了）→ `security import` |
| **自签名的指定要求跨重签稳定** | 重签两次均为 `identifier X and certificate leaf = H"4bffcd37..."`；对比 ad-hoc 为 `cdhash H"..."`，二进制一改就变 |

**为什么这条最要紧：** TCC（辅助功能授权）记的就是「指定要求」。ad-hoc 签名绑二进制指纹，每次编译都变，授权当场失效，用户得反复去系统设置重新勾。自签名绑「标识 + 证书」，编译多少次都不变。

`security find-identity` 仍显示 `0 valid identities` —— 因为该证书未被标记为受信任。**这不影响签名与 TCC**，已实测 `codesign -s "IELTS Coach Dev"` 成功。不加信任标记是刻意的，少动用户系统设置。

## File Structure

```
Sources/
├── IELTSCoachCore/          不变
├── ChatGPTBridge/           不变
├── coach/                   不变（命令行保留，与界面共存）
├── IELTSCoachUI/            新增 library：界面 + 视图模型
│   ├── AppState.swift               全局状态容器，持有 StateStore 与当前 CoachState
│   ├── Navigation.swift             侧边栏条目定义
│   ├── RootView.swift               NavigationSplitView 骨架
│   ├── Onboarding/
│   │   ├── PermissionGateView.swift 辅助功能授权引导
│   │   └── PermissionStatus.swift   权限状态判定（纯逻辑，可测）
│   ├── QuestionBank/
│   │   ├── QuestionBankViewModel.swift   筛选、分组、导入（纯逻辑，可测）
│   │   └── QuestionBankView.swift
│   ├── Review/
│   │   ├── ReviewReportViewModel.swift   把复盘 JSON 拆成可显示的分区（纯逻辑，可测）
│   │   └── ReviewReportView.swift
│   ├── Today/
│   │   ├── TodayViewModel.swift          四条路线、本周进度、最近练习（纯逻辑，可测）
│   │   └── TodayView.swift
│   ├── DesignSystem/
│   │   ├── Palette.swift                 颜色令牌
│   │   ├── Metrics.swift                 间距与圆角令牌
│   │   └── Components.swift              CoachCard / PrimaryActionCard / SectionHeader / EmptyStateView
│   └── Session/
│       ├── PracticeStage.swift           练习阶段与给用户看的文案（纯逻辑，可测）
│       ├── PracticeRunner.swift          把一场练习包成可观察的状态流（只依赖 CoachBridge，可测）
│       └── PracticeSheet.swift           练习进行中的界面
└── IELTSCoachApp/
    └── main.swift           只组装 Scene，不含业务逻辑
scripts/
└── build-app.sh             组装 .app 包 + 签名
Tests/
└── IELTSCoachUITests/       视图模型的单元测试
```

**为什么把视图模型单独分文件：** SwiftUI 的 `View` 几乎无法单元测试，但「把 `CoachState` 变成界面要显示的东西」这段逻辑完全可测。本项目已消灭 15 处空转测试，判据是「把被测逻辑改成空实现，测试会不会红」——只有视图模型分离出来，这个判据才立得住。`View` 本身靠人工验收。

### 关于本计划里 View 的写法

**视图模型给完整代码，`View` 只给要求不给代码——这是刻意的，不是省略。**

理由：布局是需要看着调的东西，把一份没人看过的 SwiftUI 布局逐字写进计划，实现者照抄之后大概率还要推翻重来，等于两遍工。所以每个 `View` 的任务里写明「必须显示什么、空状态说什么、失败时说什么」，具体怎么摆由实现者定，**由 Task 7 的令牌与组件约束，再由 Task 11 的人工验收把关**。

这与「禁止占位符」不冲突：占位符是「TBD、以后再说」，而这里给的是明确的验收标准。若实现者认为某处要求不清楚到无法动手，应当停下来问，而不是猜。

---

## Task 1: App target 骨架 + 打包脚本 + 签名

**Files:**
- Modify: `Package.swift`
- Create: `Sources/IELTSCoachUI/RootView.swift`
- Create: `Sources/IELTSCoachApp/main.swift`
- Create: `scripts/build-app.sh`
- Create: `Tests/IELTSCoachUITests/PlaceholderTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: 可执行的 `swift run IELTSCoachApp`；`scripts/build-app.sh` 产出已签名的 `.build/IELTS Speaking Coach.app`

- [ ] **Step 1: 更新 Package.swift**

```swift
    products: [
        .library(name: "IELTSCoachCore", targets: ["IELTSCoachCore"]),
        .library(name: "ChatGPTBridge", targets: ["ChatGPTBridge"]),
        .library(name: "IELTSCoachUI", targets: ["IELTSCoachUI"]),
        .executable(name: "axprobe", targets: ["axprobe"]),
        .executable(name: "coach", targets: ["coach"]),
        .executable(name: "IELTSCoachApp", targets: ["IELTSCoachApp"])
    ],
    targets: [
        .target(name: "IELTSCoachCore"),
        .target(name: "ChatGPTBridge", dependencies: ["IELTSCoachCore"]),
        .target(name: "IELTSCoachUI", dependencies: ["IELTSCoachCore", "ChatGPTBridge"]),
        .executableTarget(name: "axprobe", dependencies: ["ChatGPTBridge"]),
        .executableTarget(name: "coach", dependencies: ["IELTSCoachCore", "ChatGPTBridge"]),
        .executableTarget(name: "IELTSCoachApp", dependencies: ["IELTSCoachUI"]),
        .testTarget(name: "IELTSCoachCoreTests", dependencies: ["IELTSCoachCore"]),
        .testTarget(name: "ChatGPTBridgeTests", dependencies: ["ChatGPTBridge"]),
        .testTarget(name: "IELTSCoachUITests", dependencies: ["IELTSCoachUI"])
    ]
```

- [ ] **Step 2: 最小可跑的界面与入口**

`Sources/IELTSCoachUI/RootView.swift`：

```swift
import SwiftUI

public struct RootView: View {
    public init() {}

    public var body: some View {
        Text("IELTS Speaking Coach")
            .font(.title)
            .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview { RootView() }
```

`Sources/IELTSCoachApp/main.swift`：

```swift
import IELTSCoachUI
import SwiftUI

struct CoachApp: App {
    var body: some Scene {
        WindowGroup("IELTS Speaking Coach") { RootView() }
            .defaultSize(width: 1100, height: 720)
    }
}

CoachApp.main()
```

`Tests/IELTSCoachUITests/PlaceholderTests.swift`（SPM 要求已声明的 test target 必须有源码目录，否则会回退去扫包根并报 overlapping sources）：

```swift
// 占位文件，仅为满足 SPM 的 target 目录校验。Task 2 起会被真正的测试替换。
```

- [ ] **Step 3: 写打包脚本**

`scripts/build-app.sh`，需 `chmod +x`：

```bash
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

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>IELTSCoachApp</string>
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
```

- [ ] **Step 4: 验证**

Run: `swift build && swift test`
Expected: 构建通过，190 个既有测试全绿

Run: `chmod +x scripts/build-app.sh && ./scripts/build-app.sh`
Expected: 生成 `.build/IELTS Speaking Coach.app`，并打印 `designated => identifier com.ielts.speakingcoach and certificate leaf = H"..."`

Run: `./scripts/build-app.sh && codesign -d -r- ".build/IELTS Speaking Coach.app" 2>&1 | grep designated`
Expected: **连跑两次，两次的 designated 完全一致**。这一条是本任务的核心验收——不一致就说明签名不稳定，TCC 授权会反复失效。

Run: `open ".build/IELTS Speaking Coach.app"`
Expected: 弹出一个窗口显示 "IELTS Speaking Coach"

- [ ] **Step 5: 提交**

```bash
git add Package.swift Sources/IELTSCoachUI/ Sources/IELTSCoachApp/ Tests/IELTSCoachUITests/ scripts/
git commit -m "feat(app): SwiftUI 界面骨架与 .app 打包脚本"
```

---

## Task 2: 权限状态判定与授权引导页

**Files:**
- Create: `Sources/IELTSCoachUI/Onboarding/PermissionStatus.swift`
- Create: `Sources/IELTSCoachUI/Onboarding/PermissionGateView.swift`
- Create: `Tests/IELTSCoachUITests/PermissionStatusTests.swift`
- Delete: `Tests/IELTSCoachUITests/PlaceholderTests.swift`

**Interfaces:**
- Consumes: `AXDriver.preflight() -> BridgeReadiness`（字段 `ok: Bool`、`messages: [String]`）
- Produces:
  - `enum PermissionState { case ready, needsAccessibility, needsChatGPT, unknown }`
  - `PermissionStatus.evaluate(readiness:) -> PermissionState`
  - `PermissionStatus.systemSettingsURL: URL`
  - `PermissionGateView`

**为什么把判定单独拆出来：** `preflight()` 返回的是一组中文消息，界面要据此决定显示什么、引导去哪。这段映射是纯逻辑，可测；`View` 只负责摆布局。

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
import ChatGPTBridge
@testable import IELTSCoachUI

final class PermissionStatusTests: XCTestCase {
    func testReadyWhenPreflightOK() {
        let readiness = BridgeReadiness(ok: true, messages: ["✅ 环境就绪"])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .ready)
    }

    func testNeedsAccessibilityWhenMessageMentionsIt() {
        let readiness = BridgeReadiness(ok: false, messages: [
            "❌ 没有辅助功能权限，无法驱动 ChatGPT。下一步：系统设置 › 隐私与安全性 › 辅助功能…"
        ])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsAccessibility)
    }

    func testNeedsChatGPTWhenNotInstalled() {
        let readiness = BridgeReadiness(ok: false, messages: [
            "❌ 没找到 ChatGPT（新版桌面应用）。下一步：从 openai.com/chatgpt/download 安装。"
        ])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsChatGPT)
    }

    func testAccessibilityTakesPrecedenceWhenBothMissing() {
        // 两样都缺时先引导装 ChatGPT —— 没有目标应用，给了权限也没用
        let readiness = BridgeReadiness(ok: false, messages: [
            "❌ 没找到 ChatGPT（新版桌面应用）。下一步：从 openai.com/chatgpt/download 安装。",
            "❌ 没有辅助功能权限，无法驱动 ChatGPT。下一步：系统设置…"
        ])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .needsChatGPT)
    }

    func testUnknownWhenNotOKButNoRecognizedMessage() {
        // 不能默认当成「就绪」——那会让用户点进去撞一堵墙
        let readiness = BridgeReadiness(ok: false, messages: ["某种没见过的失败"])
        XCTAssertEqual(PermissionStatus.evaluate(readiness: readiness), .unknown)
    }

    func testSystemSettingsURLPointsAtAccessibilityPane() {
        XCTAssertEqual(PermissionStatus.systemSettingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PermissionStatusTests`
Expected: 编译失败 —— `PermissionStatus` 未定义

- [ ] **Step 3: 实现**

`PermissionStatus.swift`：

```swift
import ChatGPTBridge
import Foundation

public enum PermissionState: Equatable, Sendable {
    case ready
    case needsAccessibility
    case needsChatGPT
    /// preflight 报了失败，但消息不是我们认识的任何一种。
    /// **不能当成 ready** —— 那会让用户点进去撞一堵墙且没有线索。
    case unknown
}

public enum PermissionStatus {
    public static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    public static func evaluate(readiness: BridgeReadiness) -> PermissionState {
        if readiness.ok { return .ready }
        let joined = readiness.messages.joined()
        // 顺序有意义：两样都缺时先引导装 ChatGPT——没有目标应用，给了权限也没用
        if joined.contains("没找到 ChatGPT") { return .needsChatGPT }
        if joined.contains("辅助功能") { return .needsAccessibility }
        return .unknown
    }
}
```

`PermissionGateView.swift`：

```swift
import AppKit
import ChatGPTBridge
import SwiftUI

/// 环境未就绪时挡在前面的引导页。用户可以跳过——spec 第 7 节规定授权可跳过，
/// 跳过后运行在半自动模式（练习仍可进行，只是复盘要手动 ⌘C）。
public struct PermissionGateView: View {
    let state: PermissionState
    let messages: [String]
    let onRecheck: () -> Void
    let onSkip: () -> Void

    public init(state: PermissionState, messages: [String],
                onRecheck: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.state = state; self.messages = messages
        self.onRecheck = onRecheck; self.onSkip = onSkip
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2).bold()
            ForEach(messages, id: \.self) { Text($0).textSelection(.enabled) }
            HStack {
                if state == .needsAccessibility {
                    Button("打开系统设置") { NSWorkspace.shared.open(PermissionStatus.systemSettingsURL) }
                }
                Button("重新检查", action: onRecheck)
                Button("先跳过", action: onSkip)
            }
        }
        .padding(32)
        .frame(maxWidth: 640, alignment: .leading)
    }

    private var title: String {
        switch state {
        case .ready: return "环境就绪"
        case .needsAccessibility: return "还差一步：辅助功能权限"
        case .needsChatGPT: return "还没装 ChatGPT"
        case .unknown: return "环境检查没通过"
        }
    }
}

#Preview {
    PermissionGateView(state: .needsAccessibility,
                       messages: ["❌ 没有辅助功能权限，无法驱动 ChatGPT。下一步：系统设置 › 隐私与安全性 › 辅助功能，把本应用加进去并勾选。"],
                       onRecheck: {}, onSkip: {})
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PermissionStatusTests`
Expected: PASS（6 个测试）

- [ ] **Step 5: 突变验证**

把 `evaluate` 里 `return .unknown` 改成 `return .ready`，重跑：`testUnknownWhenNotOKButNoRecognizedMessage` 必须变红。改回后确认全绿。把两次输出写进报告。

**这条守的是本项目反复栽跟头的那类问题**：把「没认出来的失败」当成成功，用户点进去撞墙且没有线索。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Onboarding/ Tests/IELTSCoachUITests/
git rm Tests/IELTSCoachUITests/PlaceholderTests.swift
git commit -m "feat(ui): 权限状态判定与授权引导页"
```

---

## Task 3: AppState 与侧边栏导航骨架

**Files:**
- Create: `Sources/IELTSCoachUI/AppState.swift`
- Create: `Sources/IELTSCoachUI/Navigation.swift`
- Modify: `Sources/IELTSCoachUI/RootView.swift`
- Create: `Tests/IELTSCoachUITests/NavigationTests.swift`

**Interfaces:**
- Consumes: `StateStore(directory:)`、`.load() throws -> CoachState`、`DataDirectory.resolve()`、`AXDriver`、`LiveAXAccess`、`AXLocator`
- Produces:
  - `enum SidebarItem: String, CaseIterable, Identifiable`（十项，含 `title` 与 `systemImage`）
  - `SidebarItem.isImplemented: Bool`
  - `@Observable final class AppState`，含 `state: CoachState`、`permission: PermissionState`、`loadError: String?`、`reload()`、`recheckPermission()`

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
@testable import IELTSCoachUI

final class NavigationTests: XCTestCase {
    func testSidebarHasAllTenItems() {
        XCTAssertEqual(SidebarItem.allCases.count, 10)
    }

    func testEveryItemHasChineseTitleAndIcon() {
        for item in SidebarItem.allCases {
            XCTAssertFalse(item.title.isEmpty, "\(item) 缺标题")
            XCTAssertFalse(item.systemImage.isEmpty, "\(item) 缺图标")
        }
    }

    func testPhase3ImplementsExactlyThreePages() {
        // 本阶段只做今日训练、训练题库、复盘报告三页，其余显示占位。
        // 断言数量而非只断言「至少三个」—— 多标了会让用户点进空页面。
        let implemented = SidebarItem.allCases.filter(\.isImplemented)
        XCTAssertEqual(Set(implemented), [.today, .questionBank, .reviewReports])
    }

    func testTitlesAreUnique() {
        let titles = SidebarItem.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "侧边栏有重名条目")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter NavigationTests`
Expected: 编译失败 —— `SidebarItem` 未定义

- [ ] **Step 3: 实现**

`Navigation.swift`：

```swift
import Foundation

/// 侧边栏十项，与产品设计稿一致。
public enum SidebarItem: String, CaseIterable, Identifiable, Sendable {
    case today, questionBank, plan, retraining, reviewReports
    case upgrade, feedback, history, issues, vocabulary

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return "今日训练"
        case .questionBank: return "训练题库"
        case .plan: return "学习计划"
        case .retraining: return "复训中心"
        case .reviewReports: return "复盘报告"
        case .upgrade: return "功能升级"
        case .feedback: return "问题反馈"
        case .history: return "训练记录"
        case .issues: return "问题档案"
        case .vocabulary: return "我的词汇"
        }
    }

    public var systemImage: String {
        switch self {
        case .today: return "house"
        case .questionBank: return "list.bullet.rectangle"
        case .plan: return "calendar"
        case .retraining: return "arrow.triangle.2.circlepath"
        case .reviewReports: return "doc.text"
        case .upgrade: return "arrow.up.circle"
        case .feedback: return "bubble.left"
        case .history: return "clock"
        case .issues: return "exclamationmark.triangle"
        case .vocabulary: return "textformat.abc"
        }
    }

    /// 本阶段是否已实现。未实现的显示占位页，写明「这一页还没做」和它将来会有什么，
    /// 而不是空白——空白会让用户以为坏了。
    public var isImplemented: Bool {
        switch self {
        case .today, .questionBank, .reviewReports: return true
        default: return false
        }
    }
}
```

`AppState.swift`：

```swift
import ChatGPTBridge
import Foundation
import IELTSCoachCore
import Observation

@Observable
public final class AppState {
    public private(set) var state: CoachState = .empty()
    public private(set) var permission: PermissionState = .unknown
    public private(set) var permissionMessages: [String] = []
    /// 读取训练数据失败时的中文说明。非 nil 时界面必须显示它——
    /// 静默失败会让用户以为自己的练习记录没了。
    public private(set) var loadError: String?
    public var permissionSkipped = false

    private let store: StateStore

    public init(directory: DataDirectory = .resolve()) {
        self.store = StateStore(directory: directory)
        reload()
        recheckPermission()
    }

    public func reload() {
        do {
            state = try store.load()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    public func recheckPermission() {
        let access = LiveAXAccess()
        let readiness = AXDriver(access: access, locator: AXLocator(access: access)).preflight()
        permission = PermissionStatus.evaluate(readiness: readiness)
        permissionMessages = readiness.messages
    }
}
```

`RootView.swift` 改为：

```swift
import SwiftUI

public struct RootView: View {
    @State private var app = AppState()
    @State private var selection: SidebarItem = .today

    public init() {}

    public var body: some View {
        if app.permission != .ready && !app.permissionSkipped {
            PermissionGateView(state: app.permission, messages: app.permissionMessages,
                               onRecheck: { app.recheckPermission() },
                               onSkip: { app.permissionSkipped = true })
        } else {
            NavigationSplitView {
                List(SidebarItem.allCases, selection: $selection) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
                .navigationSplitViewColumnWidth(200)
            } detail: {
                detail
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let loadError = app.loadError {
            VStack(alignment: .leading, spacing: 12) {
                Text("读不到训练数据").font(.title3).bold()
                Text(loadError).textSelection(.enabled)
                Button("重试") { app.reload() }
            }.padding(32)
        } else {
            switch selection {
            case .today: TodayView(app: app)
            case .questionBank: QuestionBankView(app: app)
            case .reviewReports: ReviewReportView(app: app)
            default: PlaceholderView(item: selection)
            }
        }
    }
}

/// 未实现页面的占位。写明「还没做」与将来会有什么——
/// 空白页会让用户以为程序坏了。
struct PlaceholderView: View {
    let item: SidebarItem
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: item.systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text("「\(item.title)」还没做").font(.title3)
            Text(comingSoon).foregroundStyle(.secondary)
        }.padding(32)
    }

    private var comingSoon: String {
        switch item {
        case .plan: return "将来在这里选 7/14/30 天周期、定重点 Part，并看每日拆分。"
        case .retraining: return "将来在这里挑一个复盘里的目标，带着它重练，再换题验证。"
        case .history: return "将来在这里按月回看每次练习的题目、复盘和录音。"
        case .issues: return "将来在这里看反复出现的问题，以及它们有没有变少。"
        case .vocabulary: return "将来在这里看积累的词汇，并导出到 Anki。"
        case .upgrade: return "将来在这里看新版本与更新说明。"
        case .feedback: return "将来在这里反馈问题。"
        default: return ""
        }
    }
}
```

**注意：** `TodayView`、`QuestionBankView`、`ReviewReportView` 在 Task 4–6 才实现。本任务先建三个最小占位实现让工程编得过，各自只显示一行文字，Task 4–6 分别替换。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter NavigationTests`
Expected: PASS（4 个测试）

Run: `swift test`
Expected: 全绿

- [ ] **Step 5: 提交**

```bash
git add Sources/IELTSCoachUI/ Tests/IELTSCoachUITests/
git commit -m "feat(ui): AppState 与侧边栏导航骨架"
```

---

## Task 4: 训练题库页

**Files:**
- Create: `Sources/IELTSCoachUI/QuestionBank/QuestionBankViewModel.swift`
- Create: `Sources/IELTSCoachUI/QuestionBank/QuestionBankView.swift`
- Create: `Tests/IELTSCoachUITests/QuestionBankViewModelTests.swift`

**Interfaces:**
- Consumes: `CoachState.questions: [Question]`（字段 `id`、`part: Int`、`topic`、`prompt`、`status`）、`QuestionBankImporter.importCSV/importJSON/merge`、`StateStore.mutate`
- Produces:
  - `struct QuestionBankViewModel`，含 `init(questions:)`、`filtered(part: Int?) -> [Question]`、`groupedByTopic(part: Int?) -> [(topic: String, questions: [Question])]`、`counts: (total: Int, practiced: Int)`
  - `QuestionBankView`

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class QuestionBankViewModelTests: XCTestCase {
    private func q(_ id: String, _ part: Int, _ topic: String, status: String = "new") -> Question {
        Question(id: id, part: part, topic: topic, prompt: "P-\(id)", status: status)
    }

    func testFilterByPart() {
        let vm = QuestionBankViewModel(questions: [q("a", 1, "Home"), q("b", 2, "Skills"), q("c", 1, "Work")])
        XCTAssertEqual(vm.filtered(part: 1).map(\.id), ["a", "c"])
        XCTAssertEqual(vm.filtered(part: nil).count, 3)
    }

    func testGroupsByTopicSortedByName() {
        let vm = QuestionBankViewModel(questions: [
            q("a", 1, "Work"), q("b", 1, "Home"), q("c", 1, "Work")
        ])
        let groups = vm.groupedByTopic(part: 1)
        XCTAssertEqual(groups.map(\.topic), ["Home", "Work"])
        XCTAssertEqual(groups.last?.questions.map(\.id), ["a", "c"])
    }

    func testGroupingRespectsPartFilter() {
        let vm = QuestionBankViewModel(questions: [q("a", 1, "Home"), q("b", 2, "Home")])
        XCTAssertEqual(vm.groupedByTopic(part: 2).flatMap(\.questions).map(\.id), ["b"])
    }

    func testCountsPracticed() {
        let vm = QuestionBankViewModel(questions: [
            q("a", 1, "Home", status: "practiced"), q("b", 1, "Home"), q("c", 2, "Skills", status: "practiced")
        ])
        XCTAssertEqual(vm.counts.total, 3)
        XCTAssertEqual(vm.counts.practiced, 2)
    }

    func testEmptyBankProducesEmptyGroupsNotCrash() {
        let vm = QuestionBankViewModel(questions: [])
        XCTAssertTrue(vm.groupedByTopic(part: nil).isEmpty)
        XCTAssertEqual(vm.counts.total, 0)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter QuestionBankViewModelTests`
Expected: 编译失败 —— `QuestionBankViewModel` 未定义

- [ ] **Step 3: 实现**

```swift
import Foundation
import IELTSCoachCore

public struct QuestionBankViewModel: Sendable {
    public let questions: [Question]

    public init(questions: [Question]) { self.questions = questions }

    public func filtered(part: Int?) -> [Question] {
        guard let part else { return questions }
        return questions.filter { $0.part == part }
    }

    /// 按话题分组，话题按名称排序，组内保持题库原有顺序。
    public func groupedByTopic(part: Int?) -> [(topic: String, questions: [Question])] {
        let subset = filtered(part: part)
        var order: [String] = []
        var buckets: [String: [Question]] = [:]
        for question in subset {
            if buckets[question.topic] == nil { order.append(question.topic) }
            buckets[question.topic, default: []].append(question)
        }
        return order.sorted().map { ($0, buckets[$0] ?? []) }
    }

    public var counts: (total: Int, practiced: Int) {
        (questions.count, questions.filter { $0.status == "practiced" }.count)
    }
}
```

`QuestionBankView.swift`：一个带 Part 分段选择器的列表，顶部显示 `counts`，底部一个「导入题库…」按钮走 `NSOpenPanel`，选中文件后按扩展名调 `importCSV`/`importJSON`，**把 `ImportResult.warnings` 逐条显示出来**（那些警告是在告诉用户 CSV 哪一行有问题，比「导入了 N 题」有用得多），再 `StateStore.mutate` 合并入库并 `app.reload()`。导入失败时显示 `error.localizedDescription`。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter QuestionBankViewModelTests`
Expected: PASS（5 个测试）

- [ ] **Step 5: 突变验证**

把 `groupedByTopic` 里的 `order.sorted()` 改成 `order`，重跑：`testGroupsByTopicSortedByName` 必须变红。改回后确认全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/QuestionBank/ Tests/IELTSCoachUITests/
git commit -m "feat(ui): 训练题库页"
```

---

## Task 5: 复盘报告页

**Files:**
- Create: `Sources/IELTSCoachUI/Review/ReviewReportViewModel.swift`
- Create: `Sources/IELTSCoachUI/Review/ReviewReportView.swift`
- Create: `Tests/IELTSCoachUITests/ReviewReportViewModelTests.swift`

**Interfaces:**
- Consumes: `JSONValue`（下标、`arrayValue`、`stringValue`）、`ReviewParser.parse(_:requireAnswerUpgrades:)`
- Produces:
  - `struct ReviewSection: Equatable { let title: String; let rows: [ReviewRow] }`
  - `struct ReviewRow: Equatable, Identifiable { let id: String; let primary: String; let secondary: String; let note: String }`
  - `ReviewReportViewModel.sections(from report: JSONValue) -> [ReviewSection]`
  - `ReviewReportViewModel.priorityTarget(from report: JSONValue) -> ReviewRow?`

**字段名以修复后的 `ReviewRequestPrompt` 为准**（spec 2.3.8）：`must_correct` 每项 `{learner_said, correction, why_it_matters}`；`natural_upgrades` 每项 `{learner_said, more_natural, usage_note}`；`vocabulary` 每项 `{basic, better, collocation, priority}`；`answer_upgrades` 每项 `{question, original_answer, revised_answer, changes}`。

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class ReviewReportViewModelTests: XCTestCase {
    private func report(_ json: String) throws -> JSONValue { try JSONValue.decode(from: json) }

    func testBuildsMustCorrectSection() throws {
        let value = try report(#"""
        {"must_correct":[{"learner_said":"I very like it.","correction":"I really like it.",
        "why_it_matters":"very 不能修饰动词"}]}
        """#)
        let sections = ReviewReportViewModel.sections(from: value)
        let section = try XCTUnwrap(sections.first { $0.title == "必须纠正的表达" })
        XCTAssertEqual(section.rows.count, 1)
        XCTAssertEqual(section.rows[0].primary, "I very like it.")
        XCTAssertEqual(section.rows[0].secondary, "I really like it.")
        XCTAssertEqual(section.rows[0].note, "very 不能修饰动词")
    }

    func testSkipsSectionsThatAreAbsentOrEmpty() throws {
        let value = try report(#"{"must_correct":[],"vocabulary":[]}"#)
        XCTAssertTrue(ReviewReportViewModel.sections(from: value).isEmpty,
                      "空的分区不该显示成一个空标题")
    }

    func testExtractsPriorityTarget() throws {
        let value = try report(#"""
        {"priority_target":{"id":"logic-explain","label":"补一个原因和例子","evidence":["I just like it."]}}
        """#)
        let target = try XCTUnwrap(ReviewReportViewModel.priorityTarget(from: value))
        XCTAssertEqual(target.primary, "补一个原因和例子")
        XCTAssertTrue(target.note.contains("I just like it."))
    }

    func testSurvivesWrongShapeWithoutCrashing() throws {
        // ChatGPT 曾把 vocabulary 输出成对象而非数组（spec 2.3.8）。
        // 界面绝不能因此崩溃，最多是这一节不显示。
        let value = try report(#"{"vocabulary":{"useful":"x"},"must_correct":"不是数组"}"#)
        XCTAssertNoThrow(ReviewReportViewModel.sections(from: value))
        XCTAssertTrue(ReviewReportViewModel.sections(from: value).isEmpty)
    }

    func testSectionOrderFollowsReportSchema() throws {
        let value = try report(#"""
        {"vocabulary":[{"basic":"good","better":"rewarding","collocation":"a rewarding trip","priority":"high"}],
         "must_correct":[{"learner_said":"a","correction":"b","why_it_matters":"c"}]}
        """#)
        // 顺序固定，不随 JSON 键序变化——否则同一份复盘每次打开顺序都不一样
        XCTAssertEqual(ReviewReportViewModel.sections(from: value).map(\.title),
                       ["必须纠正的表达", "词汇升级"])
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter ReviewReportViewModelTests`
Expected: 编译失败 —— `ReviewReportViewModel` 未定义

- [ ] **Step 3: 实现**

```swift
import Foundation
import IELTSCoachCore

public struct ReviewRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let primary: String
    public let secondary: String
    public let note: String
}

public struct ReviewSection: Equatable, Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    public let rows: [ReviewRow]
}

public enum ReviewReportViewModel {
    /// 分区顺序固定，不随 JSON 键序变化——否则同一份复盘每次打开顺序都不一样。
    private static let layout: [(title: String, key: String, fields: (String, String, String))] = [
        ("必须纠正的表达", "must_correct", ("learner_said", "correction", "why_it_matters")),
        ("更自然的表达", "natural_upgrades", ("learner_said", "more_natural", "usage_note")),
        ("词汇升级", "vocabulary", ("basic", "better", "collocation")),
        ("逐题高分版", "answer_upgrades", ("question", "original_answer", "revised_answer"))
    ]

    public static func sections(from report: JSONValue) -> [ReviewSection] {
        layout.compactMap { entry in
            // arrayValue 在形状不对时返回 nil（ChatGPT 曾把 vocabulary 输出成对象），
            // 此时跳过这一节而不是崩溃
            guard let items = report[entry.key]?.arrayValue, !items.isEmpty else { return nil }
            let rows = items.enumerated().map { index, item in
                ReviewRow(id: "\(entry.key)-\(index)",
                          primary: item[entry.fields.0]?.stringValue ?? "",
                          secondary: item[entry.fields.1]?.stringValue ?? "",
                          note: item[entry.fields.2]?.stringValue ?? "")
            }
            return ReviewSection(title: entry.title, rows: rows)
        }
    }

    public static func priorityTarget(from report: JSONValue) -> ReviewRow? {
        guard let target = report["priority_target"], target.objectValue != nil,
              let label = target["label"]?.stringValue, !label.isEmpty else { return nil }
        let evidence = (target["evidence"]?.arrayValue ?? []).compactMap(\.stringValue)
        return ReviewRow(id: target["id"]?.stringValue ?? "target",
                         primary: label,
                         secondary: target["status"]?.stringValue ?? "new",
                         note: evidence.joined(separator: "；"))
    }
}
```

`ReviewReportView.swift`：左侧列出 `state.sessions` 里带 `reportPath` 的会话（按时间倒序），右侧显示选中那份复盘的分区。复盘 JSON 从 `reportPath` 读取并 `ReviewParser.parse`。**顶部显著位置显示 `priorityTarget`**（设计稿里那块深色的 NEXT SINGLE TARGET）。读不到或解析失败时显示中文错误与文件路径，让用户能自己去看原文。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter ReviewReportViewModelTests`
Expected: PASS（5 个测试）

- [ ] **Step 5: 突变验证**

把 `sections` 里的 `!items.isEmpty` 去掉，重跑：`testSkipsSectionsThatAreAbsentOrEmpty` 必须变红。改回后确认全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Review/ Tests/IELTSCoachUITests/
git commit -m "feat(ui): 复盘报告页"
```

---

## Task 6: 今日训练页

**Files:**
- Create: `Sources/IELTSCoachUI/Today/TodayViewModel.swift`
- Create: `Sources/IELTSCoachUI/Today/TodayView.swift`
- Create: `Tests/IELTSCoachUITests/TodayViewModelTests.swift`

**Interfaces:**
- Consumes: `CoachState`（`plan`、`questions`、`sessions`、`settings`）、`TrainingPlan`、`PlanDay`
- Produces:
  - `enum PracticeRoute: String, CaseIterable { case planToday, freePick, continueLast, retrain }`（各带 `title`、`subtitle`）
  - `struct TodayViewModel`，含 `init(state:today:)`、`todayQuestions: [Question]`、`availableRoutes: [PracticeRoute]`、`weekProgress: (done: Int, goal: Int)`、`recentSessions: [PracticeSession]`

**本阶段只显示与选择，不实际发起练习。** 点「开始练习」暂时提示「请在终端运行 `coach practice <id>`」——Phase 4 会把驱动接进界面。这是刻意的：把界面与驱动分两步接，出问题时能立刻判断是哪一侧。

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
import IELTSCoachCore
@testable import IELTSCoachUI

final class TodayViewModelTests: XCTestCase {
    private func question(_ id: String) -> Question {
        Question(id: id, part: 1, topic: "Home", prompt: "P-\(id)")
    }

    private func state(plan: TrainingPlan?, questions: [Question], sessions: [PracticeSession] = []) -> CoachState {
        var s = CoachState.empty()
        s.plan = plan; s.questions = questions; s.sessions = sessions
        return s
    }

    func testTodayQuestionsComeFromFirstIncompletePlanDay() throws {
        let questions = (1...14).map { question("q\($0)") }
        let plan = try PlanBuilder.build(questions: questions, lengthDays: 7,
                                         createdAt: "2026-08-05T00:00:00Z")
        let vm = TodayViewModel(state: state(plan: plan, questions: questions))
        XCTAssertEqual(vm.todayQuestions.count, 2, "14 题分 7 天，每天 2 题")
        XCTAssertEqual(vm.todayQuestions.map(\.id), plan.days[0].questionIds)
    }

    func testTodaySkipsCompletedDays() throws {
        let questions = (1...14).map { question("q\($0)") }
        var plan = try PlanBuilder.build(questions: questions, lengthDays: 7,
                                         createdAt: "2026-08-05T00:00:00Z")
        for id in plan.days[0].questionIds { plan = PlanBuilder.markCompleted(plan: plan, questionID: id) }
        let vm = TodayViewModel(state: state(plan: plan, questions: questions))
        XCTAssertEqual(vm.todayQuestions.map(\.id), plan.days[1].questionIds)
    }

    func testRouteUnavailableWhenItsPreconditionIsMissing() {
        // 没有计划就不该显示「按计划练今天」，点了也没用
        let vm = TodayViewModel(state: state(plan: nil, questions: [question("a")]))
        XCTAssertFalse(vm.availableRoutes.contains(.planToday))
        XCTAssertTrue(vm.availableRoutes.contains(.freePick), "有题库就该能自由选题")
    }

    func testContinueLastUnavailableWithoutSessions() {
        let vm = TodayViewModel(state: state(plan: nil, questions: [question("a")]))
        XCTAssertFalse(vm.availableRoutes.contains(.continueLast))
    }

    func testFreePickUnavailableWhenBankIsEmpty() {
        let vm = TodayViewModel(state: state(plan: nil, questions: []))
        XCTAssertTrue(vm.availableRoutes.isEmpty, "题库空时一条路线都不该显示")
    }

    func testRetrainAvailableOnlyWithLiveTargets() {
        func target(_ key: String, status: String) -> RetrainingTarget {
            RetrainingTarget(targetKey: key, label: "L", status: status, evidence: [],
                             sourceSessionId: "s1", createdAt: "t")
        }
        var withRetired = state(plan: nil, questions: [question("a")])
        withRetired.targets = [target("t1", status: "retired")]
        XCTAssertFalse(TodayViewModel(state: withRetired).availableRoutes.contains(.retrain),
                       "已退休的目标不该让「复训」路线出现")

        var withLive = withRetired
        withLive.targets.append(target("t2", status: "new"))
        XCTAssertTrue(TodayViewModel(state: withLive).availableRoutes.contains(.retrain))
    }

    func testWeekProgressCountsOnlyThisWeek() {
        func session(_ id: String, _ startedAt: String) -> PracticeSession {
            PracticeSession(id: id, questionId: "q", focusPart: .part1, startedAt: startedAt,
                            endedAt: startedAt, goal: "", transcript: [], reportPath: "", recordingPath: "")
        }
        let s = state(plan: nil, questions: [question("a")], sessions: [
            session("in", "2026-08-05T10:00:00Z"),
            session("also-in", "2026-08-03T10:00:00Z"),
            session("out", "2026-07-20T10:00:00Z")
        ])
        let vm = TodayViewModel(state: s, today: ISO8601DateFormatter().date(from: "2026-08-05T12:00:00Z")!)
        XCTAssertEqual(vm.weekProgress.done, 2)
        XCTAssertEqual(vm.weekProgress.goal, 5)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TodayViewModelTests`
Expected: 编译失败 —— `TodayViewModel` 未定义

- [ ] **Step 3: 实现**

```swift
import Foundation
import IELTSCoachCore

public enum PracticeRoute: String, CaseIterable, Identifiable, Sendable {
    case planToday, freePick, continueLast, retrain
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .planToday: return "按计划练今天"
        case .freePick: return "从题库自由选题"
        case .continueLast: return "继续上次练习"
        case .retrain: return "复训一个旧问题"
        }
    }

    public var subtitle: String {
        switch self {
        case .planToday: return "按学习计划安排的今日题目"
        case .freePick: return "先选 Part，再挑具体题目"
        case .continueLast: return "接着上次那道题再练"
        case .retrain: return "带上一次复盘给出的目标"
        }
    }
}

public struct TodayViewModel: Sendable {
    public let state: CoachState
    private let today: Date

    public init(state: CoachState, today: Date = Date()) {
        self.state = state
        self.today = today
    }

    /// 计划里第一个未完成的那天的题目。
    public var todayQuestions: [Question] {
        guard let plan = state.plan,
              let day = plan.days.first(where: { !$0.isComplete && !$0.questionIds.isEmpty })
        else { return [] }
        return day.questionIds.compactMap { id in state.questions.first { $0.id == id } }
    }

    /// 只显示前提成立的路线。显示一条点了没用的路线，比不显示更糟——
    /// 用户会以为程序坏了。
    public var availableRoutes: [PracticeRoute] {
        var routes: [PracticeRoute] = []
        if !todayQuestions.isEmpty { routes.append(.planToday) }
        if !state.questions.isEmpty { routes.append(.freePick) }
        if !state.sessions.isEmpty { routes.append(.continueLast) }
        if state.targets.contains(where: { $0.status != "retired" }) { routes.append(.retrain) }
        return routes
    }

    public var weekProgress: (done: Int, goal: Int) {
        let calendar = Calendar(identifier: .iso8601)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return (0, 5)
        }
        let formatter = ISO8601DateFormatter()
        let done = state.sessions.filter { session in
            guard let started = formatter.date(from: session.startedAt) else { return false }
            return week.contains(started)
        }.count
        return (done, 5)
    }

    public var recentSessions: [PracticeSession] {
        Array(state.sessions.sorted { $0.startedAt > $1.startedAt }.prefix(5))
    }
}
```

`TodayView.swift`：顶部问候与日期；中间四条路线的卡片（只渲染 `availableRoutes`，`planToday` 卡片里列出 `todayQuestions`）；右侧「本周训练 N/5」；下方「最近练习」列表。题库为空时整页显示引导：「题库还是空的。下一步：到「训练题库」页导入你的题库文件。」并附一个直接跳过去的按钮。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter TodayViewModelTests`
Expected: PASS（6 个测试）

- [ ] **Step 5: 突变验证**

把 `todayQuestions` 里的 `!$0.isComplete` 去掉（永远取第一天），重跑：`testTodaySkipsCompletedDays` 必须变红。改回后确认全绿。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Today/ Tests/IELTSCoachUITests/
git commit -m "feat(ui): 今日训练页"
```

---

## Task 7: 设计令牌与基础组件

**Files:**
- Create: `Sources/IELTSCoachUI/DesignSystem/Palette.swift`
- Create: `Sources/IELTSCoachUI/DesignSystem/Metrics.swift`
- Create: `Sources/IELTSCoachUI/DesignSystem/Components.swift`
- Create: `Tests/IELTSCoachUITests/DesignSystemTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: `Palette`、`Spacing`、`Radius`、`CoachCard`、`PrimaryActionCard`、`SectionHeader`、`EmptyStateView`

**取值全部见 `docs/superpowers/DESIGN-SYSTEM.md`，逐字照抄，不要自行调色。**

**本任务实际应在 Task 4–6 之前完成**（编号排在这里只是为了不打乱既有任务号）。三个页面必须用这套组件搭，否则会出现三种不同的卡片样式——那正是界面显得业余的头号原因。

- [ ] **Step 1: 写失败的测试**

对比度是能算的，因此能测。这是设计规范里唯一可自动验证的部分，务必测。

```swift
import SwiftUI
import XCTest
@testable import IELTSCoachUI

final class DesignSystemTests: XCTestCase {
    /// WCAG 相对亮度
    private func luminance(_ color: Color) -> Double {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        func channel(_ v: CGFloat) -> Double {
            let c = Double(v)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(ns.redComponent)
             + 0.7152 * channel(ns.greenComponent)
             + 0.0722 * channel(ns.blueComponent)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    func testPrimaryTextMeetsAA() {
        XCTAssertGreaterThanOrEqual(contrast(Palette.textPrimary, Palette.canvas), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(Palette.textPrimary, Palette.card), 4.5)
    }

    func testSecondaryTextAlsoMeetsAA() {
        // 次要文字仍然是要读的，不能降到 3:1。
        // 灰上加灰是让界面显廉价的头号原因。
        XCTAssertGreaterThanOrEqual(contrast(Palette.textSecondary, Palette.card), 4.5)
    }

    func testTextOnAccentMeetsAA() {
        XCTAssertGreaterThanOrEqual(contrast(Palette.textOnAccent, Palette.accent), 4.5)
    }

    func testSidebarTextMeetsAA() {
        XCTAssertGreaterThanOrEqual(contrast(Palette.sidebarText, Palette.sidebarBackground), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(Palette.sidebarTextSelected, Palette.sidebarBackground), 4.5)
    }

    func testSpacingScaleIsMultiplesOfFour() {
        for value in [Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl, Spacing.section] {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 4), 0, "\(value) 不是 4 的倍数")
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter DesignSystemTests`
Expected: 编译失败 —— `Palette` 未定义

- [ ] **Step 3: 实现**

按 `DESIGN-SYSTEM.md` 第 2、3 节逐字实现 `Palette`、`Spacing`、`Radius`。

`Components.swift` 实现四个组件，规范见 `DESIGN-SYSTEM.md` 第 4 节：

- `CoachCard`：白底、圆角 `Radius.card`、发丝边框、**不加投影**（设计稿靠边框和留白分层，不靠阴影）
- `PrimaryActionCard`：`Palette.accent` 填充 + `Palette.textOnAccent` 文字
- `SectionHeader(number:label:title:)`：小号编号 + 大写英文标签 + 中文标题，形如 `01 / PRACTICE ROUTES / 今天练什么？`
- `EmptyStateView(message:hint:actionTitle:action:)`：**说明现状 + 说明下一步 + 一个能直接点的按钮**，三样缺一不可

若某组件的视觉细节在规范里没写死，按规范的原则自行决定，但**不得引入字面颜色值、字号或圆角**——一律走令牌。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter DesignSystemTests`
Expected: PASS（5 个测试）

- [ ] **Step 5: 突变验证**

把 `Palette.textSecondary` 的不透明度从 0.56 改成 0.40（这是很多人会「顺手调淡一点」的值），重跑：`testSecondaryTextAlsoMeetsAA` 必须变红。改回后确认全绿。

**这条守的正是「界面显廉价」最常见的成因**，而它平时没人能一眼指出来——只会觉得「有点糊但说不上哪儿不对」。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/DesignSystem/ Tests/IELTSCoachUITests/
git commit -m "feat(ui): 设计令牌与基础组件"
```

---

## Task 8: 题库 PDF 导入

**Files:**
- Create: `Sources/IELTSCoachCore/QuestionBank/PDFQuestionExtractor.swift`
- Modify: `Sources/IELTSCoachUI/QuestionBank/QuestionBankView.swift`
- Create: `Tests/IELTSCoachCoreTests/PDFQuestionExtractorTests.swift`

**Interfaces:**
- Consumes: `Question`、`ImportResult`
- Produces: `PDFQuestionExtractor.extract(plainText:sourceTitle:) throws -> ImportResult`

**为什么必须做：** 用户手上的季度题库是 PDF，已复制到仓库根目录（`2026年5-8月雅思口语题目 5.20(1)(2).pdf`）。当前导入只支持 CSV/JSON，意味着用户得手动把上百道题敲成表格。**不解决它，界面做完了也没题可练。**

**分层：** 文本提取（需 PDFKit）与题目解析（纯 Foundation）分开。解析放 Core、只吃纯文本，因此**完全可测**；提取很薄，放 UI 层调 PDFKit。这样 `IELTSCoachCore` 只依赖 Foundation 的约束不被破坏。

雅思题库 PDF 的典型结构：Part 1 是话题 + 若干短问题；Part 2 是 cue card（`Describe…` + `You should say:` + 若干提示点）；Part 3 是话题 + 追问。

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
@testable import IELTSCoachCore

final class PDFQuestionExtractorTests: XCTestCase {
    func testExtractsPart1TopicAndQuestions() throws {
        let text = [
            "Part 1",
            "Home",
            "Do you live in a house or a flat?",
            "What do you like about your home?",
            "",
            "Work",
            "What do you do for a living?",
        ].joined(separator: "\n")

        let result = try PDFQuestionExtractor.extract(plainText: text, sourceTitle: "季度题库")
        let part1 = result.questions.filter { $0.part == 1 }
        XCTAssertEqual(part1.count, 3)
        XCTAssertEqual(part1.first?.topic, "Home")
        XCTAssertEqual(part1.last?.topic, "Work")
    }

    func testExtractsPart2CueCardAsSingleQuestion() throws {
        let text = [
            "Part 2",
            "Describe a useful skill you learned.",
            "You should say:",
            "what it is",
            "how you learned it",
            "and explain why it is useful.",
        ].joined(separator: "\n")

        let result = try PDFQuestionExtractor.extract(plainText: text, sourceTitle: "t")
        let part2 = result.questions.filter { $0.part == 2 }
        XCTAssertEqual(part2.count, 1, "整张 cue card 是一道题，不能被拆成多道")
        XCTAssertTrue(part2[0].prompt.contains("Describe a useful skill"))
        XCTAssertEqual(part2[0].followups.count, 3, "You should say 下面的提示点应进 followups")
    }

    func testIgnoresPageNumbersAndRunningHeaders() throws {
        let text = [
            "Part 1",
            "Home",
            "Do you live in a house or a flat?",
            "1",
            "第 1 页",
            "2026年5-8月雅思口语题目",
            "What do you like about your home?",
        ].joined(separator: "\n")

        let result = try PDFQuestionExtractor.extract(
            plainText: text, sourceTitle: "2026年5-8月雅思口语题目")
        XCTAssertEqual(result.questions.count, 2, "页码与页眉不能被当成题目")
    }

    func testWarnsWhenNothingExtracted() throws {
        let result = try PDFQuestionExtractor.extract(
            plainText: "完全无关的一段文字", sourceTitle: "t")
        XCTAssertTrue(result.questions.isEmpty)
        XCTAssertFalse(result.warnings.isEmpty, "一道题都没提出来必须报警，不能静默返回空")
        XCTAssertTrue(result.warnings.joined().contains("下一步"), "警告必须说明下一步做什么")
    }

    func testIDsAreContentBasedSoInsertionDoesNotShiftThem() throws {
        let onlyHome = ["Part 1", "Home", "Do you live in a house or a flat?"]
            .joined(separator: "\n")
        // 在前面插入一个新话题后，原有题目的 id 不能变——
        // 否则换季重新导入会让历史练习记录全部指错题。
        let withNewTopicFirst = ["Part 1", "New Topic", "A brand new question?",
                                 "Home", "Do you live in a house or a flat?"]
            .joined(separator: "\n")

        let first = try PDFQuestionExtractor.extract(plainText: onlyHome, sourceTitle: "t")
        let second = try PDFQuestionExtractor.extract(plainText: withNewTopicFirst, sourceTitle: "t")

        let originalID = try XCTUnwrap(first.questions.first?.id)
        let afterInsert = try XCTUnwrap(second.questions.first { $0.topic == "Home" }?.id)
        XCTAssertEqual(originalID, afterInsert)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PDFQuestionExtractorTests`
Expected: 编译失败 —— `PDFQuestionExtractor` 未定义

- [ ] **Step 3: 实现**

`PDFQuestionExtractor` 只依赖 Foundation。要点：

- 按行扫描，遇到 `Part 1` / `Part 2` / `Part 3` 之类的行切换当前 Part
- **过滤噪声行**：纯数字（页码）、含「第 N 页」、与 `sourceTitle` 高度重合的行（页眉）
- Part 1/3：以问号结尾的行是题目；不以问号结尾且较短的行是话题
- Part 2：`Describe…` / `Talk about…` 开头的行是题干，`You should say:` 之后到空行之间的每行进 `followups`
- **id 必须用内容哈希**，复用 `QuestionBankImporter` 已有的做法。位置式编号会在换季重新导入时整体错位，毁掉历史练习记录——**这个坑本项目已经栽过一次**，也是成品标准第 12 条守的东西
- 一道题都没提出来时，`warnings` 必须给出可执行的下一步，不能静默返回空

`QuestionBankView` 的导入按钮把 `.pdf` 加进可选类型，选中 PDF 后取纯文本再交给 `PDFQuestionExtractor`：

```swift
import PDFKit

func plainText(ofPDFAt url: URL) -> String? {
    PDFDocument(url: url)?.string
}
```

取不到文本时提示：「这份 PDF 里没有可提取的文字，它可能是扫描件。下一步：换一份文字版 PDF，或先用系统「预览」把它转成文字。」

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PDFQuestionExtractorTests`
Expected: PASS（5 个测试）

- [ ] **Step 5: 用真实题库验证（必须人工核对）**

用户的真实 PDF 在仓库根目录。写一个临时脚本（或用 `swift run`）跑一遍提取，然后**人工核对**：

| 核对项 | 判据 |
|---|---|
| 题目总数 | 与 PDF 里肉眼可数的题数是否接近（差一两道可接受，差一半不行）|
| 抽查 5 道题 | Part、话题、题干是否都对 |
| Part 2 | cue card 是否完整成一道题，提示点是否都进了 followups |
| 有没有垃圾 | 页码、页眉、目录行有没有混进题目里 |

**这一步不能用测试代替。** 测试用的是理想排版，真实 PDF 千奇百怪。把核对结果如实写进报告，包括提取失败的部分——**若真实 PDF 结构与假设差得太远，应当停下来报告，而不是硬调规则去凑**。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachCore/QuestionBank/ Sources/IELTSCoachUI/QuestionBank/ Tests/IELTSCoachCoreTests/
git commit -m "feat(core): 题库 PDF 导入"
```

---

## Task 9: 把练习驱动接进界面

**Files:**
- Create: `Sources/IELTSCoachUI/Session/PracticeStage.swift`
- Create: `Sources/IELTSCoachUI/Session/PracticeRunner.swift`
- Create: `Sources/IELTSCoachUI/Session/PracticeSheet.swift`
- Modify: `Sources/IELTSCoachUI/Today/TodayView.swift`
- Create: `Tests/IELTSCoachUITests/PracticeRunnerTests.swift`

**Interfaces:**
- Consumes: `CoachBridge`（全部方法）、`ExaminerPrompt.build`、`ReviewRequestPrompt`、`ReviewParser`、`ReviewArchiver`、`StateStore`
- Produces:
  - `enum PracticeStage: Equatable { case idle, newChat, startingVoice, waitingComposer, sendingPrompt, practicing, endingVoice, requestingReview, capturingReview, archiving, done, failed(String) }`
  - `PracticeStage.userFacingText: String`
  - `@MainActor @Observable final class PracticeRunner`，含 `stage`、`start(setup:)`、`finishPractice()`、`cancel()`

**这一条兑现成品标准第 2 条：全程不需要打开终端。** 初版计划把驱动接入推到 Phase 4，那意味着 Phase 3 交付一个点了只会说「请去终端敲命令」的按钮——不算做完。

**设计要点：** `PracticeRunner` 只依赖 `CoachBridge` protocol，**不依赖 `AXDriver`**。因此可以用假实现完整测试整条状态流转，不碰真的 ChatGPT。这正是 Phase 2 花力气做 `AXAccess` 接缝换来的红利。

- [ ] **Step 1: 写失败的测试**

```swift
import XCTest
import ChatGPTBridge
import IELTSCoachCore
@testable import IELTSCoachUI

/// 可编程的假 Bridge，用于测试状态流转。
final class FakeBridge: CoachBridge, @unchecked Sendable {
    var failAt: PracticeStage?
    private(set) var calls: [String] = []

    private func step(_ name: String, _ stage: PracticeStage) throws {
        calls.append(name)
        if failAt == stage {
            throw BridgeError.actionFailed("假装失败。下一步：这是测试用的。")
        }
    }

    func preflight() -> BridgeReadiness { BridgeReadiness(ok: true, messages: []) }
    func startNewChat() throws { try step("newChat", .newChat) }
    func startVoice() throws { try step("startVoice", .startingVoice) }
    func waitForVoiceComposer(timeout: TimeInterval) throws -> AXNodeSnapshot {
        try step("waitComposer", .waitingComposer)
        return AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXTextArea")
    }
    func sendText(_ text: String) throws { try step("sendText", .sendingPrompt) }
    func isVoiceActive() -> Bool { false }
    func endVoice() throws { try step("endVoice", .endingVoice) }
    func waitForAssistantReply(timeout: TimeInterval, minimumLength: Int) throws {}
    func captureLatestAssistantMessage(expectedMarker: String?) throws -> String { "" }
    func copyLatestAssistantMessage(pasteboard: any PasteboardAccess,
                                    timeout: TimeInterval) throws -> String {
        try step("copy", .capturingReview)
        return #"<<<IELTS_REVIEW_JSON:x>>>{"must_correct":[]}<<<END_IELTS_REVIEW_JSON:x>>>"#
    }
}

@MainActor
final class PracticeRunnerTests: XCTestCase {
    func testEveryStageHasUserFacingChineseText() {
        let stages: [PracticeStage] = [.newChat, .startingVoice, .waitingComposer,
                                       .sendingPrompt, .practicing, .endingVoice,
                                       .requestingReview, .capturingReview, .archiving]
        for stage in stages {
            XCTAssertFalse(stage.userFacingText.isEmpty, "\(stage) 没有给用户看的说明")
        }
    }

    func testStartingVoiceTextWarnsAboutTheWait() {
        // 实测启动语音约需 9 秒（spec 2.3.7）。这 9 秒里界面必须说明它在等什么，
        // 否则用户会以为程序卡死了。
        XCTAssertTrue(PracticeStage.startingVoice.userFacingText.contains("秒"),
                      "启动语音耗时较长，提示必须写明大约要等多久")
    }

    func testFailureCarriesActionableChineseMessage() {
        guard case .failed(let message) = PracticeStage.failed("出事了。下一步：重试。") else {
            return XCTFail("构造失败")
        }
        XCTAssertTrue(message.contains("下一步"))
    }

    func testStagesRunInOrderUpToPracticing() async throws {
        let bridge = FakeBridge()
        let runner = PracticeRunner(bridge: bridge, pasteboard: FakePasteboard(contents: ""))
        try await runner.start(setup: Self.setup())
        XCTAssertEqual(bridge.calls, ["newChat", "startVoice", "waitComposer", "sendText"],
                       "必须先新建会话、再启动语音、等语音输入框出现，最后才发提示词")
        XCTAssertEqual(runner.stage, .practicing)
    }

    func testFailureStopsTheChain() async {
        let bridge = FakeBridge()
        bridge.failAt = .startingVoice
        let runner = PracticeRunner(bridge: bridge, pasteboard: FakePasteboard(contents: ""))
        try? await runner.start(setup: Self.setup())
        guard case .failed = runner.stage else { return XCTFail("应当停在失败态") }
        XCTAssertFalse(bridge.calls.contains("sendText"), "前一步失败后不能继续往下走")
    }

    private static func setup() -> SessionSetup {
        SessionSetup(question: Question(id: "q1", part: 1, topic: "Home", prompt: "P"),
                     focusPart: .part1, durationMinutes: 5, goal: "")
    }
}
```

`FakePasteboard` 已存在于 `Tests/ChatGPTBridgeTests/`。本处需要一个同等实现——**在 `Tests/IELTSCoachUITests/` 下另建一个，不要跨测试 target 引用**。

`SessionSetup` 的真实签名以 Core 里既有定义为准；若与此处不符，以 Core 为准并相应改测试。

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PracticeRunnerTests`
Expected: 编译失败 —— `PracticeRunner`、`PracticeStage` 未定义

- [ ] **Step 3: 实现**

`PracticeStage.userFacingText` 逐条给中文说明。**`startingVoice` 必须写明大约要等 10 秒**（实测 9 秒，见 spec 2.3.7）。

`PracticeRunner.start(setup:)` 严格按 spec 2.3.5 的顺序：

新建会话 → 启动语音 → 等语音输入框出现 → 发考官提示词 → 停在 `.practicing`

**顺序不能改。** Live 模式只能在一条还没发过任何消息的会话里启动，先发消息就再也点不动 Live 了。

`finishPractice()`：结束语音（若仍在）→ 发复盘请求 → 等回复 → 取复盘（**先按 ChatGPT 自己的复制按钮，失败降级 AX 读取，再失败提示用户手动 ⌘C**）→ **先落盘再解析** → 归档 → `.done`。

「先落盘再解析」不能省：练了半小时换来的复盘，不能因为解析出错就没了（成品标准第 7 条）。

任何一步抛错都转入 `.failed(错误信息)`，**不得继续往下走**。

`PracticeSheet` 显示 `stage.userFacingText` 与进度指示；`.practicing` 时显示「我练完了」按钮；`.failed` 时显示错误全文与「重试」。用 Task 7 的组件与令牌，不要自己写样式。

`TodayView` 的「开始」按钮改为弹出 `PracticeSheet` 并调 `runner.start(setup:)`。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PracticeRunnerTests`
Expected: PASS（5 个测试）

- [ ] **Step 5: 突变验证**

把 `start` 里「前一步失败就停」的逻辑改成忽略错误继续往下走，重跑：`testFailureStopsTheChain` 必须变红。改回后确认全绿。

**这条守的是：一步失败后继续往下走，会让用户对着一个根本没收到考官提示词的 ChatGPT 练完整整一场。** Phase 2 真实发生过一次。

- [ ] **Step 6: 提交**

```bash
git add Sources/IELTSCoachUI/Session/ Sources/IELTSCoachUI/Today/ Tests/IELTSCoachUITests/
git commit -m "feat(ui): 把练习驱动接进界面"
```

---

## Task 10: 修掉测试套件的耗时回归

**Files:**
- Modify: `Tests/ChatGPTBridgeTests/AXDriverTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: 无

测试总耗时从 1.1 秒涨到了 12.2 秒。上一轮加 `copyLatestAssistantMessage` 时，某条「预期失败」的测试用了默认超时（10 秒）真的等满。

- [ ] **Step 1: 定位**

Run: `swift test --filter ChatGPTBridgeTests 2>&1 | grep -E "passed|failed" | sort -t'(' -k2 -rn | head -5`
Expected: 找出耗时最长的两三条测试

- [ ] **Step 2: 改为短超时**

给这些测试显式传短超时（0.2 秒量级），与 `AXDriverTests` 里 `driver(_:)` helper 已有的做法一致。**不要改产品代码的默认值**——那些默认值是按实测时序定的（Live 启动约需 9 秒，见 spec 2.3.7）。

- [ ] **Step 3: 验证**

Run: `time swift test`
Expected: 全绿，且总耗时回到 2 秒以内

- [ ] **Step 4: 提交**

```bash
git add Tests/ChatGPTBridgeTests/
git commit -m "test: 修掉测试套件的耗时回归"
```

---

## Task 11: 真机验收（人工，不可由子代理代劳）

**Files:** 无代码改动。产出 `docs/phase3-acceptance.md`

前面所有测试跑在视图模型上，证明的是「数据变换对」，不是「界面能用」。以下只能人来判断。

- [ ] **Step 1: 打包并授权**

```bash
cd ~/Projects/ielts-speaking-coach-mac && ./scripts/build-app.sh && open ".build/IELTS Speaking Coach.app"
```

首次打开会因为没有辅助功能权限而停在引导页。**用户需要：系统设置 › 隐私与安全性 › 辅助功能 → 把 `IELTS Speaking Coach` 加进去并勾选 → 回到 App 点「重新检查」。**

- [ ] **Step 2: 验证签名稳定性（本阶段最关键的一条）**

重新跑一次 `./scripts/build-app.sh`，然后**不重新授权**直接打开 App。

Expected: 仍然显示「环境就绪」。**若又要求重新授权，说明签名不稳定，整个打包方案要重做**——请立刻停下并报告。

- [ ] **Step 3: 逐页验收**

| 页面 | 看什么 |
|---|---|
| 今日训练 | 四条路线是不是只显示了有意义的？本周进度对不对？题库空时的引导说得清楚吗？ |
| 训练题库 | 导入真实题库文件能成功吗？警告有没有显示出来？按 Part 筛选对不对？ |
| 复盘报告 | 之前那次练习的复盘能显示吗？分区顺序合理吗？NEXT SINGLE TARGET 醒目吗？ |
| 未实现的七页 | 占位文字说清「还没做」和「将来会有什么」了吗？ |

- [ ] **Step 4: 走一遍完整练习（本阶段的成败判据）**

**把终端关掉**，只用 App：

1. 导入真实的 PDF 题库 → 题目数量和内容是否正确
2. 在今日训练页点「开始」→ **数一下从双击图标到 ChatGPT 开口，一共点了几次**（目标 ≤ 3）
3. 等待期间盯着界面：**9 秒的语音启动过程中，界面有没有一直在说它在干什么**
4. 真的练一场，练完点「我练完了」
5. 复盘有没有自动取回并归档？错题本、词汇本、重训目标三处数字有没有从 0 变正？

**这一步一旦走通，成品标准第 1、2、3、4 条就同时达成了**——这是 Phase 3 真正的交付物，不是三个页面。

- [ ] **Step 5: 界面验收（对照 DESIGN-SYSTEM.md 第 6 节）**

逐条走那十条清单。其中三条最容易被忽略、也最影响观感：

- 系统「减弱动态效果」打开后，界面是否无动画且功能正常
- 系统文字调到最大时，是否不截断、不重叠
- 统计数字变化时是否不抖动（等宽数字）

- [ ] **Step 6: 记录并提交**

把每项的实际结果写进 `docs/phase3-acceptance.md`，含截图或原文描述。**包括不好的部分**——「哪里让我不想用」这类信息只有你有（成品标准第 5 节）。

```bash
git add docs/
git commit -m "docs: Phase 3 真机验收结果"
```

---

## Phase 3 完成标准

- [ ] `swift test` 全绿，且总耗时在 2 秒以内
- [ ] `./scripts/build-app.sh` 产出可双击打开的 `.app`
- [ ] **连续两次打包，`codesign -d -r-` 的 designated 完全一致**
- [ ] 授权一次之后，重新打包不需要再次授权
- [ ] 今日训练、训练题库、复盘报告三页可用
- [ ] 未实现的七页显示有意义的占位，而非空白
- [ ] 每个视图模型的关键逻辑都经突变验证确认测试有约束力
- [ ] **PDF 题库能导入，题目数量与内容经人工核对**
- [ ] **关掉终端，只用界面就能完整练一场并自动归档**
- [ ] **`DESIGN-SYSTEM.md` 第 6 节十条验收清单全部通过**

达成后进 Phase 4：逐字稿采集 + 训练记录页。

**Phase 3 与初版计划的差别：** 驱动接入（Task 9）本来排在 Phase 4，PDF 导入（Task 8）本来没排。这两条不做，Phase 3 交付的是「三个好看但点了没用的页面」，且用户连题都没得练。设计令牌（Task 7）是把「界面要美丽」变成可验证的东西——十条清单、五个可自动跑的对比度测试，而不是一句主观评价。
