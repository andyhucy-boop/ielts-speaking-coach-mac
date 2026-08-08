import XCTest
@testable import IELTSCoachUI

final class ChangelogTests: XCTestCase {

    func testThereIsAtLeastOneRelease() {
        XCTAssertFalse(Changelog.releases.isEmpty, "「功能升级」页一条记录都没有，等于还是占位页")
    }

    func testVersionsAreUniqueAndNewestFirst() {
        let versions = Changelog.releases.map(\.version)
        XCTAssertEqual(Set(versions).count, versions.count, "有重复的版本号")
        for (newer, older) in zip(versions, versions.dropFirst()) {
            XCTAssertEqual(newer.compare(older, options: .numeric), .orderedDescending,
                           "\(newer) 排在 \(older) 前面，但它并不更新")
        }
    }

    func testCurrentIsTheNewestOne() {
        XCTAssertEqual(Changelog.current, Changelog.releases.first)
    }

    func testEveryReleaseSaysWhatChanged() {
        for release in Changelog.releases {
            XCTAssertFalse(release.date.isEmpty, "\(release.version) 没有日期")
            XCTAssertFalse(release.headline.isEmpty, "\(release.version) 没有一句话概括")
            XCTAssertFalse(release.changes.isEmpty, "\(release.version) 一条改动都没写")
            for change in release.changes {
                XCTAssertFalse(change.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(release.version) 里有一条空的改动")
            }
        }
    }

    func testNoEmptyPromises() {
        // 「敬请期待」「即将支持」在一个自用工具的更新记录里没有任何信息量，
        // 而且它们会一直留在那儿——因为没人记得回来删。
        let banned = ["TBD", "待定", "敬请期待", "即将推出", "稍后补充", "todo", "TODO"]
        let everything = (Changelog.releases.flatMap { [$0.headline] + $0.changes }
                          + Changelog.phases.map { "\($0.title)\($0.summary)" }).joined()
        for word in banned {
            XCTAssertFalse(everything.contains(word), "更新记录里出现了「\(word)」")
        }
    }

    // MARK: - 十个阶段

    func testThereAreExactlyTenPhases() {
        // 本项目就是十个阶段（ROADMAP 第 4 节，Phase 0–1 合并算一个）。
        // 断言确切数量：少一个说明漏了，多一个说明有人在这儿加了个不存在的阶段。
        XCTAssertEqual(Changelog.phases.count, 10)
    }

    func testPhaseLabelsAreUniqueAndEndAtTen() {
        let labels = Changelog.phases.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count, "有重复的阶段编号")
        XCTAssertEqual(labels.last, "10", "最后一个阶段不是 Phase 10")
    }

    func testEveryPhaseSaysWhatItIsAndWhereItStands() {
        for phase in Changelog.phases {
            XCTAssertFalse(phase.title.isEmpty, "Phase \(phase.label) 没有标题")
            XCTAssertFalse(phase.summary.isEmpty,
                           "Phase \(phase.label) 没写它给用户带来了什么——只写阶段名等于没写")
            XCTAssertFalse(phase.status.title.isEmpty, "Phase \(phase.label) 的状态没有中文说法")
        }
    }

    func testEveryStatusHasAChineseTitle() {
        // 页面上出现 "inProgress" 这种词，对用户等于没写。
        for status in [PhaseStatus.shipped, .inProgress, .planned] {
            XCTAssertFalse(status.title.isEmpty)
            XCTAssertFalse(status.title.contains(status.rawValue), "\(status) 直接把枚举名显示出来了")
        }
    }

    func testAtLeastOnePhaseIsAlreadyShipped() {
        XCTAssertTrue(Changelog.phases.contains { $0.status == .shipped },
                      "十个阶段全都没交付，那这个 App 是怎么跑起来的")
    }
}
