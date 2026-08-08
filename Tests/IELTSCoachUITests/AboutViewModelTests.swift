import Foundation
import IELTSCoachCore
import XCTest
@testable import IELTSCoachUI

final class AboutViewModelTests: XCTestCase {
    private let dataDirectory = URL(
        fileURLWithPath: "/Users/tester/Library/Application Support/IELTS Speaking Coach")

    private func metadata(channel: SignatureChannel = .selfSigned) -> AppMetadata {
        AppMetadata(displayName: "IELTS Speaking Coach",
                    bundleIdentifier: "com.ielts.speakingcoach",
                    shortVersion: "1.0.0", buildNumber: "42",
                    buildCommit: "a1b2c3d", buildDate: "2026-08-06T09:00:00Z",
                    signingIdentity: "IELTS Coach Dev", channel: channel)
    }

    private func rows(channel: SignatureChannel = .selfSigned,
                      permission: PermissionState = .ready,
                      findings: [PortabilityFinding] = []) -> [AboutRow] {
        AboutViewModel.rows(metadata: metadata(channel: channel),
                            dataDirectory: dataDirectory,
                            permission: permission,
                            portabilityFindings: findings)
    }

    func testEveryRowHasBothALabelAndAValue() {
        // 只有标签没有内容的一行，会让人以为程序坏了。
        for row in rows() {
            XCTAssertFalse(row.label.isEmpty, "\(row.id) 缺标签")
            XCTAssertFalse(row.value.isEmpty, "\(row.id) 缺内容")
        }
    }

    func testRowIDsAreUnique() {
        let ids = rows().map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "ForEach 用 id 渲染，重复会错乱")
    }

    func testDataDirectoryRowShowsTheRealPathAndSaysItIsPortable() {
        let row = rows().first { $0.id == "dataDirectory" }
        XCTAssertEqual(row?.value, dataDirectory.path)
        XCTAssertTrue(row?.hint.contains("拷") ?? false,
                      "数据目录这行必须告诉用户「换电脑时拷这个文件夹」，那是这一行存在的全部意义")
    }

    func testBundleIdentifierRowExplainsWhyItNeverChanges() {
        let row = rows().first { $0.id == "bundle" }
        XCTAssertEqual(row?.value, "com.ielts.speakingcoach")
        XCTAssertFalse(row?.hint.isEmpty ?? true,
                       "这一行要解释为什么这个标识永远不变——它是辅助功能授权的锚")
    }

    func testSelfSignedSignatureRowTellsTheRecipientHowToOpenIt() {
        let row = rows(channel: .selfSigned).first { $0.id == "signature" }
        let hint = row?.hint ?? ""
        XCTAssertTrue(hint.contains("系统设置"), "没说去哪儿：\(hint)")
        XCTAssertTrue(hint.contains("仍要打开"), "没说点什么：\(hint)")
    }

    func testDeveloperIDSignatureRowDoesNotScareTheUser() {
        let hint = rows(channel: .developerID).first { $0.id == "signature" }?.hint ?? ""
        XCTAssertFalse(hint.contains("仍要打开"),
                       "已公证的包双击就能开，不该还教人绕 Gatekeeper")
    }

    func testPermissionRowCarriesANextStepWhenNotGranted() {
        let granted = rows(permission: .ready).first { $0.id == "permission" }
        XCTAssertFalse(granted?.value.isEmpty ?? true)

        for state in [PermissionState.needsAccessibility, .needsChatGPT, .unknown] {
            let row = rows(permission: state).first { $0.id == "permission" }
            XCTAssertTrue(row?.hint.contains("下一步") ?? false,
                          "\(state) 没告诉用户下一步做什么")
        }
    }

    func testPortabilityRowSaysOKWhenCleanAndCountsWhenNot() {
        let clean = rows().first { $0.id == "portability" }
        XCTAssertTrue(clean?.value.contains("没有发现问题") ?? false)

        let finding = PortabilityFinding(location: "sessions[0].reportPath", value: "/abs/a.json",
                                         problem: "绝对路径。", nextStep: "改成相对路径。")
        let dirty = rows(findings: [finding, finding]).first { $0.id == "portability" }
        XCTAssertTrue(dirty?.value.contains("2") ?? false, "要说清有几处")
        XCTAssertTrue(dirty?.hint.contains("sessions[0].reportPath") ?? false,
                      "至少要把第一条的位置显示出来，否则用户不知道去哪儿看")
    }

    func testDevelopmentRunStillProducesCompleteRows() {
        // swift run 直接跑（没有 App bundle）时，关于页照样得能看。
        let rows = AboutViewModel.rows(metadata: AppMetadata.from(infoDictionary: nil),
                                       dataDirectory: dataDirectory,
                                       permission: .ready, portabilityFindings: [])
        XCTAssertFalse(rows.isEmpty)
        for row in rows { XCTAssertFalse(row.value.isEmpty, "\(row.id) 在开发运行时变成了空白") }
    }

    // MARK: - 致谢与许可

    func testAcknowledgementsCreditTheUpstreamProject() {
        let upstream = AboutViewModel.acknowledgements
            .first { $0.name.contains("ielts-speaking-coach") }
        XCTAssertNotNil(upstream, "本项目的功能范围、复盘规范与 state.json 结构都来自上游，出处必须写明")
        XCTAssertFalse(upstream?.url.isEmpty ?? true, "上游要给得出链接")
    }

    func testAcknowledgementsStateTheOpenAIDisclaimer() {
        let joined = AboutViewModel.acknowledgements
            .map { "\($0.name)\($0.role)\($0.license)" }.joined()
        XCTAssertTrue(joined.contains("无隶属关系"),
                      "这个 App 会被交到别人手上，必须写明与 OpenAI 无隶属关系")
    }

    func testEveryAcknowledgementIsComplete() {
        for item in AboutViewModel.acknowledgements {
            XCTAssertFalse(item.name.isEmpty, "致谢条目缺名字")
            XCTAssertFalse(item.role.isEmpty, "「\(item.name)」没说它在这个项目里是干什么的")
            XCTAssertFalse(item.license.isEmpty, "「\(item.name)」没写许可情况")
        }
    }

    func testAcknowledgementIDsAreUnique() {
        let ids = AboutViewModel.acknowledgements.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testLicenseNoticeCoversTrademarksAndRedistribution() {
        let notice = AboutViewModel.licenseNotice
        XCTAssertFalse(notice.isEmpty)
        XCTAssertTrue(notice.contains("商标"), "许可说明里要有商标声明")
        XCTAssertTrue(notice.contains("再分发"), "许可说明里要说清能不能再分发")
    }

    // MARK: - 上游 MIT 的合规

    /// 上游 lindsey-labs/ielts-speaking-coach 的 LICENSE，逐字照录。
    /// 核对方式：`curl https://raw.githubusercontent.com/lindsey-labs/ielts-speaking-coach/main/LICENSE`
    ///
    /// 这段英文本身就是 MIT 的那个条件：“The above copyright notice **and this permission
    /// notice** shall be included in all copies or substantial portions of the Software.”
    /// permission notice 指的是从 “Permission is hereby granted…” 到 “…THE SOFTWARE.” 的原文，
    /// 不是它的中文转述。所以下面几条比的是**逐字包含**，而不是「提到了 MIT」——
    /// 只要实现改回中文概述，它们就必须变红。
    private static let upstreamMITNotice = """
        MIT License

        Copyright (c) 2026 IELTS Speaking Coach contributors

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """

    /// 读仓库根目录的 LICENSE。读不到就让测试抛错变红——
    /// 这个文件是分发合规的一半，不能因为「读不着」而被静默跳过。
    private static func rootLicenseText() throws -> String {
        let url = URL(fileURLWithPath: #filePath)   // Tests/IELTSCoachUITests/AboutViewModelTests.swift
            .deletingLastPathComponent()            // Tests/IELTSCoachUITests
            .deletingLastPathComponent()            // Tests
            .deletingLastPathComponent()            // 仓库根目录
            .appendingPathComponent("LICENSE")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testLicenseNoticeShipsTheUpstreamMITNoticeVerbatim() {
        // 交到别人手上的是 .app，不是这个仓库。licenseNotice 是编进二进制、
        // 由关于页原样显示的那一份，所以 MIT 原文必须在它里面——
        // 「随副本一起交付」这个条件靠的就是这一条。
        XCTAssertTrue(AboutViewModel.licenseNotice.contains(Self.upstreamMITNotice),
                      "关于页的许可全文里没有上游 MIT 的原文。"
                          + "中文转述不满足 MIT 的条件，必须逐字附上 permission notice。")
    }

    func testRootLicenseFileShipsTheUpstreamMITNoticeVerbatim() throws {
        XCTAssertTrue(try Self.rootLicenseText().contains(Self.upstreamMITNotice),
                      "根 LICENSE 里没有上游 MIT 的原文。"
                          + "别人拿到这份代码时只会读 LICENSE，条件要在那里被满足。")
    }

    func testRootLicenseFileNamesWhatCameFromUpstream() throws {
        let text = try Self.rootLicenseText()
        XCTAssertTrue(text.contains("lindsey-labs/ielts-speaking-coach"),
                      "LICENSE 没提上游项目，读的人无从知道这份 MIT 覆盖的是什么")
        XCTAssertTrue(text.contains("AnswerUpgradePolicy"),
                      "回答升级规则正文逐字来自上游，LICENSE 要点名它")
        XCTAssertTrue(text.contains("ExaminerPrompt"),
                      "考官提示词的英文契约句逐字来自上游，LICENSE 要点名它")
    }

    func testRootLicenseScopesItsAllRightsReservedClaim() throws {
        // 关于页说「MIT，要保留声明」，LICENSE 却说「全是我的，保留所有权利」，
        // 同一件事两处打架。版权主张要留，但必须把第三方那部分排除出去。
        let claims = try Self.rootLicenseText()
            .split(separator: "\n")
            .filter { $0.contains("保留所有权利") }
        XCTAssertFalse(claims.isEmpty, "LICENSE 里本来就该有作者自己的版权主张")
        for line in claims {
            XCTAssertTrue(line.contains("第三方声明"),
                          "这句「保留所有权利」没有把第三方部分排除掉：\(line)")
        }
    }

    func testUpstreamAcknowledgementPointsAtTheRealNotice() {
        let license = AboutViewModel.acknowledgements
            .first { $0.name.contains("ielts-speaking-coach") }?.license ?? ""
        XCTAssertTrue(license.contains("第三方声明"),
                      "这一条自己是中文转述，不是 notice；它必须指向真正放着 MIT 原文的地方，"
                          + "而不是声称「这一条就是它」")
    }
}
