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

    // MARK: - 遍历目录

    func testSwiftFilesThrowsWhenTheDirectoryIsGone() {
        XCTAssertThrowsError(try SourceGuard.swiftFiles(under: "NoSuchDirectory")) { error in
            XCTAssertTrue("\(error)".contains("找不到目录"), "\(error)")
        }
    }

    func testSwiftFilesFindsTheDesignSystemSources() throws {
        let files = try SourceGuard.swiftFiles(under: "DesignSystem")
        XCTAssertEqual(files.map(\.lastPathComponent),
                       ["Components.swift", "Metrics.swift", "Palette.swift", "Typography.swift"])
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
