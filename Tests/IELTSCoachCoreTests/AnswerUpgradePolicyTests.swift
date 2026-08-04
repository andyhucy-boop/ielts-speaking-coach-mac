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
}
