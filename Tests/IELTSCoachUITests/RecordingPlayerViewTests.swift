import Foundation
import XCTest

@testable import IELTSCoachUI

/// 内嵌播放器的视图层守卫，一条对一条地钉住计划 Task 9 里那份验收要求。
///
/// **为什么这一页需要这么一份测试。** 计划 Task 9 对两个 `View` 只给验收要求、不给布局，
/// 并把正确性交给 Task 11 的人工验收。但本项目已经四次实测到「整段渲染被删掉、
/// 几百条测试全绿」（`PracticeSheet` 那次是把 `body` 里两句调用一起去掉，465 条一条不红）。
/// 人工验收只跑一次，回归会发生无数次。
///
/// `RecordingPlaybackViewModelTests` 守的是「状态与删除的规则对不对」，
/// 这一份守的是「那些规则有没有真的摆上屏」——两件事，缺哪一半都会让另一半变成空转。
///
/// **边界**（与 `HistoryViewTests` 一致）：扫源码不执行代码。「调用还在但条件永远为假」
/// 拦不住，排版好不好看、`AVAudioPlayer` 在真机上响不响也拦不住——那部分归 Task 11。
/// 它拦得住的是：整段渲染被删、按钮点了不接线、失败被悄悄吞掉。
@MainActor
final class RecordingPlayerViewTests: XCTestCase {

    private static let view = "Recording/RecordingPlayerView.swift"
    private static let history = "History/HistoryView.swift"

    private static func viewCode() throws -> String { try SourceGuard.code(view) }

    /// 先确认这一趟真的扫到了东西。扫了个空的话，下面每条 `contains` 都恒假——
    /// 那会以「全红」的形式暴露，但报错会指向十几处，看不出根因在这儿。
    func testTheScanActuallyReachesThisPage() throws {
        XCTAssertTrue(try Self.viewCode().contains("struct RecordingPlayerView"),
                      "没扫到 RecordingPlayerView 的源码，这一整个文件的断言全部等于空转。"
                          + "下一步：确认文件还在——\(Self.view)")
    }

    // MARK: - 时间显示（真跑起来的那一条）

    /// `mm:ss` 抽成纯函数就是为了这一条：扫源码只问得出「这儿画了一个时间」，
    /// 问不出 65 秒会不会显示成「1:5」，更问不出长度读不出来时会不会画出一个 `nan:nan`。
    func testTheClockIsAlwaysTwoDigitsAndNeverPrintsGarbage() {
        XCTAssertEqual(RecordingPlayerView.timeText(0), "00:00")
        XCTAssertEqual(RecordingPlayerView.timeText(9), "00:09")
        XCTAssertEqual(RecordingPlayerView.timeText(65), "01:05")
        XCTAssertEqual(RecordingPlayerView.timeText(59.9), "00:59",
                       "秒数向下取整才对得上进度条：59.9 秒显示成「01:00」的话，"
                           + "总时长会在播到头之前就显示成下一分钟。")
        XCTAssertEqual(RecordingPlayerView.timeText(3_661), "61:01",
                       "超过一小时的录音不该溢出成别的数字。")
        XCTAssertEqual(RecordingPlayerView.timeText(.nan), "00:00",
                       "长度读不出来时画出一个「nan:nan」，用户只会以为程序坏了。")
        XCTAssertEqual(RecordingPlayerView.timeText(-1), "00:00")
    }

    // MARK: - 要求 1：这次本来就没录音时，整段不渲染

    func testNothingIsDrawnWhenThereIsNoRecordingAtAll() throws {
        let body = try SourceGuard.memberBody(of: "public var body: some View",
                                              in: try Self.viewCode())
        XCTAssertTrue(body.contains("if case .none = viewModel.state"),
                      "`body` 不再按 `.none` 分支决定画不画。这次本来就没录音（开关关着），"
                          + "却摆一个灰着的播放器在那儿，用户只会以为程序坏了。"
                          + "实际取到的是：\n\(body)")
        XCTAssertTrue(body.contains("viewModel.notice == nil"),
                      "`.none` 那一支没有再看一眼 `notice`。删完录音之后状态正是 `.none`，"
                          + "而「录音已删除。这次练习的题目、逐字稿和复盘都还在。」这句话"
                          + "就在 `notice` 里——不看它，用户点完删除界面上什么反应都没有。")
    }

    // MARK: - 要求 2：文件不在了要明说，并给一颗能点的按钮

    func testAMissingFileIsSpelledOutWithAWayForward() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "missingCard(message)", inBodyOf: "private var stateBlock", of: Self.view,
            because: "文件不在了那一支不再画任何东西。记录里写着有录音、点开却一片空白，"
                + "用户会以为自己记错了（铁律 7 的静默失败）。")
        let card = try SourceGuard.memberBody(of: "private func missingCard", in: code)
        XCTAssertTrue(card.contains("Text(message)"),
                      "「找不到了」那段说明没画出来。那段话里带着记录指向的路径，"
                          + "是用户自己去访达里找的唯一线索。实际取到的是：\n\(card)")
        XCTAssertTrue(card.contains("Button(\"清除这条录音记录\")"),
                      "没有「清除这条录音记录」这颗按钮。而 `RecordingPlaybackViewModel` "
                          + "那段说明里明写「点「清除这条录音记录」」——"
                          + "指一颗不存在的按钮比不写还糟，用户会一直找。")
        XCTAssertTrue(card.contains("viewModel.clearReferenceOnly()"),
                      "按钮点下去没有真的去清那个指向，这一条会永远显示「找不到」。")
        XCTAssertTrue(card.contains(".textSelection(.enabled)"),
                      "那段说明里带着文件路径，必须能选中复制。")
    }

    // MARK: - 要求 3：文件在时的播放器

    func testThePlayerHasATransportABarAndAClock() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "playerCard(url)", inBodyOf: "private var stateBlock", of: Self.view,
            because: "文件在的那一支不再画播放器，这一整个任务的头号功能没了。")

        let card = try SourceGuard.memberBody(of: "private func playerCard", in: code)
        XCTAssertTrue(card.contains("transport"),
                      "播放器卡片里没有播放控件，只剩一个标题。实际取到的是：\n\(card)")
        XCTAssertTrue(card.contains("player.load(url)"),
                      "卡片画出来了却没有装载那条录音，播放键按下去什么都不会发生。")
        XCTAssertTrue(card.contains(".onChange(of: url)"),
                      "换到另一条录音时没有重新装载，用户点开第二场听到的还是第一场的声音——"
                          + "内容听着完全正常，比一片空白更难被发现。")

        let transport = try SourceGuard.memberBody(of: "private var transport", in: code)
        XCTAssertTrue(transport.contains("\"pause.fill\"") && transport.contains("\"play.fill\""),
                      "播放/暂停用的不是 SF Symbols 的 `play.fill` / `pause.fill`"
                          + "（DESIGN-SYSTEM 第 4 节：只用 SF Symbols，不用 emoji）。"
                          + "实际取到的是：\n\(transport)")
        XCTAssertTrue(transport.contains("player.toggle()"),
                      "播放键点下去没接到播放器上——按钮在那儿，点了没反应。")
        XCTAssertTrue(transport.contains("Slider(value: progress"),
                      "没有可拖动的进度条。回听时最常做的事就是「刚才那句再听一遍」，"
                          + "没有进度条就只能从头听。")
        XCTAssertTrue(transport.contains("Self.timeText(player.currentTime)")
                      && transport.contains("Self.timeText(player.duration)"),
                      "「当前时间 / 总时长」没画全。实际取到的是：\n\(transport)")
        XCTAssertTrue(transport.contains(".monospacedDigit()"),
                      "秒数没有用等宽数字，每过一秒整行都会抖一下"
                          + "（DESIGN-SYSTEM 第 1 节最后一条：抖动的数字会让整个界面显得廉价）。")
    }

    /// 进度条**两头都要接**：读播放位置，拖动时真的跳过去。
    /// 只接读的那一头，用户拖完会看到滑块自己弹回原位。
    func testTheProgressBarIsWiredBothWays() throws {
        let binding = try SourceGuard.memberBody(of: "private var progress: Binding<Double>",
                                                 in: try Self.viewCode())
        XCTAssertTrue(binding.contains("player.currentTime"),
                      "进度条没有从播放位置取值，它会一直停在开头。")
        XCTAssertTrue(binding.contains("player.seek(to:"),
                      "拖动进度条没有真的跳过去，滑块会自己弹回原位。实际取到的是：\n\(binding)")
    }

    // MARK: - 要求 4：删录音之前先问一声

    func testDeletingAsksFirstAndSaysWhatIsLostAndWhatIsKept() throws {
        let code = try Self.viewCode()
        SourceGuard.assertRenders(
            "deleteRow", inBodyOf: "private func playerCard", of: Self.view,
            because: "播放器上没有删除入口。ROADMAP 3.3 要求录音能逐条删掉，"
                + "而设置页那句「到「训练记录」页逐条删」指的就是这儿。")

        let row = try SourceGuard.memberBody(of: "private var deleteRow", in: code)
        XCTAssertTrue(row.contains("Button(\"删除录音\", role: .destructive)"),
                      "「删除录音」这颗按钮不见了，或者没用 `.destructive` 角色——"
                          + "看起来和普通按钮一样。实际取到的是：\n\(row)")
        XCTAssertTrue(row.contains(".confirmationDialog("),
                      "删录音没有确认框，点一下就没了，而且不进废纸篓、没有撤销。")
        XCTAssertTrue(row.contains("Text(viewModel.deleteConfirmationText)"),
                      "确认框里没有原样显示 `deleteConfirmationText`。那段话说清了"
                          + "「再也听不到这次练习你是怎么说的」以及「题目、逐字稿和复盘都会保留」——"
                          + "自己另写一句的话，`RecordingPlaybackViewModelTests` 里守着那段文案的"
                          + "测试就空转了。")
        XCTAssertTrue(row.contains("Button(\"取消\", role: .cancel)"),
                      "确认框里没有「取消」。`deleteConfirmationText` 里明写"
                          + "「不删就点「取消」」，指一颗不存在的按钮比不写还糟。")
        XCTAssertTrue(row.contains("destroy()"),
                      "确认之后没有真的去删。按钮点了没反应是本项目最不能接受的那一类。")

        let destroy = try SourceGuard.memberBody(of: "private func destroy()", in: code)
        XCTAssertTrue(destroy.contains("player.stop()"),
                      "删之前没有把播放停掉。正在播的文件被删掉之后 `AVAudioPlayer` 会接着"
                          + "播它已经读进内存的那一段，用户会看着「已删除」听着自己的声音。")
        XCTAssertTrue(destroy.contains("viewModel.delete()"),
                      "确认删除之后没有调 `viewModel.delete()`，录音根本没被删。")
        XCTAssertTrue(destroy.contains("onRecordingRemoved()"),
                      "删完没有通知外面重读训练数据。行上那个波形标记会一直留着，"
                          + "用户会再点一次删除，而这一次删的是一条已经不存在的录音。")
    }

    // MARK: - 要求 5：失败一律说出来；离开时把声音停掉

    func testAFileThatCannotBeOpenedIsSaidOutLoudInsteadOfSwallowed() throws {
        let code = try Self.viewCode()
        SourceGuard.assertOmits(
            "try? AVAudioPlayer", in: Self.view,
            because: "打不开文件被 `try?` 吞掉了。用户看到的是一颗按下去没反应的播放键，"
                + "而且没有任何线索（铁律 7）。下一步：把失败写进 `failure`，由界面显示。")
        let card = try SourceGuard.memberBody(of: "private func playerCard", in: code)
        XCTAssertTrue(card.contains("player.failure"),
                      "文件打不开时那段中文说明没有摆上屏，等于把失败咽了回去。"
                          + "实际取到的是：\n\(card)")
        // 「下一步」得指着一颗界面上真有的按钮——`RenderReachabilitySweepTests` 会全模块
        // 再查一遍「点「X」」，这里只确认这句话本身还在。
        XCTAssertTrue(code.contains("这个录音文件打不开"),
                      "打不开的那句说明不见了。")
    }

    func testLeavingThePageStopsTheSound() throws {
        SourceGuard.assertRenders(
            "player.stop()", inBodyOf: "private var content", of: Self.view,
            because: "视图消失时没有停掉播放器。切到别的记录、甚至切到别的页面，"
                + "上一条录音还在响，而界面上已经没有任何一颗键能把它停下来。")
        XCTAssertTrue(try Self.viewCode().contains(".onDisappear { player.stop() }"),
                      "停播没有挂在 `.onDisappear` 上。")
    }

    // MARK: - 要求 6：真的嵌进训练记录页了

    /// 写好一个播放器却没摆进训练记录页，是本项目栽过四次的那一类——
    /// 一个像素都不上屏，而且不会有任何编译错误。
    func testThePlayerIsActuallyEmbeddedAboveTheTranscript() throws {
        let code = try SourceGuard.code(Self.history)
        let card = try SourceGuard.memberBody(of: "private func rowCard", in: code)

        XCTAssertTrue(card.contains("recordingPlayer"),
                      "训练记录页展开一场时没有嵌播放器。成品标准第 6 条"
                          + "（能听自己那次的录音）就挂在这一处。实际取到的行是：\n\(card)")
        let playerAt = try XCTUnwrap(card.range(of: "recordingPlayer")?.lowerBound,
                                     "行里找不到播放器")
        let transcriptAt = try XCTUnwrap(card.range(of: "transcriptPane(row)")?.lowerBound,
                                         "行里找不到逐字稿")
        XCTAssertTrue(playerAt < transcriptAt,
                      "播放器被摆到了逐字稿下面。一场练习的逐字稿有几十条，"
                          + "播放器会被顶到要滚很久才看得见的地方——而计划要求的顺序是"
                          + "「先听自己怎么说的，再对照文字」。")

        XCTAssertTrue(card.contains("app.makeRecordingPlaybackViewModel(for: row.session)"),
                      "播放器的视图模型不是从 `AppState` 造的。视图自己解析一次数据目录的话，"
                          + "它会去另一个目录里找那条 m4a，于是每一场都显示「录音文件找不到了」，"
                          + "而文件其实好端端地躺在磁盘上。实际取到的行是：\n\(card)")

        let member = try SourceGuard.memberBody(of: "private var recordingPlayer", in: code)
        XCTAssertTrue(member.contains("RecordingPlayerView(viewModel: playback"),
                      "那一段里没有真的画出 `RecordingPlayerView`。实际取到的是：\n\(member)")
        XCTAssertTrue(member.contains("app.reload()"),
                      "删完录音之后没有重读训练数据，行上那个波形标记会一直留着。")
        XCTAssertTrue(member.contains(".id(playback.sessionID)"),
                      "换一场时没有换视图身份。SwiftUI 会复用同一个 `RecordingPlayerView`，"
                          + "里面那台 `AVAudioPlayer`（`@State`）还是上一场的——"
                          + "用户点开第二场，听到的是第一场的声音。")
    }

    /// 列表里得看得出哪一场有录音，否则用户只能一场一场点开碰运气。
    func testRowsWithARecordingAreMarked() throws {
        let code = try SourceGuard.code(Self.history)
        let card = try SourceGuard.memberBody(of: "private func rowCard", in: code)
        XCTAssertTrue(card.contains("recordingBadge(row)"),
                      "行上没有「这一场有录音」的标记，用户只能一场一场点开碰运气。"
                          + "实际取到的行是：\n\(card)")
        let badge = try SourceGuard.memberBody(of: "private func recordingBadge", in: code)
        XCTAssertTrue(badge.contains("row.hasRecording"),
                      "标记没有按 `hasRecording` 判断——要么每一行都挂着，要么一行都没有。")
        XCTAssertTrue(badge.contains("Image(systemName: \"waveform\")"),
                      "标记不是 SF Symbols 的 `waveform`（DESIGN-SYSTEM 第 4 节：不用 emoji）。"
                          + "实际取到的是：\n\(badge)")
    }
}
