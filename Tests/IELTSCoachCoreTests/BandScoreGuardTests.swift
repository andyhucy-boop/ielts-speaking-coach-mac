import XCTest

@testable import IELTSCoachCore

/// 「绝不预测雅思分数」这条红线的**第二道防线**。
///
/// 在这之前它只写在复盘请求的提示词里——全靠 ChatGPT 自觉，而它每换一次模型
/// 都可能不自觉一次。真写了一句「整体大概 6.5」的话，那句话会原样存档、
/// 原样显示在复盘页最上面那张卡片上。
final class BandScoreGuardTests: XCTestCase {

    // MARK: - 该拦的

    func testCatchesTheWaysAScoreActuallyGetsWritten() {
        for text in ["整体大概 6.5，建议多练。",
                     "这段相当于 band 7 的表达。",
                     "Band score: 6",
                     "大约在雅思 6.5 左右。",
                     "已经到 7 分水平了。",
                     "这一场我给 6.5 分。"] {
            XCTAssertFalse(BandScoreGuard.matches(in: text).isEmpty,
                           "没拦住：\(text)")
        }
    }

    // MARK: - 不该拦的（拦错了比不拦更糟）

    /// **这一组是这个文件真正的重点。** 复盘里到处是「分析」「部分」「十分」「区分」
    /// 「分钟」，扫中文单字「分」会让每一份复盘都误报——
    /// 而一个天天误报的警告等于没有警告，用户会学会无视它。
    func testDoesNotFireOnTheWordsThatFillEveryReview() {
        for text in ["先分析一下你这段回答的结构。",
                     "这一部分说得不错。",
                     "你答了 3 分钟，共 2 题。",
                     "十分自然的一个说法。",
                     "要区分 borrow 和 lend。",
                     "分别举了两个例子。",
                     "把这句话分开说会更清楚。"] {
            XCTAssertTrue(BandScoreGuard.matches(in: text).isEmpty,
                          "误报了：\(text) → \(BandScoreGuard.matches(in: text))")
        }
    }

    /// **已知的漏网之鱼，写下来是为了别把它当成没想到。**
    ///
    /// 光秃秃的整数（「大概 7」）不拦：它和「大概 7 个例子」分不开，
    /// 而这里误报一次的代价是把一句正常的话从总结里挡掉。
    /// 带「分」「band」「雅思」「水平」中任意一个的整数写法仍然拦得住。
    func testABareIntegerIsDeliberatelyNotTreatedAsAScore() {
        XCTAssertTrue(BandScoreGuard.matches(in: "大概 7 个例子就够了。").isEmpty)
        XCTAssertTrue(BandScoreGuard.matches(in: "整体大概 7，还不错。").isEmpty,
                      "整数写法是刻意放过的；要改的话得先解决「7 个例子」那种误报")
        XCTAssertFalse(BandScoreGuard.matches(in: "整体大概 7 分。").isEmpty)
    }

    /// 本工具自己算出来的客观事实（「这一场 12 分钟」）绝不能被当成分数挡掉。
    func testASessionLengthIsNotAScore() {
        XCTAssertTrue(BandScoreGuard.matches(in: "这一场 12 分钟，答了 5 题。").isEmpty)
        XCTAssertEqual(BandScoreGuard.stripping("这一场 12 分钟，答了 5 题。"),
                       "这一场 12 分钟，答了 5 题。")
    }

    // MARK: - 挡的方式

    /// **按句子挡，不是按字挡。** 只删「6.5」的话，剩下的是「整体大概 ，建议…」——
    /// 比留着更糟，用户会以为复盘本身坏了。
    func testItRemovesTheWholeSentenceNotJustTheDigits() {
        let text = "你的流利度进步明显。整体大概 6.5 分。下次注意补一个例子。"
        let stripped = BandScoreGuard.stripping(text)
        XCTAssertFalse(stripped.contains("6.5"))
        XCTAssertTrue(stripped.contains("你的流利度进步明显。"), stripped)
        XCTAssertTrue(stripped.contains("下次注意补一个例子。"), stripped)
        XCTAssertFalse(stripped.contains("整体大概"), "只删了数字，留下一句半截话：\(stripped)")
    }

    /// 没有命中时**一个字符都不许动**——包括不许顺手 trim 掉原有的空白。
    func testACleanSummaryComesBackUntouched() {
        let text = "你这一场答得比上次充实，理由都跟上了。"
        XCTAssertEqual(BandScoreGuard.stripping(text), text)
        XCTAssertNil(BandScoreGuard.notice(for: text))
    }

    /// **必须把挡掉的原文摆出来。** 只说「挡掉了一句话」而不说是哪一句，
    /// 等于让他怀疑复盘里还有别的东西被悄悄动过。
    func testTheNoticeQuotesWhatWasBlockedAndSaysWhy() throws {
        let notice = try XCTUnwrap(BandScoreGuard.notice(for: "整体大概 6.5 分。"))
        XCTAssertTrue(notice.contains("6.5"), "没说挡掉的是哪一句：\(notice)")
        XCTAssertTrue(notice.contains("原文"), "没说原文还在，用户会以为内容被删了")
        XCTAssertTrue(notice.contains("下一步"), "没有下一步（铁律 6）")
    }

    /// 整段都是分数时挡完是空的——**这不是「ChatGPT 没写总结」**，
    /// 两者该说的话完全不同，所以原文那一份必须留着给别人判断。
    func testAnAllScoreSummaryStripsToNothingButStillReportsWhy() {
        XCTAssertTrue(BandScoreGuard.stripping("大概 6.5 分").isEmpty)
        XCTAssertNotNil(BandScoreGuard.notice(for: "大概 6.5 分"))
    }
}
