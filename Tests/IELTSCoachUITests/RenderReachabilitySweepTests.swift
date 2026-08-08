import Foundation
import XCTest

@testable import IELTSCoachUI

/// 全模块守卫，管两件贯穿本项目的老毛病。**都不是猜的，都是实测能溜过去的。**
///
/// ## 一、写好了，但没摆上屏幕
///
/// 逻辑层测得很扎实，缺的一直是「这段渲染真的被画出来了吗」。已实测的四次：
///
/// - 删掉 `PracticeSheet.practiceBody` 里 `stageBlock` / `checklist` 那两句 → 369 条全绿；
/// - 删掉 `QuestionBankImportResultSheet` 里那段警告渲染 → 279 条全绿；
/// - **把 `PracticeSheet.body` 里 `practiceBody(for: running)` 和 `actions` 那两句一起去掉
///   → 465 条全绿**（本次实测）。那时整张 sheet 只剩一行题目：没有进度、没有失败信息、
///   一颗按钮都没有，用户开一场练习就再也退不出来。
///
/// 前两次是逐个成员手写断言补上的，而第三次正说明手写补不完：漏的永远是没写到的那一个。
/// 所以这里换成结构性的问法——**从 `body` 出发，顺着调用关系能不能走到每一个 `some View` 成员？**
/// 新写一段渲染却忘了摆进去，同样会在这里报出来。
///
/// ## 二、文案里指的控件，界面上不存在
///
/// 铁律 4 要的「下一步」最常见的形态就是「点某颗按钮 / 拨某个开关」。指错了比不写还糟——
/// 用户会一直找。已实测：解析失败那句话里嵌着「点『补生成复盘报告』」，而全 App 没有这颗按钮。
///
/// ## 三、控件是有，但不在文案说的那一页上
///
/// 第二类只问「这个控件存不存在」，于是漏过一处：`RetrainingFlowView` 那句
/// 「到菜单『设置』里确认『记录对话逐字稿』是开着的」——那个开关**确实存在**
/// （在「训练记录」页右上角），错的是位置。⌘, 打开的设置窗口里只有录音那两块，
/// 用户照着找必然找不到。所以「存在」之外还要问一句「在他被指去的那一页上吗」。
///
/// **边界**：扫源码不执行代码。「调用还在但条件永远为假」拦不住，排版好不好看也拦不住。
/// 第三类只认「到 X …『Y』」这种同一小句里紧挨着的一对，换个说法绕开是可能的。
final class RenderReachabilitySweepTests: XCTestCase {

    // MARK: - 一、每一段渲染都得从 body 走得到

    func testEveryViewMemberInTheModuleIsReachableFromItsBody() throws {
        var scannedTypes = 0
        var scannedMembers = 0
        var report: [String] = []

        for url in try SourceGuard.swiftFiles() {
            let path = try SourceGuard.relativePath(of: url)
            let code = SourceGuard.stripLineComments(
                try SourceGuard.read(contentsOf: url, describedAs: path))
            for type in SourceGuard.viewTypes(in: code) {
                scannedTypes += 1
                scannedMembers += type.viewMembers.count
                for member in type.unreachable {
                    report.append("\(path) · \(type.name).\(member)")
                }
            }
        }

        XCTAssertTrue(report.isEmpty,
                      "下面这些视图成员声明着，却从 `body` 顺着调用关系走不到——"
                          + "也就是写好了一个像素都不上屏，而且不会有任何编译错误：\n"
                          + report.map { "  • " + $0 }.joined(separator: "\n")
                          + "\n下一步：把它摆回渲染树里；确实不要了就连声明一起删掉，"
                          + "别让它留在那儿让人以为这块内容还在。")

        // 这一趟真的扫到东西了吗。扫了个空的话上面那条恒真——最坏的一种空转。
        XCTAssertGreaterThanOrEqual(scannedTypes, 8, "扫到的 SwiftUI 视图类型太少，这条测试多半失效了")
        XCTAssertGreaterThanOrEqual(scannedMembers, 40, "扫到的视图成员太少，这条测试多半失效了")
    }

    /// 上面那条自己有没有牙齿：喂一段「声明了但没人调」的人造源码，它必须报出来。
    ///
    /// 没有这一条的话，`viewTypes` 哪天认不出成员了（改个写法就可能），
    /// 全模块那一趟会扫出 0 处违规，然后一直绿着。
    func testTheReachabilityScannerReportsAMemberNobodyCalls() {
        let source = """
            struct Sheet: View {
                var body: some View {
                    VStack {
                        header
                    }
                }
                private var header: some View { Text("标题") }
                private var stageBlock: some View { Text(runner.stage.userFacingText) }
                private func row(_ item: Item) -> some View { Text(item.name) }
            }
            """
        let types = SourceGuard.viewTypes(in: source)
        XCTAssertEqual(types.count, 1)
        XCTAssertEqual(types.first?.unreachable, ["stageBlock", "row"],
                       "没人调的成员没被报出来：\(types.first?.unreachable ?? [])")
    }

    /// 反过来也要成立：链条隔一层也算走得到，否则会误报到被人整条删掉。
    func testTheReachabilityScannerFollowsTheChainAndDoesNotCryWolf() {
        let source = """
            struct Sheet: View {
                var body: some View { practiceBody }
                private var practiceBody: some View {
                    VStack { stageBlock; self.checklist }
                }
                private var stageBlock: some View { Text("在干什么") }
                private var checklist: some View { Text("走到第几步") }
            }
            """
        XCTAssertEqual(SourceGuard.viewTypes(in: source).first?.unreachable, [])
    }

    /// `runner.stage` 里的 `stage` 不该被当成「调用了一个叫 stage 的成员」。
    /// 认错的话会有一堆假的「走得到」，这条守卫就等于关掉了。
    func testAPropertyAccessOnSomethingElseDoesNotCountAsACall() {
        let source = """
            struct Sheet: View {
                var body: some View { Text(runner.header) }
                private var header: some View { Text("标题") }
            }
            """
        XCTAssertEqual(SourceGuard.viewTypes(in: source).first?.unreachable, ["header"],
                       "`runner.header` 被当成了对成员 `header` 的调用")
    }

    // MARK: - 二、文案里指名让用户点的东西，界面上得真有

    /// 界面模块里字面写死的「点『X』」，X 必须是界面上真存在的控件标题。
    ///
    /// **清单是按钮加开关**（`literalControlTitles`），不是只有按钮：麦克风权限那几句话
    /// 指的就是一颗 `Toggle`（「保存我的回答录音」）。只查按钮的话，指得完全正确的
    /// 一句话会被报成幽灵控件，几次误报之后这条守卫就会被人整条删掉。
    ///
    /// 带字符串插值的那些（`点「\\(retry.buttonTitle)」`）扫源码判不了，
    /// 交给 `PracticeRunnerTests` 在运行期查——那边会真的把运行器跑进失败态再看那句话。
    func testEveryButtonNamedInUICopyActuallyExists() throws {
        let controls = try SourceGuard.literalControlTitles()
        var checked = 0
        var report: [String] = []

        for url in try SourceGuard.swiftFiles() {
            let path = try SourceGuard.relativePath(of: url)
            let code = SourceGuard.stripLineComments(
                try SourceGuard.read(contentsOf: url, describedAs: path))
            for target in SourceGuard.literalClickTargets(in: code) {
                checked += 1
                guard !controls.contains(target) else { continue }
                report.append("\(path) 让用户去点「\(target)」")
            }
        }

        XCTAssertTrue(report.isEmpty,
                      "下面这些「下一步」指的控件，界面上一个都找不到（铁律 4）：\n"
                          + report.map { "  • " + $0 }.joined(separator: "\n")
                          + "\n界面上真有的按钮和开关是：\(controls.sorted().joined(separator: "、"))。"
                          + "\n下一步：把文案改成指界面上真有的那个，或者干脆把那颗控件做出来。")

        XCTAssertGreaterThanOrEqual(checked, 6, "一句「点『…』」都没扫到，这条测试等于空转")
    }

    /// 上面那条的牙齿：按钮清单是真从源码里读出来的，不是写死的一份。
    /// 读出来的清单里必须有几颗肉眼可查的按钮，也必须**没有**那颗命令行时代的。
    func testTheButtonInventoryComesFromTheRealSource() throws {
        let buttons = try SourceGuard.literalButtonTitles()
        for real in ["开始练习", "我练完了", "我已经复制好了", "重新检查"] {
            XCTAssertTrue(buttons.contains(real), "清单里没有「\(real)」，说明扫按钮的写法失效了")
        }
        XCTAssertFalse(buttons.contains("补生成复盘报告"),
                       "「补生成复盘报告」是命令行时代的说法，界面上没有这颗按钮。"
                           + "真要做出来的话，把它做成一颗 Button 再改这条测试。")
    }

    // MARK: - 三、文案说那个控件在哪一页，它就得真在那一页上

    /// 「存在」和「在他被指去的那一页上」是两件事。
    ///
    /// 上面第二类只问前者，于是本项目漏过一处：`RetrainingFlowView` 那句
    /// 「到菜单「设置」里确认「记录对话逐字稿」是开着的」——那个开关**确实存在**
    /// （在「训练记录」页右上角），而 ⌘, 打开的设置窗口里只有录音那两块。
    /// 用户照这句话去找必然找不到，比不写更糟：他会一直翻。
    ///
    /// 判据：文案里点名一页、紧接着点名一个控件时，那个控件必须真的声明在那一页的源码目录里。
    /// 「哪一页由谁画」从 `RootView` 的 detail switch 读，「那一页叫什么」从
    /// `SidebarItem.title` 读，设置窗口从 App 层那个 `Settings { … }` 场景读——
    /// 三份都不是手写清单（`SourceGuardTests` 钉着这份推导）。
    ///
    /// **边界**：只认「到 X …「Y」」这种同一小句里紧挨着的一对。隔着逗号、句号的不算
    /// （真源码里就有一句「到「训练记录」页逐条删，或点下面的「打开录音文件夹」」，
    /// 那颗按钮说的是当前这一页），所以换个说法绕开是可能的——那部分归人工验收。
    func testEveryControlNamedTogetherWithAPageActuallyLivesOnThatPage() throws {
        let locations = try SourceGuard.uiLocations()
        let names = Set(locations.flatMap(\.names))
        let controls = try SourceGuard.literalControlTitles()
        var checked = 0
        var report: [String] = []

        for url in try SourceGuard.swiftFiles() {
            let path = try SourceGuard.relativePath(of: url)
            let code = SourceGuard.stripLineComments(
                try SourceGuard.read(contentsOf: url, describedAs: path))
            for segment in SourceGuard.copySegments(in: code) {
                for direction in SourceGuard.directions(in: segment, locationNames: names,
                                                        controlTitles: controls) {
                    checked += 1
                    guard let named = locations.first(where: { $0.names.contains(direction.location) }),
                          !named.controls.contains(direction.control) else { continue }
                    let elsewhere = locations
                        .filter { $0.controls.contains(direction.control) }
                        .flatMap(\.names).map { "「\($0)」" }.joined(separator: " / ")
                    report.append("\(path)：\(direction)，但那一页（\(named.directory)/）上没有这个控件"
                                      + (elsewhere.isEmpty ? "（全 App 都找不到它）"
                                         : "；它其实在 \(elsewhere)"))
                }
            }
        }

        XCTAssertTrue(report.isEmpty,
                      "下面这些「下一步」把用户指去了错的地方（铁律 4：下一步必须是真做得到的一步）：\n"
                          + report.map { "  • " + $0 }.joined(separator: "\n")
                          + "\n下一步：把文案里那个位置改成这个控件真正所在的那一页；"
                          + "确实该把控件挪过去的话，先挪控件再改文案。")

        XCTAssertGreaterThanOrEqual(checked, 3, "一句「到某页找某控件」都没扫到，这条测试等于空转")
    }
}
