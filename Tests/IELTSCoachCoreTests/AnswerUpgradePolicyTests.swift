import XCTest
@testable import IELTSCoachCore

final class AnswerUpgradePolicyTests: XCTestCase {
    func testPart1Guidance() {
        let text = AnswerUpgradePolicy.guidance(part: "Part 1")
        XCTAssertTrue(text.contains("2至4句"))
        XCTAssertTrue(text.contains("不得把补充内容伪装成考生亲身事实"))
        XCTAssertTrue(text.contains("不得硬塞俚语"))
    }

    func testPart2Guidance() {
        let text = AnswerUpgradePolicy.guidance(part: "Part 2")
        XCTAssertTrue(text.contains("最多两分钟"))
        XCTAssertTrue(text.contains("90至120秒"))
        XCTAssertTrue(text.contains("若真实个人信息不足"))
    }

    func testPart3Guidance() {
        let text = AnswerUpgradePolicy.guidance(part: "Part 3")
        XCTAssertTrue(text.contains("4至7句"))
        XCTAssertTrue(text.contains("观点、原因、解释或例子"))
    }

    func testUnknownPartFallsBackToGeneralRule() {
        let text = AnswerUpgradePolicy.guidance(part: "full mock")
        XCTAssertTrue(text.contains("先根据问题所属Part"))
    }

    func testAllVariantsCarryTheSevenSharedRules() {
        for part in ["Part 1", "Part 2", "Part 3", "full mock"] {
            let text = AnswerUpgradePolicy.guidance(part: part)
            XCTAssertTrue(text.contains("逐题高分版生成规则"), "缺共享规则：\(part)")
            XCTAssertTrue(text.contains("示范补充，请按真实情况调整"), "缺免责措辞：\(part)")
        }
    }

    /// **一场里出现了哪几种题型，就给哪几套长度标准。**
    ///
    /// 落回通用兜底的话，那句话里三个 Part 的目标句数、词数一个都没有——
    /// 复盘照样生成、照样归档，只是这一场的长度要求悄悄变成了没有数字的一句话。
    func testEveryCombinedModeCarriesTheLengthStandardOfEachPartItRuns() {
        let markers: [ExamPart: String] = [.one: "2至4句", .two: "90至120秒", .three: "4至7句"]
        for focus in [FocusPart.part1And2, .part1And3, .part2And3] {
            let text = AnswerUpgradePolicy.guidance(part: focus.rawValue)
            for part in focus.parts {
                XCTAssertTrue(text.contains(markers[part]!),
                              "\(focus.rawValue) 缺 \(part.englishName) 的长度标准：\n\(text)")
            }
            for absent in ExamPart.allCases where !focus.includes(absent) {
                XCTAssertFalse(text.contains(markers[absent]!),
                               "\(focus.rawValue) 里混进了 \(absent.englishName) 的长度标准——"
                                   + "这一场根本不会出现那种题：\n\(text)")
            }
            XCTAssertFalse(text.contains("先根据问题所属Part选择对应长度"),
                           "\(focus.rawValue) 落回了通用兜底，"
                               + "而它明明知道自己只会出现哪几种题型：\n\(text)")
        }
    }

    /// **每一档考法都得拿到一份标准，一档都不能漏。**
    ///
    /// 这条守的是「加了一档考法却忘了给长度标准」：漏掉的那一档会静默落回兜底，
    /// 复盘一切正常，只是长度要求换成了另一套。
    func testNoFocusPartIsLeftWithoutAnyGuidance() {
        for focus in FocusPart.allCases {
            let text = AnswerUpgradePolicy.guidance(part: focus.rawValue)
            XCTAssertTrue(text.contains("逐题高分版生成规则"), "缺共享规则：\(focus.rawValue)")
            XCTAssertFalse(text.hasPrefix("\n"), "\(focus.rawValue) 的长度标准是空的")
        }
    }
}
