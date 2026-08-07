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
}
