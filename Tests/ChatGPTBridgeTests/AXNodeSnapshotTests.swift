import XCTest
@testable import ChatGPTBridge

/// `AXNodeSnapshot.isEmptyComposer` 的直接单测——不经过 `AXDriver.sendText` 的
/// 轮询/超时机制，把「空输入框判据」本身的正确性从「发送流程能不能跑通」里剥离出来。
/// 这是本项目第三次栽在「验证判据与实际观测对不上」（spec 2.3.6）：实测空输入框的
/// value 不是空字符串，而是「换行 + 输入框自己的 description」，例如 "\nMessage ChatGPT"。
final class AXNodeSnapshotTests: XCTestCase {
    private func composer(value: String, description: String = "Message ChatGPT") -> AXNodeSnapshot {
        AXNodeSnapshot(element: AXElementRef(rawID: 1, epoch: 0), role: "AXTextArea",
                       value: value, descriptionText: description)
    }

    func testEmptyStringIsRecognizedAsEmpty() {
        XCTAssertTrue(composer(value: "").isEmptyComposer)
    }

    // 本次故障的直接现场：实测占位符值必须被判定为「空」，否则发送后永远等到超时。
    func testObservedPlaceholderValueIsRecognizedAsEmpty() {
        XCTAssertTrue(composer(value: "\nMessage ChatGPT").isEmptyComposer,
                     "实测占位符值必须被判定为「空」，否则发送后永远等到超时")
    }

    func testPlaceholderMatchesWhicheverDescriptionTheComposerCurrentlyHas() {
        // 语音会话进行中输入框 description 是 "Work with ChatGPT"，占位符要跟着变。
        XCTAssertTrue(composer(value: "\nWork with ChatGPT", description: "Work with ChatGPT").isEmptyComposer)
    }

    func testLeftoverTextIsNotRecognizedAsEmpty() {
        XCTAssertFalse(composer(value: "考官提示词").isEmptyComposer,
                       "还留着没发出去的文字时不能被误判成已清空")
    }

    // 与「第二次栽」（spec 2.3.4）的教训一致：换行/空白规范化不能把「没清空」误判成「清空了」。
    func testNormalizedWhitespaceAroundLeftoverTextIsStillNotEmpty() {
        XCTAssertFalse(composer(value: "考官提示词\n").isEmptyComposer)
    }
}
