import XCTest
import IELTSCoachCore
@testable import ChatGPTBridge

final class AXTranscriptSamplerTests: XCTestCase {
    private var nextID = 0

    private func text(_ value: String) -> AXNodeSnapshot {
        nextID += 1
        return AXNodeSnapshot(element: AXElementRef(rawID: nextID, epoch: 0),
                              role: "AXStaticText", value: value)
    }

    /// 一个「只有一个 AXImage 子节点」的图标按钮，符合 spec 2.3.1 的结构判据。
    private func iconButton(_ description: String, role: String = "AXButton") -> AXNodeSnapshot {
        nextID += 1
        return AXNodeSnapshot(element: AXElementRef(rawID: nextID, epoch: 0),
                              role: role, descriptionText: description,
                              childCount: 1, childRoles: ["AXImage"])
    }

    private func sampler(_ nodes: [AXNodeSnapshot]) -> (AXTranscriptSampler, FakeAXAccess) {
        let access = FakeAXAccess()
        access.nodes = nodes
        return (AXTranscriptSampler(access: access), access)
    }

    // MARK: - 说话人判别

    func testTextBeforeTheAssistantCopyButtonBelongsToTheExaminer() {
        let (sampler, _) = self.sampler([
            text("Do you live in a house or a flat?"),
            iconButton("Copy")
        ])
        let sweep = sampler.sample()
        XCTAssertNil(sweep.failure)
        XCTAssertEqual(sweep.fragments,
                       [TranscriptFragment(speaker: .examiner,
                                           text: "Do you live in a house or a flat?")])
    }

    /// `Copy message` 是**用户自己**那条消息的复制按钮（spec 2.3.9），
    /// 两个按钮结构完全相同，只能靠标签区分。搞反了会让整份逐字稿的说话人全反。
    func testTextBeforeTheUserCopyButtonBelongsToTheLearner() {
        let (sampler, _) = self.sampler([
            text("I live in a flat with my parents."),
            iconButton("Copy message")
        ])
        XCTAssertEqual(sampler.sample().fragments,
                       [TranscriptFragment(speaker: .learner,
                                           text: "I live in a flat with my parents.")])
    }

    func testAWholeConversationIsAttributedTurnByTurn() {
        let (sampler, _) = self.sampler([
            text("You will act as an IELTS Speaking examiner."),
            iconButton("Copy message"),
            text("Do you live in a house or a flat?"),
            iconButton("Copy"),
            text("I live in a flat."),
            iconButton("Copy message")
        ])
        XCTAssertEqual(sampler.sample().fragments.map(\.speaker),
                       [.learner, .examiner, .learner])
    }

    /// 正在流式输出的那条消息还没有复制按钮。**不许猜，也不许丢。**
    func testTextWithNoSpeakerMarkerIsKeptAsUnknownInsteadOfDropped() {
        let (sampler, _) = self.sampler([
            text("Do you live in a house or a flat?"),
            iconButton("Copy"),
            text("I live in a fl")            // 还在往外冒字，按钮还没出现
        ])
        let fragments = sampler.sample().fragments
        XCTAssertEqual(fragments.count, 2, "判不出说话人也不能把内容丢掉")
        XCTAssertEqual(fragments[1].speaker, .unknown)
        XCTAssertEqual(fragments[1].text, "I live in a fl")
    }

    /// 一条消息在 AX 树里被切成好几段（spec 2.3.9 实测）。
    /// 采样器不做拼接——那是 TranscriptAssembler 的活——但必须**按原顺序**全都带出来。
    func testFragmentsOfOneMessageComeOutInDocumentOrder() {
        let (sampler, _) = self.sampler([
            text("Do you live"), text("in a house"), text("or a flat?"),
            iconButton("Copy")
        ])
        XCTAssertEqual(sampler.sample().fragments.map(\.text),
                       ["Do you live", "in a house", "or a flat?"])
        XCTAssertEqual(Set(sampler.sample().fragments.map(\.speaker)), [.examiner])
    }

    // MARK: - 过滤

    func testOnlyStaticTextIsCollected() {
        nextID += 1
        let composer = AXNodeSnapshot(element: AXElementRef(rawID: nextID, epoch: 0),
                                      role: "AXTextArea", value: "\nWork with ChatGPT",
                                      descriptionText: "Work with ChatGPT")
        let (sampler, _) = self.sampler([composer, text("Hello?"), iconButton("Copy")])
        XCTAssertEqual(sampler.sample().fragments.map(\.text), ["Hello?"])
    }

    func testBlankAndOneCharacterNoiseIsDropped() {
        let (sampler, _) = self.sampler([
            text("   "), text("\n"), text("·"), text("Hello?"), iconButton("Copy")
        ])
        XCTAssertEqual(sampler.sample().fragments.map(\.text), ["Hello?"])
    }

    /// 侧边栏里的会话行也带按钮，但它们**不是**图标按钮（嵌套 AXButton，含 Pin chat /
    /// Archive chat），不满足 spec 2.3.1 的结构判据，不能被当成说话人标记。
    func testASidebarRowNamedCopyIsNotMistakenForACopyButton() {
        nextID += 1
        let sidebarRow = AXNodeSnapshot(element: AXElementRef(rawID: nextID, epoch: 0),
                                        role: "AXButton", descriptionText: "Copy",
                                        childCount: 2, childRoles: ["AXStaticText", "AXButton"])
        let (sampler, _) = self.sampler([text("Do you live in a house?"), sidebarRow])
        XCTAssertEqual(sampler.sample().fragments.map(\.speaker), [.unknown],
                       "结构不符的同名元素不能用来判定说话人")
    }

    // MARK: - 失败（绝不抛错）

    /// 读不到界面时返回 failure，**不抛错**——逐字稿是增强，不是必需，
    /// 采样失败不得中断练习（ROADMAP 3.2）。
    func testAnEmptyTreeIsReportedAsAFailureNotAsAnEmptyConversation() throws {
        let (sampler, _) = self.sampler([])
        let sweep = sampler.sample()
        XCTAssertTrue(sweep.fragments.isEmpty)
        let failure = try XCTUnwrap(sweep.failure, "读不到就必须说读不到，不能装作这一秒没人说话")
        XCTAssertFalse(failure.isEmpty)
    }

    func testATreeWithChromeButNoConversationIsNotAFailure() {
        // 练习刚开始、还没人说话：树是有内容的，只是没有对话。这不是失败。
        nextID += 1
        let chrome = AXNodeSnapshot(element: AXElementRef(rawID: nextID, epoch: 0),
                                    role: "AXButton", descriptionText: "New chat",
                                    childCount: 1, childRoles: ["AXImage"])
        let (sampler, _) = self.sampler([chrome])
        let sweep = sampler.sample()
        XCTAssertNil(sweep.failure)
        XCTAssertTrue(sweep.fragments.isEmpty)
    }

    func testSamplingTwiceReallyRereadsTheTree() {
        let (sampler, access) = self.sampler([text("Hello?"), iconButton("Copy")])
        _ = sampler.sample()
        _ = sampler.sample()
        XCTAssertEqual(access.snapshotCount, 2, "每次采样都必须重新读树，不能缓存")
    }

    // MARK: - 以下四条是计划之外补的守卫（理由写在各自注释里）

    /// 失败原因会原样进 `TranscriptAssembler.completenessNote` 的括号里给用户看
    /// （「最后一次的原因：……」）。只断言「非空」的话，把它改成 "error" 或 "nil"
    /// 测试照样绿，而用户看到的就是一句看不懂的英文。
    /// 这里钉住：必须是中文、且说清「读不到的是 ChatGPT 的界面」。
    func testTheFailureReasonNamesWhatCouldNotBeRead() throws {
        let (sampler, _) = self.sampler([])
        let failure = try XCTUnwrap(sampler.sample().failure)
        XCTAssertTrue(failure.contains("ChatGPT"), "要说清读不到的是什么：\(failure)")
        XCTAssertTrue(failure.contains("没能读到"), "要用中文说清发生了什么：\(failure)")
    }

    /// 中文界面下两个复制按钮的标签是「复制消息」与「复制」。
    /// `copyAssistantMessage` 的中文标签已有测试守着，`copyUserMessage` 是本任务新增的，
    /// 漏掉中文标签的后果是：中文界面下**用户自己说的话全被记成考官说的**，
    /// 而且不报错、不崩溃——正是本项目最忌讳的那种无声错误。
    func testChineseCopyButtonLabelsAreRecognisedToo() {
        let (sampler, _) = self.sampler([
            text("我住在公寓里。"), iconButton("复制消息"),
            text("Do you live in a house?"), iconButton("复制")
        ])
        XCTAssertEqual(sampler.sample().fragments.map(\.speaker), [.learner, .examiner])
    }

    /// 判据必须与 `matchControl` 对称（role + label + 结构三重，见 spec 2.3.1）：
    /// role 不是控制类的同名元素不得用来判定说话人。只判结构不判 role 的话，
    /// 改版后某个恰好只有一个 AXImage 子节点的 AXGroup 会让整段话被安到错误的人头上。
    func testANonControlRoleNamedCopyIsNotASpeakerMarker() {
        let (sampler, _) = self.sampler([
            text("Do you live in a house?"),
            iconButton("Copy", role: "AXGroup")
        ])
        XCTAssertEqual(sampler.sample().fragments.map(\.speaker), [.unknown],
                       "role 不符的同名元素不能用来判定说话人")
    }

    /// 一个复制按钮只结算它**前面**攒的那些文本。不清空 pending 的话，
    /// 上一条消息会被重复安到下一个说话人头上——逐字稿里凭空多出内容，
    /// 且多出来的那份说话人是错的。
    func testTextIsSettledOnceAndNotCarriedIntoTheNextSpeaker() {
        let (sampler, _) = self.sampler([
            text("Do you live in a house?"), iconButton("Copy"),
            text("I live in a flat."), iconButton("Copy message")
        ])
        let fragments = sampler.sample().fragments
        XCTAssertEqual(fragments.count, 2, "每段文本只应结算一次")
        XCTAssertEqual(fragments.map(\.text), ["Do you live in a house?", "I live in a flat."])
        XCTAssertEqual(fragments.map(\.speaker), [.examiner, .learner])
    }
}
