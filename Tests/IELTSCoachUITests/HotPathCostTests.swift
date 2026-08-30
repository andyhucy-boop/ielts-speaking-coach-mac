import Foundation
import XCTest

@testable import IELTSCoachUI

/// 守「重绘热路径上不许干重活」。
///
/// ## 为什么需要这一组
///
/// 这一类缺陷**不会让任何测试变红**：结果完全正确，只是慢。它也不会在开发时被发现——
/// 开发机上的数据量往往比真实用户小。2026-08-30 的一次审计实测出三处叠在一起的后果：
/// 问题档案页点一下筛选按钮，窗口冻约 **0.5 秒**。
///
/// 三处分别是：
///   1. `CoachTime.parse` 每次调用新建两个 `ISO8601DateFormatter`（实测每个约 34–46 µs）；
///   2. 那个 `parse` 被放在**排序比较器**里，于是解析次数从 n 变成「比较次数 × 2」；
///   3. 页面的 `model` 是计算属性，一次 body 求值构造四次视图模型。
///
/// 单独看每一处都像小事，乘起来是半秒。所以三处各配一条守卫。
final class HotPathCostTests: XCTestCase {

    /// **`CoachTime` 里的 formatter 必须是复用的，不许在函数体里现造。**
    ///
    /// 实测：`ISO8601DateFormatter()` 一次分配约 34–46 µs，而 `parse` 从前每次造两个
    /// （还先试注定失败的那个）。改成复用之后，同一个时间戳的解析
    /// 从 148.7 µs 降到 21.7 µs（快 7 倍）。
    ///
    /// 这条扫的是「函数体里有没有构造」，不是跑分——跑分在 CI 上会随机变红，
    /// 而这个退化的形状是固定的：谁把构造挪回函数体里，这里当场变红。
    func testCoachTimeReusesItsFormattersInsteadOfBuildingThemPerCall() throws {
        let code = try SourceGuard.repositoryCode("Sources/IELTSCoachCore/CoachTime.swift")

        for function in ["parse", "parseDayPrefix"] {
            let body = try SourceGuard.functionBody(named: function, in: code)
            for expensive in ["ISO8601DateFormatter(", "DateFormatter("] {
                XCTAssertFalse(
                    body.contains(expensive),
                    "`CoachTime.\(function)` 的函数体里现造了 `\(expensive)`。"
                        + "实测一次分配约 34–46 µs，而这个函数在重绘热路径上一次会被调几百次——"
                        + "问题档案页因此卡过半秒。"
                        + "下一步：改成复用那几个装在加锁盒子里的 formatter"
                        + "（`ISO8601Formatters` / `DayFormatter` / `ISO8601Writer`）。"
                        + "实际取到的函数体是：\n\(body)")
            }
        }

        // 反过来：盒子本身必须还在，否则上面那条可以靠「把整个功能删掉」通过。
        for box in ["ISO8601Formatters", "DayFormatter", "ISO8601Writer"] {
            XCTAssertTrue(code.contains("private static let"),
                          "`CoachTime` 里没有复用用的静态实例了")
            XCTAssertTrue(
                code.contains("final class \(box)"),
                "`CoachTime.\(box)` 不见了。上面那条「函数体里不许现造」会因此变成"
                    + "「把功能删光也算通过」。下一步：确认复用的盒子还在。")
        }
    }

    /// **`CoachTime.parse` 不许出现在排序比较器里。**
    ///
    /// 比较器会被调用 O(n log n) 次甚至更多——实测 30 条错题排一次要比较 393 次
    /// （错题按归档顺序追加，最旧的在前，几乎正好是想要的顺序的反向）。
    /// 每次比较解析两个时间戳，就是 786 次解析，而实际只需要 30 次。
    ///
    /// 正确写法是 decorate-sort-undecorate：先 `map` 出 `(元素, 解析好的 Date)`，
    /// 排序时只比已经算好的值。
    func testNoDateParsingInsideSortComparators() throws {
        var comparatorsChecked = 0
        for file in try SourceGuard.swiftFiles() {
            let path = try SourceGuard.relativePath(of: file)
            let code = try SourceGuard.code(path)
            for comparator in Self.sortComparators(in: code) {
                comparatorsChecked += 1
                XCTAssertFalse(
                    comparator.contains("CoachTime.parse"),
                    "\(path) 在排序比较器里调 `CoachTime.parse`。比较器会被调 O(n log n) 次，"
                        + "于是 n 次解析变成几百次（实测 30 条错题 → 786 次）。"
                        + "下一步：改成先解析再排序（decorate-sort-undecorate）——"
                        + "`let dated = xs.map { ($0, CoachTime.parse($0.someAt)) }`，"
                        + "比较器里只读 `.1`。实际取到的比较器是：\n\(comparator)")
            }
        }
        // 防空转：切分写坏了、一处比较器都切不出来时，上面那圈一次都不跑也是全绿。
        XCTAssertGreaterThanOrEqual(
            comparatorsChecked, 5,
            "只切出 \(comparatorsChecked) 处排序比较器，这条测试很可能在空转。"
                + "下一步：确认 `sortComparators(in:)` 还认得出 `.sorted {` / `.sort {` 的写法。")
    }

    /// 切出一个文件里**每一处**排序比较器的闭包体。
    ///
    /// 早先这里只取 `code.range(of: ".sorted {")` 的**第一处**，而且靠
    /// `tail.range(of: "\n        }")` 这个八空格缩进去找收尾：
    /// 一个文件里第二处排序完全不检查，缩进不是八空格的（嵌在闭包里的那些）
    /// 直接 `continue` 静默跳过。守卫的覆盖面比它宣称的窄得多，而且不会有任何迹象。
    ///
    /// 现在逐处扫，并且**按大括号配对**找收尾，不看缩进。
    private static func sortComparators(in code: String) -> [String] {
        var found: [String] = []
        for opener in [".sorted {", ".sort {", ".sorted(by: {", ".max(by: {", ".min(by: {"] {
            var searchFrom = code.startIndex
            while let hit = code.range(of: opener, range: searchFrom..<code.endIndex) {
                searchFrom = hit.upperBound
                // 从 `{` 之后开始数括号，数到配对的那个 `}` 为止。
                var depth = 1
                var index = hit.upperBound
                while index < code.endIndex, depth > 0 {
                    if code[index] == "{" { depth += 1 }
                    if code[index] == "}" { depth -= 1 }
                    if depth > 0 { index = code.index(after: index) }
                }
                found.append(String(code[hit.upperBound..<index]))
            }
        }
        return found
    }

    /// **题库那 163 张话题卡必须惰性构建。**
    ///
    /// 真实题库是 258 道题、163 个话题。普通 `VStack` 会在**每次重绘**时把 163 张
    /// `CoachCard`（每张带 clipShape + strokeBorder）、258 个题目行、几百个徽章全部建出来，
    /// 哪怕屏幕上只看得见十来张；而这一页的搜索框每敲一个字就重绘一次。
    ///
    /// ## 为什么不把这条推广到每一页
    ///
    /// `LazyVStack` 和 `ScrollViewReader.scrollTo` 相冲：还没建出来的行滚不过去。
    /// `PlanView`（滚到今天那一天）和 `RetrainingCenterView`（滚到刚选中的目标）都用了它，
    /// **那两页刻意保持非惰性**。所以这条只钉题库页——它没有 `ScrollViewReader`。
    /// 这一条下面那半段守的就是这个前提：哪天题库页加了 `ScrollViewReader`，
    /// 这里会提醒你重新想一遍。
    func testTheQuestionBankListIsLazyBecauseItIsHundredsOfCards() throws {
        let code = try SourceGuard.code("QuestionBank/QuestionBankView.swift")
        let bank = try SourceGuard.memberBody(of: "private func bank", in: code)

        XCTAssertTrue(
            bank.contains("LazyVStack"),
            "题库的话题列表不再是惰性构建。真实题库 163 个话题、258 道题，"
                + "普通 `VStack` 每次重绘都要把它们全部建一遍——而这一页的搜索框"
                + "每敲一个字就重绘一次。下一步：把那个 `ForEach(groups)` 包回 `LazyVStack`。"
                + "实际取到的是：\n\(bank)")

        XCTAssertFalse(
            code.contains("ScrollViewReader"),
            "题库页加了 `ScrollViewReader`。它和 `LazyVStack` 相冲——`scrollTo` 滚不到"
                + "还没建出来的行，而上面那条正要求这一页用 `LazyVStack`。"
                + "下一步：两者只能选一个；要滚动定位就得放弃惰性（`PlanView` 与 "
                + "`RetrainingCenterView` 就是这么选的），并把上面那条一起改掉。")
    }

    /// **这两页的视图模型必须在 `body` 里只构造一次。**
    ///
    /// ## 为什么只钉这两页，而不是定一条通行规矩
    ///
    /// 「视图模型写成计算属性」这个写法本身在这个工程里到处都是，而且**大多数时候没问题**：
    /// `TodayViewModel` 是个 struct，只存 `let state`，结果全在计算属性里——
    /// 构造它是免费的，一次 body 构造十次也是免费的。给它加一条通行禁令，
    /// 换来的是 963 行的 `TodayView` 里十几处签名改动，和零收益。
    ///
    /// 真正付钱的是**在 `init` 里干活**的那种。这两页是实测出来的：
    ///
    /// - `IssueArchiveViewModel.init` 要算趋势、把整张错题表排一遍、逐条解析时间。
    ///   一次 body 构造四次，实测 **485 ms** 卡在主线程上（30 条错题）。
    /// - `QuestionBankView` 的那一个更隐蔽：贵的不是 `init`，是传给它的实参——
    ///   `QuestionSearch.filter(app.state.questions, keyword:)` 要在 258 道题的题干、话题、
    ///   约 1250 条参考问句上跑区域感知的子串匹配。一次 body 取七次 ≈ 1.2 万次 ICU 比较，
    ///   而搜索框每敲一个字重绘一次。
    ///
    /// 所以这条守的是「这两处已经修好的东西别退回去」，不是一条美学规矩。
    /// 将来再有第三页测出同样的问题，把它加进来——**并且写清测出来的数字**。
    func testTheTwoMeasuredPagesBuildTheirViewModelOnlyOnce() throws {
        let pages = [
            ("Issues/IssueArchiveView.swift", "IssueArchiveViewModel",
             "实测一次重绘构造四次、卡约 485 ms"),
            ("QuestionBank/QuestionBankView.swift", "QuestionBankViewModel",
             "实测一次重绘取七次、约 1.2 万次 ICU 比较，搜索框打字时光标跟不上手")
        ]
        for (path, type, measured) in pages {
            let code = try SourceGuard.code(path)

            // 1. 不许再是「每次访问都新建」的计算属性。
            XCTAssertFalse(
                code.contains("private var model: \(type)"),
                "\(path) 又把视图模型改回每次访问都新建的计算属性了（\(measured)）。"
                    + "下一步：在 `body` 顶上算一次，当参数传给各个分区方法。")

            // 2. 整个文件里只许构造一次。
            let built = SourceGuard.occurrences(of: "\(type)(", in: code)
            XCTAssertEqual(
                built, 1,
                "\(path) 里构造了 \(built) 次 `\(type)`，应该只有 `body` 里那一次（\(measured)）。"
                    + "下一步：算一次往下传。")

            // 3. **不许改成 `@State` 存起来。** 那会让「慢」变成「不更新」——
            //    视图模型读的是 `app.state`，存进 `@State` 之后导入新数据界面纹丝不动，
            //    那比慢得多，而且更难发现。
            XCTAssertFalse(
                code.contains("@State private var model"),
                "\(path) 把视图模型存进了 `@State`。它读的是 `app.state`，"
                    + "存起来之后数据变了这一页不会更新——用户导入一份新复盘，"
                    + "看到的还是旧的。下一步：改回「`body` 里算一次的局部量」。")
        }
    }

    // MARK: - 等宽数字必须焊在组件里

    /// **`CoachBadge` 自己带等宽数字，调用方加不上去。**
    ///
    /// `monospacedDigit()` 作用于环境字体，而 `CoachBadge` 内部给 `Text` 设了显式字体，
    /// 显式字体压过环境字体——所以 `CoachBadge("9 题").monospacedDigit()` 是一句摆设。
    /// 改版时三处调用就是这么从 `Text(…).font(…).monospacedDigit()`
    /// （修饰符跟在自己的字体后面，必然生效）变成了没有作用的写法，
    /// **而源码里那几个字还在，扫源码的测试照样全绿**。
    func testTheBadgeCarriesMonospacedDigitsItselfInsteadOfLeavingItToCallers() throws {
        let components = try SourceGuard.code("DesignSystem/Components.swift")
        let badge = try SourceGuard.memberBody(of: "public struct CoachBadge", in: components)
        XCTAssertTrue(
            badge.contains(".monospacedDigit()"),
            "`CoachBadge` 内部没有等宽数字。徽章里装的几乎都是数字（「9 题」「Part 1」「6 条」），"
                + "少了它，数字从 9 跳到 10 时那一行会横向抖——"
                + "而 DESIGN-SYSTEM 第 1 节末行与第 6 节最后一条都明写这不许发生。"
                + "**在调用处加是没用的**（显式字体压过环境字体）。实际取到的是：\n\(badge)")

        // 调用处不许再写那句摆设：留着会让下一个人以为它有用。
        for path in ["QuestionBank/QuestionBankView.swift", "Review/ReviewReportView.swift"] {
            let code = try SourceGuard.code(path)
            XCTAssertFalse(
                code.contains("CoachBadge(") && code.contains(").monospacedDigit()"),
                "\(path) 在 `CoachBadge(...)` 外面加了 `.monospacedDigit()`——那是一句摆设"
                    + "（显式字体压过环境字体），删掉它，等宽数字由组件自己保证。")
        }
    }

    // MARK: - 抽签滚动期间不许改输入

    /// **滚动那一秒里，决定抽什么的那几个控件必须锁住。**
    ///
    /// `roll()` 在按下按钮那一刻就把结果定死，一秒后无条件写回 `drawn`。
    /// 期间若还能改数量或那个开关，用户会得到一组和屏幕上的数字对不上的题——
    /// 而 `drawCountBinding` 的注释逐字写着这件事不许发生。
    func testTheDrawInputsAreLockedWhileTheReelIsSpinning() throws {
        let section = try SourceGuard.memberBody(
            of: "private var drawCountsSection",
            in: try SourceGuard.code("Session/PracticeSheet.swift"))
        XCTAssertEqual(
            SourceGuard.occurrences(of: ".disabled(isRolling)", in: section), 2,
            "抽签滚动期间三个步进器与「只抽没练过的」开关没有全部锁住。"
                + "点「抽题」之后立刻改数量，一秒后 `roll()` 会把**按旧数量抽的**那一组写回来："
                + "步进器写着 3、底下列出 1 道，而「开始练习」练的就是列出的这一组。"
                + "实际取到的是：\n\(section)")
    }

    // MARK: - 页面版式只有一份定义

    /// `CoachPage` 必须调 `coachPageBody()`，不许把那三行再抄一遍。
    ///
    /// 抄一份的话，页面版式就有了两套定义：套 `CoachPage` 的几页和直接用
    /// `.coachPageBody()` 的那七页。以后调内边距或最大宽度时改了一处忘了另一处，
    /// 两组页面的边距与栏宽就会对不上——这套设计系统开宗明义要消灭的就是这个。
    func testThePageLayoutHasExactlyOneDefinition() throws {
        let components = try SourceGuard.code("DesignSystem/Components.swift")
        let page = try SourceGuard.memberBody(of: "public struct CoachPage", in: components)
        XCTAssertTrue(
            page.contains(".coachPageBody()"),
            "`CoachPage` 没有走 `coachPageBody()`，多半是把那三行又抄了一遍。"
                + "实际取到的是：\n\(page)")
        XCTAssertFalse(
            page.contains("Layout.contentMaxWidth"),
            "`CoachPage` 里又出现了 `Layout.contentMaxWidth`——页面版式有了第二份定义。"
                + "下一步：只留 `.coachPageBody()` 那一句。")
    }

    // MARK: - 系统标准能力不许被样式需求删掉

    /// 侧边栏的折叠按钮要留着。
    ///
    /// 一度为了让自绘的深色侧边栏顶上干净而 `.toolbar(removing: .sidebarToggle)`，
    /// 那是拿「删功能」解「样式问题」：侧边栏固定占 220pt，小屏上用户再也没有办法
    /// 把它收起来给正文腾地方，`⌃⌘S` 也跟着失效。
    func testTheSidebarCanStillBeCollapsed() throws {
        let code = try SourceGuard.code("RootView.swift")
        XCTAssertFalse(
            code.contains(".toolbar(removing: .sidebarToggle)"),
            "又把侧边栏的折叠按钮去掉了。侧边栏固定占 \(Int(Layout.sidebarWidth))pt，"
                + "去掉它之后小屏上没有任何办法把它收起来。"
                + "样式上的那点收益换不来一个系统标准能力。")
    }
}
