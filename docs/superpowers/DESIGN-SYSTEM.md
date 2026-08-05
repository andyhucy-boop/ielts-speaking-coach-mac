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

| 用途 | SwiftUI | 近似字号 | 字重 |
|---|---|---|---|
| 页面大标题 | `.largeTitle` | 26 | `.bold` |
| 区块标题 | `.title2` | 17 | `.semibold` |
| 卡片标题 | `.headline` | 13 | `.semibold` |
| 正文 | `.body` | 13 | `.regular` |
| 次要说明 | `.callout` | 12 | `.regular` |
| 小标签 | `.caption` | 11 | `.medium` |
| 数字（统计、时长）| `.title` + `.monospacedDigit()` | 22 | `.semibold` |

**统计数字必须用等宽数字**（`.monospacedDigit()`）。否则「本周 3/5 次」跳到「本周 10/5 次」时整行会抖动。

**这张表已落成 `Typography` 令牌**（`Sources/IELTSCoachUI/DesignSystem/Typography.swift`），一行一个令牌。**视图里请引用令牌，不要直接写语义字体，也不要单独加字重。**

理由是这张表的第四列：SwiftUI 只有一部分语义字体自带字重（`.headline` 是 semibold），`.caption`、`.title`、`.largeTitle` 默认都是 regular。写 `.font(.caption)` 编得过也跑得动，只是比表里的 medium 轻一档，而这种差别没人能在截图上指出来——Phase 3 的 `SectionHeader` 就这么掉过一次。现在两条测试守着：`testTypographyTokensMatchTheSpecTable` 逐行比对令牌与本表，`testDesignSystemTakesFontsFromTypographyTokens` 扫 `DesignSystem/` 的源码不许视图自己拼字体。

---

## 2. 颜色

从设计稿提取。**全部定义为语义令牌**，视图里只能引用令牌名。

```swift
public enum Palette {
    // 品牌主色。设计稿里的紫色，用于主按钮、选中态、强调数字
    public static let accent = Color(red: 0.361, green: 0.318, blue: 0.910)      // #5C51E8

    // 侧边栏。设计稿里的深色导航条
    public static let sidebarBackground = Color(red: 0.133, green: 0.118, blue: 0.239)  // #221E3D
    public static let sidebarText = Color.white.opacity(0.72)
    public static let sidebarTextSelected = Color.white

    // 内容区
    public static let canvas = Color(red: 0.957, green: 0.957, blue: 0.969)      // #F4F4F7
    public static let card = Color.white
    public static let cardBorder = Color.black.opacity(0.08)

    // 文字
    public static let textPrimary = Color(red: 0.07, green: 0.07, blue: 0.09)    // #121217
    public static let textSecondary = Color.black.opacity(0.56)
    public static let textOnAccent = Color.white

    // 语义。**取值已按实测对比度调深过，见下方说明**
    public static let success = Color(red: 0.09, green: 0.50, blue: 0.27)   // 约 5.02:1 / 4.58:1
    public static let warning = Color(red: 0.60, green: 0.39, blue: 0.02)   // 约 5.05:1 / 4.60:1
    public static let danger = Color(red: 0.80, green: 0.20, blue: 0.20)    // 约 5.14:1 / 4.68:1
}
```

**语义色为什么比设计稿深（2026-08-06 实测修正）：** 设计稿里的绿是 3.64:1、橙只有 2.72:1，
都进不了下面那条「不可协商」的 4.5:1。这两个颜色不是装饰——它们要承载中文正文
（例如「本周已完成」「这份 PDF 可能是扫描件」），读不清就是缺陷。所以调深到刚过线，
色相保持不变。**看着比设计稿沉一点是刻意的，不是调色失误。**

> ### ⚠️ 上面 `success` 与 `warning` 两个取值不达标（2026-08-06 跨阶段复审记，**待用户确认后改写本节**）
>
> 按下面「对比度底线」那张表实测：
>
> | 令牌 | 上面写的 | 对白卡片 | 对内容区底色 | 建议改成 | 改后 |
> |---|---|---|---|---|---|
> | `success` | `(0.13, 0.60, 0.35)` | **3.64:1** | 3.44:1 | `(0.09, 0.50, 0.27)` | 约 5.02:1 / 4.58:1 |
> | `warning` | `(0.85, 0.55, 0.10)` | **2.72:1** | 2.57:1 | `(0.60, 0.39, 0.02)` | 约 5.05:1 / 4.60:1 |
>
> 两者都低于本节那条「不可协商」的 4.5:1，而 **Phase 8 明确要用 `Palette.warning` 显示一段中文正文**——那是正文，不是装饰。`danger`（约 5.14:1）达标，不动。
>
> **Phase 3 Task 7 与 Phase 10 Task 12 都已按建议值实现，并有测试拦着。**
> 改后的颜色在浅色下会明显更深；**用户确认观感之后，把上面代码块里那两行直接改掉、删掉本注记**。
> 若用户想换别的取值，唯一前提是仍 ≥ 4.5:1。

### 深色模式

**Phase 3 只做浅色，但所有颜色必须走令牌**，这样加深色模式时只改这一个文件，不用翻遍所有视图。

**不要用反色实现深色模式**——深色下要用降饱和的色调变体，并单独验证对比度。

> **归属更正（2026-08-06）：** 本节原写「Phase 7 加深色模式」。Phase 7 明确没做，8/9 也没接。
> 跨阶段决策 7 已把深色模式收口到 **Phase 10 Task 12 / 13**：两套静态取值（`Palette.light` / `Palette.dark`）
> + 跟随系统外观的动态令牌，**不提供手动切换**（理由见 Phase 10 Task 13）。

### 对比度底线（不可协商）

| 组合 | 最低比值 |
|---|---|
| 正文 vs 背景 | 4.5:1 |
| 次要文字 vs 背景 | 4.5:1（**不是 3:1**——次要文字仍是要读的）|
| 大标题、图标 vs 背景 | 3:1 |

**`textSecondary` 用 56% 黑而不是常见的 40%**，就是为了守住 4.5:1。灰上加灰是让界面显廉价的头号原因。

**算对比度时必须先按 alpha 把前景合成到背景上，再算亮度。** `Color.black.opacity(0.56)` 的三个分量是**纯黑**，透明度全在 alpha 上——直接拿分量算会得到 21:1，而它在屏幕上只有 4.94:1。忽略 alpha 的对比度测试对每一个半透明令牌都是空转的，包括上面这条「56% 而不是 40%」本身。

这三条底线现在由 `Tests/IELTSCoachUITests/DesignSystemTests.swift`（Phase 3，浅色）与 `Tests/IELTSCoachUITests/AppearanceContrastTests.swift`（Phase 10，两套外观的完整矩阵）逐对验证，不再靠目测。

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
    public static let card: CGFloat = 12
    public static let control: CGFloat = 8
    public static let pill: CGFloat = 999
}
```

**页面内边距统一 `Spacing.xl`（32）**，卡片内边距 `Spacing.lg`（24）。设计稿里的留白很足，这是它显得高级的主要原因——**不要为了多塞内容压缩留白**。

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

**必须尊重「减弱动态效果」系统设置**（`@Environment(\.accessibilityReduceMotion)`）。开启时禁用所有过渡。

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

最后一条最容易被忽略，也最容易被察觉——**抖动的数字会让整个界面显得廉价**。
