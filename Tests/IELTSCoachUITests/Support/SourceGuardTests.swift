import Foundation
import XCTest

/// **守门员自己的守门员。**
///
/// `SourceGuard` 存在的理由是「测试要有牙齿」，那它自己就不能是空转的。
/// 本项目已经吃过这个亏：复审各自临时发明的扫源码写法，看着在守，
/// 实际把 `.font(Typography.label)` 换成 `.font(Font.caption)` 就溜过去了——
/// **没有人给那些扫描器自己写过一条「该红的时候真的会红」的测试。**
///
/// 所以这里每个辅助函数各有一条自测，做法统一是：
/// 喂一段人造的、含违规写法的字符串给它，断言它真的报出来；
/// 再喂一段干净的，断言它不乱叫（否则会被人以「误报太多」为由整条删掉）。
///
/// 断言函数（`assertRenders` / `assertOmits` / `assertUsesDesignTokens`）的报错出口是可注入的，
/// 自测时换成录音机，于是「它报了错」这件事本身可以被断言。
/// 最后 `testTheDefaultReporterReallyTurnsTheTestRed` 把录音机换回默认出口，
/// 证明那条线真的接在 `XCTFail` 上——否则前面所有自测就都只是在测一个录音机。
final class SourceGuardTests: XCTestCase {

    /// 录音机：把本该变红的报错收下来，让测试能对它下断言。
    private final class Recorder {
        private(set) var messages: [String] = []
        var reporter: SourceGuard.Reporter {
            { [self] message, _, _ in messages.append(message) }
        }
        var only: String {
            messages.count == 1 ? messages[0] : messages.joined(separator: " ||| ")
        }
    }

    // MARK: - 定位仓库根：不许写死绝对路径

    func testRepositoryRootIsFoundByWalkingUpFromThisFile() throws {
        let root = try SourceGuard.repositoryRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appending(path: "Package.swift").path),
            "找到的仓库根里没有 Package.swift：\(root.path)")
        // 换台机器、换个克隆目录都得照样能跑，所以只断言相对结构，不断言具体路径。
        let uiRoot = try SourceGuard.uiSourceRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: uiRoot.appending(path: "RootView.swift").path),
            "定位到的界面源码目录不对：\(uiRoot.path)")
    }

    // MARK: - 读源码：读不到必须抛错，绝不返回空串

    /// **这是整个机制里最要命的一条。**
    /// 读不到就返回空串的话，后面每条 `contains` 恒假、每条 `!contains` 恒真，
    /// 整组测试当场变成空转，而且一点迹象都没有——它们看上去还是绿的。
    func testReadThrowsInsteadOfReturningAnEmptyStringWhenThePathIsWrong() {
        XCTAssertThrowsError(try SourceGuard.read("Today/ThisFileDoesNotExist.swift")) { error in
            XCTAssertTrue("\(error)".contains("找不到源码文件"), "报错没说清发生了什么：\(error)")
            XCTAssertTrue("\(error)".contains("下一步"), "报错没说下一步做什么：\(error)")
        }
    }

    func testReadThrowsWhenTheRelativePathPointsAtADirectory() {
        XCTAssertThrowsError(try SourceGuard.read("Today")) { error in
            XCTAssertTrue("\(error)".contains("是个目录"), "\(error)")
        }
    }

    /// 空文件和不存在一样危险：内容为空，所有断言照样退化。
    func testReadThrowsOnAnEmptyFile() throws {
        let empty = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "source-guard-empty-\(UUID().uuidString).swift")
        try "   \n\n  ".write(to: empty, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: empty) }

        XCTAssertThrowsError(try SourceGuard.read(contentsOf: empty, describedAs: "空文件")) { error in
            XCTAssertTrue("\(error)".contains("空文件"), "\(error)")
        }
    }

    func testReadReturnsTheRealSourceForAPathThatExists() throws {
        let source = try SourceGuard.read("DesignSystem/Components.swift")
        XCTAssertTrue(source.contains("public struct CoachCard"), "读到的不是 Components.swift")
    }

    // MARK: - 界面模块之外的源码

    /// 有些必须守住的东西不在 `Sources/IELTSCoachUI` 里——`Sources/IELTSCoachApp/main.swift`
    /// 里 `WindowGroup` 还是 `Window` 这一个词，决定了整个进程有几份 `AppState`。
    ///
    /// 这条同时钉住两件事：读得到真文件，以及**去注释这一步真的在做**。
    /// 后者不是顺带的：那个文件的注释里必然要写清「为什么不用 `WindowGroup`」，
    /// 注释没被去掉的话，`AppSceneTests` 里那条「不许出现 WindowGroup」会被自己的说明绊倒。
    func testRepositoryCodeReachesOutsideTheUIModuleAndStripsComments() throws {
        let raw = try SourceGuard.repositoryRead("Sources/IELTSCoachApp/main.swift")
        XCTAssertTrue(raw.contains("struct CoachApp"), "读到的不是 App 的入口文件")
        XCTAssertTrue(raw.contains("WindowGroup"),
                      "这条自测靠「注释里提到了 WindowGroup」来证明去注释真的在做。"
                          + "下一步：那段说明被删了的话，换一个同样在注释里、代码里没有的词。")

        let code = try SourceGuard.repositoryCode("Sources/IELTSCoachApp/main.swift")
        XCTAssertTrue(code.contains("struct CoachApp"), "去注释把代码也切掉了")
        XCTAssertFalse(code.contains("WindowGroup"),
                       "行注释没被去掉，扫「不许出现某个词」的断言会被注释里的反例绊倒")
    }

    func testRepositoryPathsThrowInsteadOfComingBackEmpty() {
        XCTAssertThrowsError(try SourceGuard.repositoryCode("Sources/NoSuchTarget/main.swift")) {
            XCTAssertTrue("\($0)".contains("找不到源码文件"), "\($0)")
        }
        XCTAssertThrowsError(try SourceGuard.swiftFiles(atRepositoryPath: "Sources/NoSuchTarget")) {
            XCTAssertTrue("\($0)".contains("找不到目录"), "\($0)")
        }
    }

    func testSwiftFilesAtARepositoryPathListsTheWholeTarget() throws {
        let files = try SourceGuard.swiftFiles(atRepositoryPath: "Sources/IELTSCoachApp")
        XCTAssertEqual(files.map(\.lastPathComponent), ["main.swift"],
                       "App 目标里的文件清单变了。下一步：确认新加的文件有没有开出第二个窗口场景。")
    }

    // MARK: - 遍历目录

    func testSwiftFilesThrowsWhenTheDirectoryIsGone() {
        XCTAssertThrowsError(try SourceGuard.swiftFiles(under: "NoSuchDirectory")) { error in
            XCTAssertTrue("\(error)".contains("找不到目录"), "\(error)")
        }
    }

    func testSwiftFilesFindsTheDesignSystemSources() throws {
        let files = try SourceGuard.swiftFiles(under: "DesignSystem")
        XCTAssertEqual(files.map(\.lastPathComponent),
                       ["Components.swift", "ContrastMath.swift", "Metrics.swift",
                        "Palette.swift", "Typography.swift"])
        // 换算回相对路径：全模块扫描的报错信息和豁免名单都按这个形式对齐，
        // 换算错了，豁免名单会一条都对不上（于是豁免失效或者全都豁免）。
        XCTAssertEqual(try SourceGuard.relativePath(of: files[0]),
                       "DesignSystem/Components.swift")
    }

    // MARK: - 去注释

    /// 去注释是所有扫描的前置：源文件的文档注释里必然要写「反例长什么样」
    /// （本项目的注释风格就是这样），不去掉的话扫描会被自己的说明绊倒。
    ///
    /// 反过来也不能矫枉过正：`"https://…"` 里那两条斜杠不是注释，切掉的话会把同一行
    /// 后面的真代码一起吃掉，扫描就出现一个谁也想不到的盲区。
    func testStripLineCommentsRemovesCommentsButKeepsStringLiterals() {
        let stripped = SourceGuard.stripLineComments(
            """
            let a = 1 // .font(.caption) 这是注释里的反例
            let u = "https://example.com" // 真注释
            let b = 2
            """)
        XCTAssertFalse(stripped.contains(".font(.caption)"), "注释里的反例没被去掉")
        XCTAssertFalse(stripped.contains("真注释"), "行注释没被去掉")
        XCTAssertTrue(stripped.contains("https://example.com"), "字符串里的斜杠被当成注释切掉了")
        XCTAssertEqual(stripped.split(separator: "\n", omittingEmptySubsequences: false).count, 3,
                       "行数变了，违规报告里的行号就对不上源文件了")
    }

    // MARK: - 数次数

    /// 「声明一次、用一次」那类断言全靠它。只问「出现过吗」的话，
    /// 把 body 里那句调用删掉、只留声明，断言照样绿。
    func testOccurrencesCountsEveryHit() {
        XCTAssertEqual(SourceGuard.occurrences(of: "checklist", in: "checklist\nvar checklist"), 2)
        XCTAssertEqual(SourceGuard.occurrences(of: "checklist", in: "var checklist"), 1)
        XCTAssertEqual(SourceGuard.occurrences(of: "checklist", in: "无"), 0)
    }

    /// `occurrences` 是纯子串计数，凑数的东西太多。「参数收下了有没有真的用上」
    /// 这类断言得用 `standaloneOccurrences`，否则一个同名的颜色令牌就能把它顶满。
    func testStandaloneOccurrencesIgnoresMemberNamesAndLongerNames() {
        // 真实形态：闭包参数 + 颜色令牌 + 真正画出来的那一处 = 只应数到 2。
        let real = "_, warning in Label(warning).foregroundStyle(Palette.warning)"
        XCTAssertEqual(SourceGuard.standaloneOccurrences(of: "warning", in: real), 2)
        // 把真正画出来的那一处换成一句泛泛之词 → 只剩闭包参数那一次。
        let generic = "_, warning in Label(\"出问题了\").foregroundStyle(Palette.warning)"
        XCTAssertEqual(SourceGuard.standaloneOccurrences(of: "warning", in: generic), 1)
        // 更长的名字不算：warnings / rewarning 都不是 warning 本身。
        XCTAssertEqual(
            SourceGuard.standaloneOccurrences(of: "warning", in: "feedback.warnings rewarning"), 0)
        // 别把正常的一次也吞了。
        XCTAssertEqual(SourceGuard.standaloneOccurrences(of: "warning", in: "warning"), 1)
        XCTAssertEqual(SourceGuard.standaloneOccurrences(of: "warning", in: "无"), 0)
    }

    // MARK: - 切出一段

    func testMemberBodyTakesOnlyThatDeclarationsBraces() throws {
        let code = """
        private var actions: some View {
            HStack {
                Button("放弃这一场") { abandon() }
                if let retry { Button("重试") { redo(retry) } }
            }
        }
        private var decoration: some View {
            Text("重试 的残影")
        }
        """
        let actions = try SourceGuard.memberBody(of: "private var actions", in: code)
        // 切早了同样致命：视图的 body 第一行几乎必然是 `VStack {` 这类嵌套容器，
        // 一遇嵌套就收工的话，切出来的是个几乎空的片段，靠它的每条断言都会变成永远绿。
        XCTAssertTrue(actions.contains(#"Button("放弃这一场")"#), "切早了：\n\(actions)")
        XCTAssertTrue(actions.contains("redo(retry)"), "嵌套里最深的那一层被切掉了：\n\(actions)")
        XCTAssertFalse(actions.contains("残影"), "括号配对没停在自己那一段，切出来的范围太大了")
    }

    /// 括号配对必须跳过字符串字面量。
    ///
    /// 本项目的文案里落单的括号是常态（「下一步：按 { 键」「（右边那颗）」），
    /// 不跳过的话切出来的范围会歪掉一大截——而歪掉之后没有任何症状，
    /// 靠它的断言只会安静地退化成永远绿。
    func testBracketMatchingSkipsBracesAndParensInsideStringLiterals() throws {
        let code = """
        private var actions: some View {
            Text("下一步：按 { 键")
        }
        private var decoration: some View {
            Text("残影")
        }
        """
        let actions = try SourceGuard.memberBody(of: "private var actions", in: code)
        XCTAssertFalse(actions.contains("残影"),
                       "字符串里的 `{` 被当成了真括号，范围一路吃到下一个声明：\n\(actions)")

        // 圆括号同理——颜色扫描靠它取修饰符的整段参数。
        // 字符串里那个落单的 `)` 一旦被当真，参数会在 `.gray` 之前就被截断，违规就漏掉了。
        let source = #"Text(hint).foregroundStyle(tone(for: "少一个 ) 括号") ?? .gray)"#
        XCTAssertFalse(
            SourceGuard.colorViolations(in: source).isEmpty,
            "字符串里的 `)` 被当成了参数结尾，后面的字面语义色就扫不到了")
    }

    /// 切不出来必须抛错。返回空串的话，靠它的那几条断言会全部退化成永远绿。
    func testMemberBodyThrowsWhenTheDeclarationIsGone() {
        XCTAssertThrowsError(
            try SourceGuard.memberBody(of: "private var actions", in: "struct A {}")) { error in
            XCTAssertTrue("\(error)".contains("找不到"), "\(error)")
            XCTAssertTrue("\(error)".contains("空转"), "报错没点出「这会让断言空转」：\(error)")
        }
    }

    // MARK: - 字体扫描：三种同义写法都要认

    /// 旧扫描只认「点开头」的 `font(.`，`.font(Font.caption)` 实测能溜过去。
    /// 这条把已知的每一种绕法都摆出来，一种漏掉就红。
    func testFontScannerCatchesEverySynonymIncludingTheOneThatUsedToSlipThrough() {
        let bypasses = [
            ".font(.caption)",                 // 旧扫描认得的那一种
            ".font(Font.caption)",             // 实测能溜过旧扫描的那一种
            ".font(Font.caption.weight(.medium))",
            "let f = Font.system(size: 11)",   // 连 .font( 都不写，先存成变量
            ".fontWeight(.bold)",
            ".font(Typography.label).weight(.black)",
            ".bold()",
            ".italic()",
            ".fontDesign(.rounded)"
        ]
        for bypass in bypasses {
            XCTAssertFalse(
                SourceGuard.fontViolations(in: "Text(\"甲\")\(bypass)").isEmpty,
                "「\(bypass)」这种写法溜过去了——字体表的字重那一列就管不到它了")
        }
    }

    /// 字距是排版取值里唯一有令牌、却一直没人扫的一档。
    /// 实测把 `SectionHeader` 的 `.tracking(Tracking.label)` 换成 `.tracking(2.5)`，429 条全绿。
    func testFontScannerCatchesLiteralTrackingAndLineSpacing() {
        for bypass in [".tracking(2.5)", ".kerning(1)", ".lineSpacing(6)"] {
            XCTAssertFalse(SourceGuard.fontViolations(in: "Text(\"甲\")\(bypass)").isEmpty,
                           "「\(bypass)」这种写法溜过去了")
        }
        XCTAssertEqual(
            SourceGuard.fontViolations(in: ".tracking(Tracking.label)\n.lineSpacing(Spacing.xs)"),
            [], "令牌写法被误判成违规了")
    }

    func testFontScannerAcceptsTokensIncludingTernaries() {
        let clean = """
        Text("甲").font(Typography.label)
        Text("乙").font(highlighted ? Typography.cardTitle : Typography.body)
        Text("丙").font(Typography.number).monospacedDigit()
        """
        XCTAssertEqual(SourceGuard.fontViolations(in: clean), [],
                       "把合规写法判成违规的话，这条规则迟早会被人以「误报太多」为由删掉")
    }

    // MARK: - 颜色扫描：字面构造色与字面语义色都要认

    /// 实测过的退化：把 `.foregroundStyle(Palette.textSecondary)` 换成一个字面灰色，全绿。
    /// 「字面灰色」可以写成好几种样子，这里逐个钉住。
    func testColorScannerCatchesBothConstructedAndSemanticLiterals() {
        let bypasses = [
            ".foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.5))",
            ".foregroundStyle(Color(white: 0.55))",
            ".foregroundStyle(Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1))",
            ".foregroundStyle(Color.gray)",
            ".foregroundStyle(.gray)",
            ".foregroundStyle(.secondary)",
            ".tint(.blue)",
            ".background(Color(hue: 0.1, saturation: 0.2, brightness: 0.3))",
            ".fill(.clear)",
            "let c = NSColor(calibratedWhite: 0.5, alpha: 1)"
        ]
        for bypass in bypasses {
            XCTAssertFalse(
                SourceGuard.colorViolations(in: "Text(\"甲\")\(bypass)").isEmpty,
                "「\(bypass)」这种写法溜过去了——它绕开了 Palette 的对比度测试，"
                    + "也不会跟着深色模式走")
        }
    }

    /// **「灰上加灰」的最后一条通道**：引用着令牌，却在视图里再乘一次不透明度。
    ///
    /// `Palette.textSecondary` 的 56% 是按 4.5:1 定的，再 `.opacity(0.35)` 一下就掉到 2:1 上下。
    /// 实测这么改，429 条一条不红——前面每条规则都因为「它用了令牌」而放行。
    func testColorScannerCatchesDimmingATokenInTheView() {
        for bypass in [".foregroundStyle(Palette.textSecondary.opacity(0.35))",
                       ".background(Palette.card.opacity(0.5))",
                       ".foregroundStyle(Palette.accent .opacity(0.4))"] {
            XCTAssertFalse(SourceGuard.colorViolations(in: bypass).isEmpty,
                           "「\(bypass)」这种写法溜过去了——它绕开了对比度那几条断言")
        }
        XCTAssertEqual(SourceGuard.colorViolations(in: ".foregroundStyle(Palette.textSecondary)"),
                       [], "令牌写法被误判成违规了")
    }

    /// 规范第 4 节：卡片靠边框和留白分层，**不加投影**。所以投影没有令牌，出现即违规。
    func testShapeScannerCatchesAnyShadow() {
        for bypass in [".shadow(radius: 8)",
                       ".shadow(color: Palette.cardBorder, radius: Radius.card, y: 2)"] {
            XCTAssertFalse(SourceGuard.shapeViolations(in: bypass).isEmpty,
                           "「\(bypass)」这种写法溜过去了——第 4 节明写不加投影")
        }
    }

    /// 不能误伤令牌写法。尤其 `Typography.secondary`：它带着一个 `.secondary`，
    /// 粗暴地扫 `.secondary` 会把它当成字面语义色。
    func testColorScannerLeavesTokenUsagesAlone() {
        let clean = """
        Text("甲").font(Typography.secondary).foregroundStyle(Palette.textSecondary)
        Text("乙").foregroundStyle(picked ? Palette.accent : Palette.textSecondary)
        Text("丙").background(Palette.card,
                              in: RoundedRectangle(cornerRadius: Radius.control))
        VStack(alignment: .leading, spacing: Spacing.sm) { detail }
        """
        XCTAssertEqual(SourceGuard.colorViolations(in: clean), [])
    }

    // MARK: - 圆角与描边

    func testShapeScannerCatchesLiteralCornerRadiusAndLineWidth() {
        for bypass in ["RoundedRectangle(cornerRadius: 40)",
                       ".cornerRadius(12)",
                       ".strokeBorder(Palette.cardBorder, lineWidth: 1)"] {
            XCTAssertFalse(SourceGuard.shapeViolations(in: bypass).isEmpty,
                           "「\(bypass)」这种写法溜过去了")
        }
        XCTAssertEqual(
            SourceGuard.shapeViolations(
                in: ".strokeBorder(Palette.cardBorder, lineWidth: BorderWidth.hairline)"
                    + "\n.clipShape(RoundedRectangle(cornerRadius: Radius.card))"),
            [])
    }

    // MARK: - 间距

    func testSpacingScannerCatchesLiteralPaddingAndSpacing() {
        for bypass in [".padding(32)", ".padding(.top, 8)", "VStack(spacing: 12) {"] {
            XCTAssertFalse(SourceGuard.spacingViolations(in: bypass).isEmpty,
                           "「\(bypass)」这种写法溜过去了")
        }
        // 版面尺寸不是设计令牌，不该被拦。误伤会让这条规则被整条删掉。
        XCTAssertEqual(
            SourceGuard.spacingViolations(
                in: ".padding(Spacing.xl)\n.frame(width: 620, minHeight: 600)"
                    + "\nSpacer(minLength: 0)"),
            [])
    }

    // MARK: - 豁免：必须说得出理由、只管一行、过期了要吵

    /// 豁免写对了就该放行——否则「确有正当理由的那一处」只能靠把整条规则删掉来解决。
    func testAValidExemptionSilencesExactlyTheLineItIsWrittenFor() {
        let sameLine = """
        Text("甲").padding(32)   // 设计令牌豁免：这是窗口最小尺寸，不是间距令牌
        """
        XCTAssertEqual(SourceGuard.designTokenViolations(inRawSource: sameLine), [],
                       "写在行尾的豁免没被认出来")

        let lineAbove = """
        // 设计令牌豁免：这是窗口最小尺寸，不是间距令牌
        Text("甲").padding(32)
        """
        XCTAssertEqual(SourceGuard.designTokenViolations(inRawSource: lineAbove), [],
                       "写在上一行的豁免没被认出来")
    }

    /// **豁免只管两行。** 管一整段的话，一次「随手豁免」就能把整个文件的守卫关掉。
    func testAnExemptionDoesNotCoverTheRestOfTheFile() {
        let source = """
        // 设计令牌豁免：这是窗口最小尺寸，不是间距令牌
        Text("甲").padding(32)
        Text("乙").padding(16)
        Text("丙").foregroundStyle(.gray)
        """
        let found = SourceGuard.designTokenViolations(inRawSource: source)
        XCTAssertEqual(found.map(\.line), [3, 4],
                       "豁免的覆盖范围超出了它该管的那一行：\(found)")
    }

    /// 理由太短等于没写，而且它自己就是一条违规——不然「随手豁免」就是零成本的。
    func testAnExemptionWithoutARealReasonIsItselfAViolation() {
        let source = """
        Text("甲").padding(32)   // 设计令牌豁免：临时
        """
        let found = SourceGuard.designTokenViolations(inRawSource: source)
        XCTAssertEqual(found.count, 2, "该报两条（原违规没被豁免 + 豁免本身不合格）：\(found)")
        XCTAssertTrue(found.contains { $0.rule.contains("内边距") },
                      "理由不合格的豁免不该挡住原来那条违规：\(found)")
        XCTAssertTrue(found.contains { $0.rule.contains("豁免没说清理由") }, "\(found)")
    }

    /// **过期豁免要吵。** 规则一变，这些豁免就静静躺在代码里：
    /// 下一个人只会以为这儿本来就该破例，而且它会替将来真正的违规挡枪。
    func testAStaleExemptionIsReportedSoItGetsDeleted() {
        let source = """
        Text("甲").padding(Spacing.xl)   // 设计令牌豁免：这个理由长得足够进得了门
        """
        let found = SourceGuard.designTokenViolations(inRawSource: source)
        XCTAssertEqual(found.count, 1, "\(found)")
        XCTAssertTrue(found.first?.rule.contains("多余") == true, "\(found)")
    }

    /// 注释里举的反例不算豁免，也不该被扫成违规——两头都得对。
    func testExemptionsAreReadFromCommentsAndNotFromStringLiterals() {
        let source = #"""
        let hint = "写法示例：设计令牌豁免：这段是文案不是注释"
        Text(hint).padding(32)
        """#
        let found = SourceGuard.designTokenViolations(inRawSource: source)
        XCTAssertEqual(found.count, 1, "字符串里的字样被当成了豁免：\(found)")
        XCTAssertEqual(SourceGuard.exemptions(in: source), [])
    }

    // MARK: - 令牌清单：手写的表漏掉新加的那一行

    /// 实测过的洞：往 `Metrics.swift` 里加一个 `Radius.sheet = 3` 并在卡片上用它，429 条全绿。
    /// 根因是「逐行钉死取值」那张表是手写的，没人问过「声明了几个、钉住了几个」。
    func testDeclaredTokenNamesReadsTheRealTokenList() throws {
        let metrics = try SourceGuard.code("DesignSystem/Metrics.swift")
        XCTAssertEqual(try SourceGuard.declaredTokenNames(inEnum: "Radius", of: metrics),
                       ["card", "control", "pill"])
        // 只取这一个 enum 里的，不许把隔壁 enum 的令牌算进来——算多了，那张表会「怎么都对得上」。
        XCTAssertFalse(try SourceGuard.declaredTokenNames(inEnum: "Radius", of: metrics)
                        .contains("xs"))
        XCTAssertEqual(SourceGuard.declaredEnumNames(in: metrics),
                       ["Spacing", "Radius", "BorderWidth", "Tracking"])
    }

    /// enum 改了名字却没同步改这里，必须抛错。返回空数组的话，
    /// 「每个令牌都被钉住了」那条断言会因为「一个令牌都没解析到」而永远绿。
    func testDeclaredTokenNamesThrowsWhenTheEnumIsGone() {
        XCTAssertThrowsError(
            try SourceGuard.declaredTokenNames(inEnum: "Elevation", of: "public enum Radius {}")) {
            XCTAssertTrue("\($0)".contains("空转"), "\($0)")
        }
    }

    /// **「测试去读测试」这条路上的一个坑，本次真踩了一次。**
    ///
    /// 元测试自己必须把被查函数的名字写成字符串（`named: "testFoo"`）。那个字符串一旦排在
    /// 真正的声明前面，按「第一处文字匹配」切出来的就是元测试自己的函数体——
    /// 它于是在检查自己，永远绿。所以重名时必须抛错，不许猜。
    func testFunctionBodyRefusesToGuessWhenTheNameIsNotUnique() throws {
        let code = """
        func meta() {
            let marker = "func target"
            check(marker)
        }
        func target() {
            let pinned = 1
        }
        """
        // 名字唯一（字符串里那处没带括号，不算），切出来的必须是真正的声明。
        let body = try SourceGuard.functionBody(named: "target", in: code)
        XCTAssertTrue(body.contains("let pinned = 1"), "切错了段：\(body)")
        XCTAssertFalse(body.contains("check(marker)"), "切到元测试自己的函数体上了：\(body)")

        XCTAssertThrowsError(
            try SourceGuard.functionBody(named: "target",
                                         in: code + "\nfunc target() { let 冒牌 = 2 }")) {
            XCTAssertTrue("\($0)".contains("2 处"), "\($0)")
        }
        XCTAssertThrowsError(try SourceGuard.functionBody(named: "noSuchFunc", in: code))
    }

    // MARK: - 视图成员：切段与「从 body 走得到吗」

    /// **切段必须切到那个成员自己的大括号上。**
    ///
    /// 写这个扫描时踩过一次：正则末尾带着 `{`，再从「匹配的结尾」往后找大括号，
    /// 找到的是函数体内部的下一个 `{`——切出来是半截东西。
    /// 半截东西照样能让上层的 `contains` 恒真，那就是一条看不出来的空转。
    func testViewMemberBodiesAreCutAtTheMembersOwnBraces() {
        let source = """
            struct Sheet: View {
                var body: some View {
                    VStack {
                        header
                    }
                }
                private var header: some View {
                    Text("这是标题")
                }
            }
            """
        guard let sheet = SourceGuard.viewTypes(in: source).first else { return XCTFail("没切出类型") }
        let bodies = Dictionary(uniqueKeysWithValues: sheet.viewMembers.map { ($0.name, $0.body) })
        XCTAssertTrue(bodies["body"]?.contains("header") == true, "body 切出来的是：\(bodies["body"] ?? "")")
        XCTAssertTrue(bodies["header"]?.contains("这是标题") == true,
                      "header 切出来的是：\(bodies["header"] ?? "")")
        XCTAssertFalse(bodies["header"]?.contains("VStack") == true,
                       "切到别的成员身上去了：\(bodies["header"] ?? "")")
    }

    /// 属性和方法两种写法都得认。只认一种的话，另一种被摘掉照样绿。
    func testViewMembersCoverBothComputedPropertiesAndFunctions() {
        let source = """
            struct Sheet: View {
                var body: some View { VStack { header } }
                private var header: some View { Text("标") }
                private func row(_ item: Item) -> some View { Text(item.name) }
            }
            """
        let names = SourceGuard.viewTypes(in: source).first?.viewMembers.map(\.name) ?? []
        XCTAssertEqual(Set(names), ["body", "header", "row"], "漏认了写法：\(names)")
    }

    /// 没有 `body` 的类型不是视图，别去查它——否则每个协议实现、每个测试替身都会被误报。
    func testTypesWithoutABodyAreNotTreatedAsViews() {
        let source = """
            struct InertBridge: CoachBridge {
                func preflight() -> BridgeReadiness { BridgeReadiness(ok: false, messages: []) }
            }
            """
        XCTAssertEqual(SourceGuard.viewTypes(in: source).count, 0)
    }

    /// `mentions` 是可达性判定的地基：它把 `runner.header` 认成「调用了成员 header」的话，
    /// 整条守卫会有一堆假的「走得到」，等于关掉。
    func testMentionsIgnoresPropertyAccessOnSomethingElse() {
        XCTAssertTrue(SourceGuard.mentions("header", in: "VStack { header }"))
        XCTAssertTrue(SourceGuard.mentions("header", in: "VStack { self.header }"))
        XCTAssertFalse(SourceGuard.mentions("header", in: "Text(runner.header)"))
        XCTAssertFalse(SourceGuard.mentions("header", in: "Text(headerTitle)"))
        XCTAssertFalse(SourceGuard.mentions("row", in: "narrow(1)"))
    }

    // MARK: - 每个状态都得有一条出口

    /// 状态清单必须从枚举**声明**里读，而且不能被同一个文件里的 `switch` 模式匹配污染。
    /// 清单一空、或者混进了别的名字，「每个状态都有出口」那条断言就失去依据。
    func testDeclaredCaseNamesReadsDeclarationsAndNotSwitchPatterns() throws {
        let code = """
            public enum Fake: Equatable {
                case idle
                case needsManualCopy(String)
                case done, failed
                var order: Int {
                    switch self {
                    case .idle: return 0
                    case .needsManualCopy: return 1
                    case .done, .failed: return 2
                    }
                }
            }
            """
        XCTAssertEqual(try SourceGuard.declaredCaseNames(inEnum: "Fake", of: code),
                       ["idle", "needsManualCopy", "done", "failed"])
    }

    /// 真的读得到 `PracticeStage`。人造字符串跑通、真源码读不到，等于没在守。
    ///
    /// **不钉死条数**：往 `PracticeStage` 里正经加一个状态不该让这条变红
    /// （那件事归 `PracticeSheetTests.testEveryPracticeStageHasAWayOut` 管）。
    /// 这里改成钉「没有重复」——真源码里 `.idle` 在几个 `switch` 里各出现一次，
    /// 扫描要是把模式匹配也算成声明，重复会立刻暴露。
    func testDeclaredCaseNamesReadsTheRealPracticeStage() throws {
        let stages = try SourceGuard.declaredCaseNames(
            inEnum: "PracticeStage", of: try SourceGuard.code("Session/PracticeStage.swift"))
        XCTAssertGreaterThanOrEqual(stages.count, 13, "读出来的状态是：\(stages)")
        XCTAssertEqual(stages.count, Set(stages).count,
                       "同一个状态被读出了不止一次，说明 `switch` 里的模式匹配也被当成了声明：\(stages)")
        XCTAssertTrue(stages.contains("startingVoice"), "\(stages)")
        XCTAssertTrue(stages.contains("failed"), "\(stages)")
    }

    /// 枚举改了名字却没同步改这里，必须抛错。返回空数组的话断言会恒真。
    func testDeclaredCaseNamesThrowsInsteadOfComingBackEmpty() {
        XCTAssertThrowsError(
            try SourceGuard.declaredCaseNames(inEnum: "Fake", of: "enum Fake { var x: Int { 1 } }")) {
            XCTAssertTrue("\($0)".contains("空转"), "\($0)")
        }
        XCTAssertThrowsError(try SourceGuard.declaredCaseNames(inEnum: "Gone", of: "enum Fake {}"))
    }

    /// 分支要切在各自的标签上。切错（全糊成一条）的话，
    /// 「这个状态下有按钮吗」会被别的状态的按钮糊弄过去。
    func testSwitchBranchesCutEachBranchAtItsOwnLabel() throws {
        let code = """
            switch runner.stage {
            case .practicing:
                Button("我练完了") { finish() }
            case .capturingReview, .needsManualCopy(let message):
                Button("我已经复制好了") { paste(message) }
            default:
                Button("取消") { abandon() }
            }
            """
        let branches = try SourceGuard.switchBranches(over: "runner.stage", in: code)
        XCTAssertEqual(branches.map(\.cases),
                       [["practicing"], ["capturingReview", "needsManualCopy"], []])
        XCTAssertTrue(branches[0].body.contains("我练完了"), "\(branches[0].body)")
        XCTAssertFalse(branches[0].body.contains("我已经复制好了"),
                       "切到下一条分支上去了：\(branches[0].body)")
        XCTAssertTrue(branches[2].isDefault && branches[2].body.contains("取消"),
                      "\(branches[2])")
    }

    /// 三个会把切分支带偏的写法：`.defaultAction`（不是 `default:` 标签）、
    /// `if case … = x {`（不是分支标签）、嵌套 `switch` 里的 case（是里面那层的）。
    func testSwitchBranchesIgnoreLookalikes() throws {
        let code = """
            switch stage {
            case .a:
                if case .failed = other { Text("x") }
                switch inner {
                case .deep: Text("深")
                }
                Button("甲") { go() }
                    .keyboardShortcut(.defaultAction)
            case .b:
                Button("乙") { go() }
            }
            """
        let branches = try SourceGuard.switchBranches(over: "stage", in: code)
        XCTAssertEqual(branches.map(\.cases), [["a"], ["b"]],
                       "被 `.defaultAction` / `if case` / 嵌套 switch 带偏了：\(branches.map(\.label))")
        XCTAssertTrue(branches[0].body.contains("甲"), "\(branches[0].body)")
    }

    /// switch 没了要抛错，不能返回空数组——空数组会让「逐个状态问出口」一条都问不到。
    func testSwitchBranchesThrowInsteadOfComingBackEmpty() {
        XCTAssertThrowsError(
            try SourceGuard.switchBranches(over: "runner.stage", in: "Text(\"没有 switch\")")) {
            XCTAssertTrue("\($0)".contains("空转"), "\($0)")
        }
    }

    /// 「有一颗 Button」和「用户一定点得到」是两件事。
    /// 藏在 `if` 里的、挂了 `.disabled` 的都不算出口——认它们的话，
    /// 一个只剩灰按钮的状态照样能骗过守卫。
    func testUnconditionalButtonsSkipTheConditionalAndTheDisabledOnes() {
        let code = """
            Button("关掉") { onClose() }
                .buttonStyle(.bordered)
            if let retry = runner.retry {
                Button("重试") { redo(retry) }
            }
            Button("开始练习") { startPicked() }
                .disabled(picked == nil)
            """
        let labels = SourceGuard.unconditionalButtons(in: code).map(\.label)
        XCTAssertEqual(labels, [#""关掉""#], "认错了出口：\(labels)")
    }

    /// 空闭包的按钮是铁律 5 说的静默失败：看着有出口，按下去什么都不发生。
    func testUnconditionalButtonsFlagTheOnesWiredToNothing() {
        let wired = SourceGuard.unconditionalButtons(in: #"Button("取消") { abandon() }"#)
        XCTAssertEqual(wired.map(\.isWired), [true], "\(wired)")

        let dead = SourceGuard.unconditionalButtons(in: #"Button("取消") { }"#)
        XCTAssertEqual(dead.map(\.isWired), [false], "空闭包的按钮被当成了出口：\(dead)")

        // `action:` 那种写法也得认，否则 `Button("完成", action: onClose)` 会被误判成死按钮。
        let byArgument = SourceGuard.unconditionalButtons(in: #"Button("完成", action: onClose)"#)
        XCTAssertEqual(byArgument.map(\.isWired), [true], "\(byArgument)")
    }

    /// 去条件块不许误伤参数标签。`practiceBody(for: setup)` 里那个 `for` 认成关键字的话，
    /// 后面一整块渲染会被当成条件块删掉——扫描从那一刻起就开始撒谎了。
    func testRemovingConditionalBlocksLeavesArgumentLabelsAlone() {
        let code = """
            practiceBody(for: setup)
            Button("取消") { abandon() }
            """
        XCTAssertTrue(SourceGuard.removingConditionalBlocks(from: code).contains("取消"),
                      "把无条件那段也删掉了：\(SourceGuard.removingConditionalBlocks(from: code))")
    }

    // MARK: - 文案里指的按钮真的存在吗

    /// 按钮清单必须是从真源码里读出来的。读不到（写法失效）就抛错——
    /// 返回空集合的话，「文案指的按钮存在吗」那条断言会恒真。
    func testLiteralButtonTitlesComeFromTheRealSourceAndNeverComeBackEmpty() throws {
        let titles = try SourceGuard.literalButtonTitles()
        XCTAssertTrue(titles.contains("开始练习"), "扫按钮的写法失效了：\(titles.sorted())")
        XCTAssertTrue(titles.contains("我已经复制好了"), "扫按钮的写法失效了：\(titles.sorted())")
        XCTAssertFalse(titles.contains("补生成复盘报告"), "这颗按钮界面上并不存在")
    }

    /// 控件清单必须**同时**认得按钮和开关。
    ///
    /// 只认按钮的话，「下一步：点『保存我的回答录音』」这句指得完全正确的话
    /// 会被报成「幽灵控件」——误报几次之后，这条守卫就会被人整条删掉。
    /// 反过来，开关不在清单里，也就没人证明得了那句话指对了东西。
    func testLiteralControlTitlesCoverSwitchesAndNotJustButtons() throws {
        let toggles = try SourceGuard.literalToggleTitles()
        XCTAssertTrue(toggles.contains("保存我的回答录音"),
                      "扫开关的写法失效了：\(toggles.sorted())")

        let controls = try SourceGuard.literalControlTitles()
        XCTAssertTrue(controls.contains("保存我的回答录音"),
                      "控件清单里没有那颗开关：\(controls.sorted())")
        XCTAssertTrue(controls.contains("开始练习"),
                      "控件清单把按钮那一半弄丢了：\(controls.sorted())")
    }

    /// 「点『X』」要认得出来，且**不能把带插值的那种当成字面标题**——
    /// `点「\\(retry.buttonTitle)」` 的取值要跑起来才知道，当字面量查会报一堆假违规，
    /// 然后这条守卫会被人以「误报太多」为由整条删掉。
    func testClickTargetsAreFoundAndInterpolatedOnesAreLeftToRuntime() {
        let message = "下一步：点「重新检查」，或者点一下「打开系统设置」。"
        XCTAssertEqual(SourceGuard.clickTargets(in: message), ["重新检查", "打开系统设置"])

        let code = #"return "下一步：点「\(retry.buttonTitle)」，或点「补生成复盘报告」。""#
        XCTAssertEqual(SourceGuard.clickTargets(in: code).count, 2, "插值那处也该被认出来")
        XCTAssertEqual(SourceGuard.literalClickTargets(in: code), ["补生成复盘报告"],
                       "插值那处不该被当成字面标题：\(SourceGuard.literalClickTargets(in: code))")
    }

    // MARK: - 文案指的那个控件，真在它说的那一页上吗

    /// 文案经常被 `+` 拆成好几段写。不先拼回一段的话，
    /// 「到「训练记录」页右上角」和「确认「记录对话逐字稿」…」分属两个字面量，
    /// 「地点 + 控件」这一对就永远配不上——那条守卫会安静地永远绿。
    func testCopySegmentsJoinLiteralsThatAreConcatenatedWithPlus() {
        let code = """
            hintCard("到「训练记录」页右上角"
                     + "确认「记录对话逐字稿」是开着的。")
            Text("另一段")
            """
        let segments = SourceGuard.copySegments(in: code)
        XCTAssertTrue(segments.contains("到「训练记录」页右上角确认「记录对话逐字稿」是开着的。"),
                      "用 `+` 连起来的文案没有被拼回一段：\(segments)")
        XCTAssertTrue(segments.contains("另一段"), "没被连接的那一段也得单独在：\(segments)")
    }

    /// 「到某一页找某个控件」这一对要认得出来。
    ///
    /// 这是本项目实测漏过去的那一种：`RetrainingFlowView` 那句
    /// 「到菜单「设置」里确认「记录对话逐字稿」是开着的」，控件真实存在（在训练记录页右上角），
    /// 所以「文案指的控件存在吗」那条全绿；错的是它说的**位置**。
    func testDirectionsPairAPageWithTheControlItPointsAt() {
        let found = SourceGuard.directions(
            in: "到菜单「设置」里确认「记录对话逐字稿」是开着的。",
            locationNames: ["设置", "训练记录"],
            controlTitles: ["记录对话逐字稿", "打开录音文件夹"])
        XCTAssertEqual(found, [SourceGuard.Direction(location: "设置",
                                                     control: "记录对话逐字稿")],
                       "这一对没被认出来：\(found)")
    }

    /// 隔着一个分句的那种**不算指路**。
    ///
    /// 真源码里就有一句：「到「训练记录」页逐条删，或点下面的「打开录音文件夹」。」
    /// 后半句那颗按钮说的是「下面的」——就在当前这一页上，跟前半句那一页无关。
    /// 这条不写的话，守卫上线第一天就报假违规，然后被人以「误报太多」为由整条删掉。
    func testDirectionsIgnoreAControlThatSitsInASeparateClause() {
        let found = SourceGuard.directions(
            in: "下一步：想删已有录音的话，到「训练记录」页逐条删，或点下面的「打开录音文件夹」。",
            locationNames: ["训练记录"],
            controlTitles: ["打开录音文件夹"])
        XCTAssertEqual(found, [], "隔着一个逗号的那颗按钮被当成了指路：\(found)")
    }

    /// 「哪一页上有哪些控件」这份清单必须从真源码里推出来，而且**分得清页与页**。
    ///
    /// 这是整条守卫的地基：清单要是把全 App 的控件混成一坨，
    /// 「这个控件在不在那一页」就永远为真——最坏的一种空转。
    func testUILocationInventoryKnowsWhichPageEachControlLivesOn() throws {
        let locations = try SourceGuard.uiLocations()

        guard let history = locations.first(where: { $0.names.contains("训练记录") }) else {
            return XCTFail("清单里没有「训练记录」这一页：\(locations)")
        }
        XCTAssertTrue(history.controls.contains("记录对话逐字稿"),
                      "「记录对话逐字稿」这个开关就在训练记录页右上角，清单里却找不到：\(history)")

        guard let settings = locations.first(where: { $0.names.contains("设置") }) else {
            return XCTFail("清单里没有 ⌘, 那个设置窗口：\(locations)")
        }
        XCTAssertTrue(settings.controls.contains("保存我的回答录音"),
                      "设置窗口那颗录音开关没扫到：\(settings)")
        XCTAssertFalse(settings.controls.contains("记录对话逐字稿"),
                       "设置窗口里并没有「记录对话逐字稿」。清单说有，"
                           + "就等于把这条守卫关掉了：\(settings)")

        // 十项侧边栏里已实现的五页 + 设置窗口。少于这个数说明推导写法失效了。
        XCTAssertGreaterThanOrEqual(locations.count, 6, "扫到的页面太少：\(locations)")
    }

    /// 元测试要去读测试自己的源码。读不到同样必须抛错。
    func testTestCodeReadsTheTestSourcesAndThrowsWhenThePathIsWrong() throws {
        let source = try SourceGuard.testCode("DesignSystemTests.swift")
        XCTAssertTrue(source.contains("final class DesignSystemTests"), "读到的不是那个测试文件")
        XCTAssertThrowsError(try SourceGuard.testCode("NoSuchTests.swift"))
    }

    // MARK: - 违规报告本身要能读

    /// 报告要指出行号、原文和下一步（铁律 4）。只说「有违规」的话，
    /// 下一个人只能自己去翻——那这条测试的价值就少一半。
    func testViolationsReportLineNumberEvidenceAndNextStep() {
        let source = "行一\n行二\nText(\"甲\").font(.caption)\n行四"
        let found = SourceGuard.designTokenViolations(in: source)
        XCTAssertEqual(found.count, 1, "\(found)")
        XCTAssertEqual(found.first?.line, 3, "行号不对，改起来得靠猜")
        XCTAssertTrue(found.first?.evidence.contains(".caption") == true, "\(found)")
        XCTAssertTrue(found.first?.nextStep.isEmpty == false, "没说下一步做什么")
    }

    // MARK: - 断言函数：该报错的时候真的报错了

    func testAssertRendersReportsWhenTheCallSiteIsDeletedButTheDeclarationStays() {
        let recorder = Recorder()
        // 真实退化形态：`private var checklist` 还在，但 body 里那句调用被删了，
        // 于是用户一个字都看不到，而只问「出现过吗」的断言仍然是绿的。
        SourceGuard.assertRenders("checklist", in: "Session/PracticeSheet.swift",
                                  atLeast: 99, because: "（自测用的不可能值）",
                                  reporter: recorder.reporter)
        XCTAssertEqual(recorder.messages.count, 1, "该报错时没报错，这个断言函数是空转的")
        XCTAssertTrue(recorder.only.contains("只出现了"), recorder.only)

        let quiet = Recorder()
        SourceGuard.assertRenders("checklist", in: "Session/PracticeSheet.swift",
                                  atLeast: 2, because: "", reporter: quiet.reporter)
        XCTAssertEqual(quiet.messages, [], "合规时不该报错")
    }

    /// 路径写错时必须响。**这条比上面那条更要紧**：路径错了却静默通过，
    /// 就是「守门员自己走开了，比赛照常显示 0 失球」。
    func testAssertRendersShoutsWhenTheFileIsMissingInsteadOfPassingQuietly() {
        let recorder = Recorder()
        SourceGuard.assertRenders("随便什么", in: "Session/NoSuchSheet.swift",
                                  because: "", reporter: recorder.reporter)
        XCTAssertEqual(recorder.messages.count, 1, "文件不存在却静默通过了——这正是最坏的一种空转")
        XCTAssertTrue(recorder.only.contains("找不到源码文件"), recorder.only)
    }

    func testAssertRendersScopedToAMemberIgnoresTheDecoyElsewhereInTheFile() {
        let recorder = Recorder()
        // `runner.finishPractice(` 在 `redo(_:)` 里另有一处调用。扫全文的话，
        // 把「我练完了」那颗按钮整颗删掉照样绿——扫这一段才问得出真话。
        SourceGuard.assertRenders("这段肯定不在按钮里",
                                  inBodyOf: "private var actions",
                                  of: "Session/PracticeSheet.swift",
                                  because: "", reporter: recorder.reporter)
        XCTAssertEqual(recorder.messages.count, 1, "该报错时没报错")

        let missing = Recorder()
        SourceGuard.assertRenders("随便",
                                  inBodyOf: "private var 这个声明不存在",
                                  of: "Session/PracticeSheet.swift",
                                  because: "", reporter: missing.reporter)
        XCTAssertEqual(missing.messages.count, 1, "扫描范围失效却静默通过了")
        XCTAssertTrue(missing.only.contains("空转"), missing.only)
    }

    func testAssertOmitsReportsWhenTheForbiddenWritingIsThere() {
        let recorder = Recorder()
        SourceGuard.assertOmits("struct PracticeSheet", in: "Session/PracticeSheet.swift",
                                because: "（自测：这段一定在）", reporter: recorder.reporter)
        XCTAssertEqual(recorder.messages.count, 1, "该报错时没报错，这个断言函数是空转的")

        let quiet = Recorder()
        SourceGuard.assertOmits("这段文字不可能出现在源码里", in: "Session/PracticeSheet.swift",
                                because: "", reporter: quiet.reporter)
        XCTAssertEqual(quiet.messages, [])
    }

    func testAssertOmitsShoutsWhenTheFileIsMissing() {
        let recorder = Recorder()
        SourceGuard.assertOmits("随便", in: "NoSuchView.swift", because: "",
                                reporter: recorder.reporter)
        XCTAssertEqual(recorder.messages.count, 1,
                       "文件不存在时 !contains 恒真，这条断言会永远绿——必须报错")
    }

    func testAssertUsesDesignTokensReportsEveryClassOfViolation() throws {
        // 拿一个真实文件当底稿，人造地破坏它，证明这个断言函数看得见四类里的每一类。
        let recorder = Recorder()
        SourceGuard.assertUsesDesignTokens(in: "DesignSystem/Components.swift",
                                           reporter: recorder.reporter)
        XCTAssertEqual(recorder.messages, [], "Components.swift 现在应该是干净的：\(recorder.only)")

        // 按文件扫的那个入口同样不许静默：路径写错要抛错，不是给一份空的违规清单
        // （空清单会被读成「这个文件很干净」）。
        XCTAssertThrowsError(try SourceGuard.designTokenViolations(inFileAt: "NoSuchView.swift"))

        let dirty = """
        Text("甲").font(Font.caption).foregroundStyle(.gray)
            .padding(8)
            .clipShape(RoundedRectangle(cornerRadius: 40))
        """
        let found = SourceGuard.designTokenViolations(in: dirty)
        let rules = Set(found.map(\.rule))
        XCTAssertTrue(rules.contains(where: { $0.contains("字体") }), "\(rules)")
        XCTAssertTrue(rules.contains(where: { $0.contains("语义色") }), "\(rules)")
        XCTAssertTrue(rules.contains(where: { $0.contains("圆角") }), "\(rules)")
        XCTAssertTrue(rules.contains(where: { $0.contains("内边距") }), "\(rules)")
    }

    // MARK: - 最后一根线：默认出口真的接在 XCTFail 上

    /// 前面每一条自测都把报错出口换成了录音机。**那就必须再证明一次：
    /// 不换录音机的时候，这些断言真的会让测试变红**——否则上面全是在测一个录音机，
    /// 而线路早在 `failTest` 那一步就断了。
    func testTheDefaultReporterReallyTurnsTheTestRed() {
        XCTExpectFailure("这条失败是故意的：证明默认出口真的接在 XCTFail 上") {
            SourceGuard.assertRenders("这段文字不可能出现在源码里",
                                      in: "Session/PracticeSheet.swift",
                                      because: "（自测：默认出口必须让测试变红）")
        }
    }
}
