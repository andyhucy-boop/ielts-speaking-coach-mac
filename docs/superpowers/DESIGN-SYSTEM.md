# 设计规范

日期：2026-08-05
基准：用户提供的产品设计稿（六页真实界面截图）

**这份文件是界面的唯一视觉依据。** 所有页面必须从这里取值，不得在视图里写字面颜色、字号、圆角。

---

## 0. 为什么不用通用设计工具给的推荐

用设计推荐工具跑过一次，它按「education / learning」推出的是 **Claymorphism + Baloo 2 + Comic Neue**，定位「儿童教育 App、教育游戏」。

**不采用。** 理由：

- 用户是成年备考者，不是儿童。圆滚滚的糖果风会削弱这个工具的严肃感
- **用户已经有设计稿**，那份稿子定义的是克制、专业、以内容为主的工作台风格
- 通用推荐不知道这个产品的具体语境

从通用规则里**保留**的部分：对比度门槛、状态可辨识性、间距节奏、无障碍要求。这些与风格无关，是底线。

---

## 1. 字体：用系统字体，不引入外部字体

**统一使用 SF Pro（macOS 系统字体），通过 SwiftUI 的语义字体取用。**

理由：

1. 原生 Mac 应用用系统字体才「像 Mac 应用」，换成 Web 字体会立刻显出违和
2. 系统字体自动支持动态字号，用户在系统里调大文字时界面不会崩
3. 不用打包字体文件，也没有授权问题

| 令牌 | 用途 | SwiftUI | 近似字号 | 字重 | 行距 |
|---|---|---|---|---|---|
| `pageTitle` | 页面大标题 | `.largeTitle` | 26 | `.bold` | `tight` |
| `sectionTitle` | 区块标题 | `.title2` | 17 | `.semibold` | `tight` |
| `cardTitle` | 卡片标题 | `.title3` | 15 | `.semibold` | `tight` |
| `lede` | 引导语、要逐字读的例句 | `.title3` | 15 | `.regular` | `body` |
| `rowTitle` | 密排列表的行标题 | `.headline` | 13 | `.semibold` | `tight` |
| `body` | 正文 | `.body` | 13 | `.regular` | `body` |
| `secondary` | 次要说明 | `.callout` | 12 | `.regular` | `body` |
| `label` | 小标签 | `.caption` | 11 | `.medium` | `tight` |
| `overline` | 区块眉标（`01 TODAY`）| `.caption2` | 10 | `.semibold` | `tight` |
| `navItem` | 侧边栏一项 | `.body` | 13 | `.medium` | `tight` |
| `action` | 按钮文字 | `.headline` | 13 | `.semibold` | `tight` |
| `number` | 统计数字、时长 | `.title` + `.monospacedDigit()` | 22 | `.semibold` | — |
| `numberHero` | 一屏里最大的那个数字 | `.largeTitle` + `.monospacedDigit()` | 26 | `.bold` | — |

### 2026-08-30 改版：把「全是 13 磅」拆开

改版前只有七档，而其中 `cardTitle`（`.headline`）与 `body`（`.body`）**在 macOS 上是同一个字号**，
只差一档字重；`secondary` 12、`label` 11 又紧挨着它们。于是整页从卡片标题到脚注全落在
11–13 磅这一条窄缝里，层级只能靠颜色深浅去分——**这是改版前界面显得平、显得糊的头号原因**。

改法是把标题那一档整体抬高一级（`cardTitle` 13 → 15），并补上两头：`lede`（15 regular）
撑开需要逐字读的地方，`overline`（10 semibold）收紧眉标。
改完的层级是 26 / 22 / 17 / 15 / 13 / 12 / 11 / 10，每一档之间都看得出差别。

`testTheTypeScaleActuallySeparatesItsTiers` 守着这条：同字重的档位里任意两档不许取同一个值。
上面那张表只钉得住「每一档是什么」，钉不住「这几档还分不分得开」。

### 行距：中文段落必须加

SwiftUI 的默认行距是按拉丁文字定的，中文方块字在同样的行距下会贴在一起——一段五行的中文说明
读起来像一堵墙，而这个 App 的界面文字**绝大多数是中文长句**（每条错误信息都要写清
「发生了什么 + 下一步做什么」）。

```swift
public enum LineHeight {
    public static let tight: CGFloat = 0    // 标题、单行标签：不额外加
    public static let body: CGFloat = 5     // 中文正文，13pt 上约合 1.4 倍
    public static let relaxed: CGFloat = 8  // 需要逐字读的长段，约 1.55 倍
}
```

视图用 `.coachParagraph()`（`Components.swift`）而不是自己写 `.lineSpacing(5)`：
那个修饰符连 `fixedSize` 一起带上，省得每处各记一次「中文段落还要防截断」。

**`tight` 是 0，写出来是刻意的**：让「这一处不加行距」这件事在代码里看得见，
而不是靠「没写就是没有」。


**统计数字必须用等宽数字**（`.monospacedDigit()`）。否则「本周 3/5 次」跳到「本周 10/5 次」时整行会抖动。

**这张表已落成 `Typography` 令牌**（`Sources/IELTSCoachUI/DesignSystem/Typography.swift`），一行一个令牌。**视图里请引用令牌，不要直接写语义字体，也不要单独加字重。**

理由是这张表的第四列：SwiftUI 只有一部分语义字体自带字重（`.headline` 是 semibold），`.caption`、`.title`、`.largeTitle` 默认都是 regular。写 `.font(.caption)` 编得过也跑得动，只是比表里的 medium 轻一档，而这种差别没人能在截图上指出来——Phase 3 的 `SectionHeader` 就这么掉过一次。现在两条测试守着：`testTypographyTokensMatchTheSpecTable` 逐行比对令牌与本表，`testDesignSystemTakesFontsFromTypographyTokens` 扫 `DesignSystem/` 的源码不许视图自己拼字体。

---

## 2. 颜色

从设计稿提取。**全部定义为语义令牌**，视图里只能引用令牌名。

**两套静态取值 + 一组随系统外观解析的动态令牌**（Phase 10 Task 12）。视图只引用
`Palette.accent` 那一组动态令牌，一行都不用管当前是浅色还是深色；测试只认
`Palette.light` / `Palette.dark` 这两套静态值——动态颜色会按「跑测试那一刻的系统外观」
解析，拿它去算对比度的话，「深色的对比度测试」在浅色机器上永远是绿的。

```swift
public enum Appearance: String, CaseIterable, Sendable { case light, dark }

public struct PaletteTokens: Equatable, Sendable {
    public let accent: Color
    public let sidebarBackground, sidebarHighlight: Color
    public let sidebarText, sidebarTextSelected: Color
    public let canvas, card, surfaceSubtle, accentSoft: Color
    public let cardBorder, cardBorderStrong: Color
    public let textPrimary, textSecondary, textOnAccent: Color
    public let success, warning, danger: Color
}

public enum Palette {
    public static let light = PaletteTokens(
        accent: Color(red: 0.361, green: 0.318, blue: 0.910),            // #5C51E8
        sidebarBackground: Color(red: 0.133, green: 0.118, blue: 0.239), // #221E3D
        sidebarHighlight: Color(red: 0.180, green: 0.161, blue: 0.314),  // 选中/悬停那一行的底
        sidebarText: Color.white.opacity(0.72),                          // 对侧边栏底 8.85:1
        sidebarTextSelected: .white,                                     // 15.96:1
        canvas: Color(red: 0.957, green: 0.957, blue: 0.969),            // #F4F4F7
        card: .white,
        surfaceSubtle: Color(red: 0.945, green: 0.945, blue: 0.965),     // #F1F1F6
        accentSoft: Color(red: 0.941, green: 0.937, blue: 0.992),        // #F0EFFD，主色 4.86:1
        cardBorder: Color.black.opacity(0.08),
        cardBorderStrong: Color.black.opacity(0.16),                     // 悬停 / 选中
        textPrimary: Color(red: 0.07, green: 0.07, blue: 0.09),          // 对卡片 18.82:1
        textSecondary: Color.black.opacity(0.56),                        // 对卡片 4.94:1
        textOnAccent: .white,                                            // 对主色 5.53:1
        success: Color(red: 0.08, green: 0.46, blue: 0.25),              // 最暗底 5.07:1
        warning: Color(red: 0.55, green: 0.355, blue: 0.02),             // 最暗底 5.16:1
        danger: Color(red: 0.75, green: 0.18, blue: 0.18))               // 最暗底 5.09:1

    /// 深色。**每一个值都是降饱和的色调变体，不是反色。**
    public static let dark = PaletteTokens(
        accent: Color(red: 0.651, green: 0.631, blue: 0.878),            // 对卡片 6.94:1
        sidebarBackground: Color(red: 0.106, green: 0.094, blue: 0.188),
        sidebarHighlight: Color(red: 0.133, green: 0.118, blue: 0.220),
        sidebarText: Color.white.opacity(0.78),                          // 对侧边栏底 10.86:1
        sidebarTextSelected: .white,                                     // 17.22:1
        canvas: Color(red: 0.078, green: 0.078, blue: 0.102),
        card: Color(red: 0.118, green: 0.118, blue: 0.149),              // 比底色亮，卡片才不是个洞
        surfaceSubtle: Color(red: 0.149, green: 0.149, blue: 0.184),     // 又亮一档，嵌在卡片里
        accentSoft: Color(red: 0.165, green: 0.153, blue: 0.263),        // 主色 5.98:1
        cardBorder: Color.white.opacity(0.14),
        cardBorderStrong: Color.white.opacity(0.26),
        textPrimary: Color(red: 0.929, green: 0.929, blue: 0.949),       // 对卡片 14.07:1
        textSecondary: Color.white.opacity(0.70),                        // 对卡片 8.69:1
        textOnAccent: Color(red: 0.078, green: 0.078, blue: 0.102),      // 对主色 7.74:1
        success: Color(red: 0.42, green: 0.79, blue: 0.56),
        warning: Color(red: 0.95, green: 0.74, blue: 0.35),
        danger: Color(red: 0.98, green: 0.53, blue: 0.51))

    public static func tokens(for appearance: Appearance) -> PaletteTokens { … }

    // 视图用这一组：名字与类型跟以前完全一样，只是会跟着系统外观自己解析。
    public static let accent = dynamic(\.accent)   // …以下 16 个同理
}
```

### 2026-08-30 改版新增的四个令牌

改版前只有两级底色（`canvas` 灰、`card` 白），**没有第三级**——于是「卡片里再嵌一块」
这种再普通不过的层次做不出来，所有内容只能平铺在白卡片上，一节六条读下来像一份日志。
四个新令牌各解决一件事：

| 令牌 | 干什么 | 哪儿在用 |
|---|---|---|
| `surfaceSubtle` | 卡片**里面**再低一档的底 | 复盘行里「原话 → 改成什么」那一对、悬停行、柱状图底槽 |
| `accentSoft` | 主色的浅底，配主色文字 | `CoachBadge(kind: .accent)`、Part 标记 |
| `cardBorderStrong` | 悬停 / 选中时那一档边框 | `CoachActionCard`、列表行 |
| `sidebarHighlight` | 侧边栏选中 / 悬停那一行的底 | `SidebarRow` |

**`sidebarHighlight` 顺带修掉一处深色下的失守：** 侧边栏选中行原本打算用 `accent` 作底 +
白字，而深色的 `accent` 是调亮过的 `#A6A1E0`，白字压上去只有 **2.39:1**。
现在选中标记是「`sidebarHighlight` 底 + 主色竖条」，两套外观下白字都在 13:1 以上。

**语义色（success / warning / danger）在浅色下比上一版再深了约一档**
（例如 success `(0.09,0.50,0.27)` → `(0.08,0.46,0.25)`）。原值只在 `card` / `canvas` 上刚过
4.5:1（4.61），压到新的 `surfaceSubtle` 上就掉到 4.45——而那正是新版复盘行的底色。
现在三个都在最暗的底上仍有 5.07:1 以上的余量。**看着比上一版再沉一点是刻意的。**


**语义色为什么比设计稿深（2026-08-06 实测修正）：** 设计稿里的绿是 3.64:1、橙只有 2.72:1，
都进不了下面那条「不可协商」的 4.5:1。这两个颜色不是装饰——它们要承载中文正文
（例如「本周已完成」「这份 PDF 可能是扫描件」），读不清就是缺陷。所以调深到刚过线，
色相保持不变。**看着比设计稿沉一点是刻意的，不是调色失误。**

**深色下这两个色反而调亮并降了饱和**（success `(0.42, 0.79, 0.56)`、warning
`(0.95, 0.74, 0.35)`）：同一个色相在近黑底色上要往亮的一侧走才读得清。
深色主色也因此翻了一次面——主色调亮到 `#A6A1E0` 之后，压在它上面的文字必须是近黑，
白字只有 2.7:1。一个令牌不可能同时满足「主色当文字用」和「白字压在主色上」。

### 深色模式

**Phase 10 Task 12 已实现**：两套静态取值（`Palette.light` / `Palette.dark`）+ 跟随系统外观的动态令牌，
**不提供手动切换**（理由见 Phase 10 Task 13）。视图侧一行都不用改——`Palette.accent` 那一组名字与类型
都没变，只是改成由 AppKit 的动态颜色在绘制时按当前外观解析。

Phase 3 那条「所有颜色必须走令牌」的规矩，回报就在这里：深色模式只改了 `Palette.swift` 一个文件。

**不要用反色实现深色模式**——深色下要用降饱和的色调变体，并单独验证对比度。上面那两套取值就是照这条做的：
深色主色是调亮并降饱和的同色相变体（`#A6A1E0`），不是 `1 − 浅色主色`；
`AppearanceContrastTests.testTheDarkPaletteIsNotJustTheLightOneInverted` 逐通道拦着这条。

### 对比度底线（不可协商）

| 组合 | 最低比值 |
|---|---|
| 正文 vs 背景 | 4.5:1 |
| 次要文字 vs 背景 | 4.5:1（**不是 3:1**——次要文字仍是要读的）|
| 大标题、图标 vs 背景 | 3:1 |

**`textSecondary` 用 56% 黑而不是常见的 40%**，就是为了守住 4.5:1。灰上加灰是让界面显廉价的头号原因。

**算对比度时必须先按 alpha 把前景合成到背景上，再算亮度。** `Color.black.opacity(0.56)` 的三个分量是**纯黑**，透明度全在 alpha 上——直接拿分量算会得到 21:1，而它在屏幕上只有 4.94:1。忽略 alpha 的对比度测试对每一个半透明令牌都是空转的，包括上面这条「56% 而不是 40%」本身。这套算法收在 `Sources/IELTSCoachUI/DesignSystem/ContrastMath.swift`，一处实现、两套外观共用。

**已实测：** 把 `ContrastMath.ratio` 里那三行合成删掉，再把 `textSecondary` 从 56% 调到 40%，整条矩阵照样全绿（40% 黑的分量同样是纯黑，还是算成 21:1）；把合成加回来，同一个 40% 当场报出「light 的「次要文字 vs 卡片」只有 2.85:1」。

这三条底线现在由 `Tests/IELTSCoachUITests/AppearanceContrastTests.swift`（两套外观 × 15 组配对的完整矩阵）逐对验证，不再靠目测。Phase 3 留在 `DesignSystemTests.swift` 里的那几条浅色对比度断言已经并进这份矩阵——矩阵对浅色跑的是同样的配对，外加深色那一半，「每个令牌都必须被显式归类」那条完整性守卫也一起搬了过去。

---

## 3. 间距与圆角

统一 4 的倍数。

```swift
public enum Spacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let section: CGFloat = 40   // 大区块之间
}

public enum Radius {
    public static let panel: CGFloat = 16     // 页面级大面板
    public static let card: CGFloat = 12
    public static let control: CGFloat = 8
    public static let pill: CGFloat = 999
}
```

**页面内边距统一 `Spacing.xl`（32）**，卡片内边距 `Spacing.lg`（24）。设计稿里的留白很足，这是它显得高级的主要原因——**不要为了多塞内容压缩留白**。

圆角要跟着面积走：同一个 12 贴在 1000pt 宽的面板上和贴在 200pt 的小卡上看着不是一回事，
所以页面级的大面板（首屏主行动卡、复盘页顶上那条目标横幅）用 `panel`（16）。

### 版面尺寸（2026-08-30 新增）

```swift
public enum Layout {
    public static let readingMaxWidth: CGFloat = 720   // 连续段落
    public static let contentMaxWidth: CGFloat = 1040  // 页面内容整体
    public static let sidebarWidth: CGFloat = 220
    public static let railWidth: CGFloat = 4
    public static let minWindowWidth: CGFloat = 960
    public static let minWindowHeight: CGFloat = 640
}
```

**`readingMaxWidth` 是这次改版里效果最大的一个令牌。** 改版前整个 App 一处宽度限制都没有，
窗口拉到 1728pt 时：

- 复盘报告的中文段落一行 1100pt、上百个字——眼睛读完一行找不回下一行的行首；
- 每张卡片被拉成一千点宽的长条，标题贴在最左、按钮被 `Spacer` 顶到最右，中间空出九百多点。
  卡片本来就长得像能点的东西，用户第一下多半点在卡片上，然后什么也不发生。

两档而不是一档：**正文要窄（读），列表与网格可以宽（扫）**。
页面用 `CoachPage` 或 `.coachPageBody()` 套上 `contentMaxWidth` 并居中；
段落另外用 `.coachReadingColumn()` 收到 `readingMaxWidth`。

---

## 4. 组件规范

### 卡片 `CoachCard`

白底、圆角 12、发丝边框、**不加投影**。

设计稿里的卡片靠边框和留白分层，不靠阴影。滥用投影是让界面显脏的常见原因。

```swift
.background(Palette.card)
.clipShape(RoundedRectangle(cornerRadius: Radius.card))
.overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.cardBorder, lineWidth: 1))
```

### 主行动卡片 `PrimaryActionCard`

紫色填充、白字，用于「今天想怎么练？」那块。

**每个页面最多一个主行动。** 其余动作必须在视觉上明确次一级——两个同样醒目的紫色大块会让人不知道该点哪个。

### 区块标题

设计稿的写法：小号编号 + 全大写英文标签 + 中文标题。

```
01  PRACTICE ROUTES
今天练什么？
```

编号与英文标签用 `.caption` + `Palette.textSecondary` + 字距略宽；中文标题用 `.title2`。

### 空状态（必须有，不能留白）

任何列表为空时都要给三样东西：**一句说明现状、一句说明下一步、一个能直接点的按钮**。

```
题库还是空的
先导入你的雅思口语题库，才能开始练习。
[ 导入题库… ]
```

**空白页会让用户以为程序坏了**——这条在本项目已经写进硬性约束（错误信息必须说清「发生了什么 + 下一步做什么」），空状态同理。

### 整块可点的卡片 `CoachActionCard` / `PrimaryActionCard`

一张卡片如果代表一个动作，**整块都要能点**，右边给一个 `chevron.right` 作提示，并且必须有悬停反馈。

理由见上面 `readingMaxWidth` 那一段：把动作藏在一颗离标题九百点远的小按钮里，
既难点，又让人以为卡片本身是死的。

### 提示 `NoticeCard`

图标 + 文字（+ 可选按钮），按语气分 info / success / warning / danger 四种。

**不许在页面里手搓。** 改版前这块在六个地方各写了一遍，图标、间距、边框各不相同，
而它承载的恰恰是本项目最要紧的那类文字——「发生了什么 + 下一步做什么」。

### 标记 `CoachBadge`

`Part 1`、`没练过`、`6 条` 这类状态词用胶囊，不要用一行小灰字跟在标题后面：
一屏几十行的列表里，跟在后面的小灰字扫一眼分不出哪个是内容、哪个是状态。

### 侧边栏

深色（`sidebarBackground`），**按用途分组**，每一项都要有悬停反馈。
选中标记有两样：左边那道主色竖条 + 底色换成 `sidebarHighlight`——
只靠底色的话「选中」和「鼠标正悬在上面」长得一样；只靠竖条则是纯颜色信息。

> 2026-08-30 之前，这条侧边栏是一个系统默认样式的 `List`：
> 上面那四个为它定好、而且逐项验过对比度的令牌**一个都没被用过**。
> 也就是说这个 App 最显眼的那一块，此前从没有被设计过。

### 液态玻璃（macOS 26 起）

用 `.coachGlass(tint:fallback:interactive:in:)`。macOS 26 以下自动回落成不透明底色。

**只用在「浮在有颜色的面板上的浮层」**——目前恰好三处：

- 侧边栏里选中/悬停那颗药丸（浮在我们自己铺好的深色底上）
- 主行动卡片上那颗「开始练习」（浮在主色面板上）
- 复盘页目标横幅上那颗「带着这条去复训」（浮在深色面板上）

**卡片、提示卡、页面正文一律不用。** 它们贴在一整片纯色底上，背后什么都没有，
玻璃在那儿只会变成一层灰蒙蒙的膜——既没有效果，又让本来验过 4.5:1 的文字底色
变成了半透明的未知数。

#### 整片侧边栏用玻璃：试过，否掉了（2026-08-30 实测）

想法很自然：侧边栏浮在桌面之上，这是 macOS 上玻璃最经典的用法。
先按「tint 的不透明度盖在纯白壁纸上」算了一遍，得出 0.80 时最坏情况仍有 5.27:1，
看着是安全的。

**做出来之后从实机截图上采样，那片区域是 `rgb(219,219,220)`——浅灰。**

原因：`Glass.tint(_:)` 是给材质**上色**，不是按不透明度把颜色压上去。
传一个 alpha 0.92 的深紫进去，渲染出来仍然是浅色。也就是说那个算法从一开始
就不适用，算得再准也没用。后果是这条深色侧边栏在浅色壁纸下整片变浅、白字糊成一片，
**而在开发者自己的深色壁纸上完全看不出来。**

结论写成一条硬规矩：**玻璃跟着背后的东西走，所以它只能当浮层，不能当承载文字的底。**
承载文字的那一层必须是我们自己铺的、进过对比度矩阵的不透明令牌。
`AppearanceContrastTests.testTheSidebarSurfaceItselfIsOpaqueAndOnlyThePillIsGlass` 守着这条。

> 顺带记一笔：换成玻璃之后，侧边栏里未选中的行当场现出十个深色小药丸——
> 那是一句给未选中行也铺了底色的旧代码，在不透明底下一直是隐形的。
> **换底会让这一类「一直躺在那儿」的缺陷现形**，值得每次都看一眼实机截图。

### 图标

**只用 SF Symbols，不用 emoji。** emoji 在不同系统版本渲染不一致，也无法跟随语义颜色。

同一层级只用一种风格（都用线性或都用填充），尺寸统一 16/20/24 三档。

---

## 5. 交互与动效

**克制。** 这是个学习工具，不是展示品——动效的作用是让状态变化可理解，不是让人觉得炫。

| 规则 | 值 |
|---|---|
| 微交互时长 | 150–250ms |
| 缓动 | 进场 `.easeOut`，出场 `.easeIn` |
| 同屏动画元素 | 最多 1–2 个 |
| 禁止 | 纯装饰性动画、循环浮动、视差 |

```swift
public enum Motion {
    public static let quick: Double = 0.16       // 悬停、按下
    public static let standard: Double = 0.22    // 展开、切换、内容替换
    public static let deliberate: Double = 0.32  // 整屏过渡，上限就是它
}
```

**必须尊重「减弱动态效果」系统设置**（`@Environment(\.accessibilityReduceMotion)`）。开启时禁用所有过渡。

**视图不要自己写 `.animation(...)`，用 `.coachAnimation(_:value:)`**（`Components.swift`）：
那个修饰符自己读「减弱动态效果」，于是这条无障碍要求由构造保证。
从前它靠每个调用点记得写 `reduceMotion ? nil : …` 这个三元表达式，
而漏写的那一处不会报错、不会变红，只会在开了那个开关的人机器上照样动。

### 悬停（桌面应用的硬要求）

改版前全项目**一处 `onHover` 都没有**：所有卡片、所有列表行、整条侧边栏，
鼠标划过去毫无反应。在 Mac 上这会让界面显得是一张图片而不是一个程序。

现在可点的东西都要有悬停反馈，而且**不用投影**（第 4 节禁止投影）：
底色换 `surfaceSubtle`、边框换 `cardBorderStrong`，主色面板上则是加一圈白边。

### 键盘与焦点

这是桌面应用，**键盘可达性不是可选项**：

- 所有可点击元素必须能用 Tab 到达，且**焦点环可见**（不许为了好看去掉焦点环）
- Tab 顺序与视觉顺序一致
- 主要动作有快捷键（如 `⌘N` 开始新练习）

### 长时操作必须有进度

启动语音实测需约 9 秒（spec 2.3.7）。**这 9 秒里界面必须一直在说话**：

```
▸ 正在新建会话…
▸ 正在启动语音…（这一步约需 10 秒）
▸ 正在把考官提示词发过去…
```

超过 300ms 的操作都要有反馈。**对着不动的界面等 9 秒，用户会以为死机了。**

---

## 6. 验收清单

界面完成后逐条验：

- [ ] 视图里没有任何字面颜色值、字号、圆角——全部走令牌
- [ ] 正文与次要文字对比度都 ≥ 4.5:1（用取色工具实测，不靠目测）
- [ ] 没有 emoji 当图标
- [ ] 每个列表的空状态都有「说明 + 下一步 + 按钮」
- [ ] 每页只有一个主行动
- [ ] Tab 能走遍所有可点元素，焦点环可见
- [ ] 打开系统「减弱动态效果」后，界面无动画且功能正常
- [ ] 系统文字调到最大时，界面不截断、不重叠
- [ ] 所有超过 300ms 的操作都有进度提示
- [ ] 统计数字用等宽数字，数值变化时不抖动
- [ ] **没有任何一段正文能横着长过 `readingMaxWidth`**（把窗口拉到最宽再看一遍）
- [ ] 每个可点的卡片/行都有悬停反馈，且整块可点（不是只有角落那颗按钮）
- [ ] 网格里同一行的卡片上下边各自齐平（`GridItem` 的纵向对齐默认是居中，要显式写 `.top`）

最后一条最容易被忽略，也最容易被察觉——**抖动的数字会让整个界面显得廉价**。
