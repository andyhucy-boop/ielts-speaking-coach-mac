import XCTest

/// 守「问题反馈页绝不自动发送任何东西」。
///
/// 这一页存在的前提就是「你复制，你决定发给谁」。一旦有人顺手加个
/// 「一键提交」或者一个 GitHub 链接，就等于替用户决定了他的练习环境信息发去哪儿。
final class FeedbackPrivacyContractTests: XCTestCase {

    private var feedbackRoot: URL {
        NotarizeScriptTests.repositoryRoot.appending(path: "Sources/IELTSCoachUI/Feedback")
    }

    private func sources() throws -> [(name: String, text: String)] {
        let urls = try FileManager.default.contentsOfDirectory(at: feedbackRoot,
                                                               includingPropertiesForKeys: nil)
        return try urls.filter { $0.pathExtension == "swift" }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    func testThereAreFilesToScan() throws {
        XCTAssertFalse(try sources().isEmpty,
                       "扫不到问题反馈页的源码，先检查这个路径：\(feedbackRoot.path)")
    }

    func testNothingInTheFeedbackPageCanReachTheNetwork() throws {
        for (name, text) in try sources() {
            for forbidden in ["URLSession", "NSURLConnection", "NWConnection",
                              "CFSocket", "mailto:", "http://", "https://"] {
                XCTAssertFalse(text.contains(forbidden),
                               "\(name) 里出现了「\(forbidden)」。这一页只能复制到剪贴板，"
                               + "发给谁由用户自己决定。")
            }
        }
    }

    func testTheFeedbackPageUsesTheSharedDiagnosticsTextInsteadOfWritingItsOwn() throws {
        let joined = try sources().map(\.text).joined()
        XCTAssertTrue(joined.contains("DiagnosticsReport.text("),
                      "问题反馈页没有用统一的诊断文本。自己再拼一份的话，"
                      + "Task 5 那些「不许带练习内容」的测试就管不到它了。")
    }
}
