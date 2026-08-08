import ApplicationServices
import Foundation
import XCTest

@testable import ChatGPTBridge

/// 代次校验那一行本身有没有人盯着。
///
/// 这一组补的是终审实测出来的一个空洞：把 `LiveAXAccess.resolve` 里的
/// `element.epoch == currentEpoch` 删掉，此前全套测试**没有一条会红**。
/// 已有的并发那一组走的是「找不到目标 App」接缝，那时 `elementMap` 恒为空，
/// `press` 无论如何都返回 false——它问的是「会不会丢 +1」「会不会当场炸」，
/// 恰恰问不到「旧引用还认不认」。
///
/// 真删掉之后会发生什么：`rawID` 每次快照都从 0 重新编号，
/// 于是一个上一趟快照留下的旧引用会**静默命中新树里编号相同的另一个元素**，
/// 本工具在 ChatGPT 里按到别的控件上——用户看到的是「按钮明明在，按下去没反应」。
///
/// **一次也不碰真实 ChatGPT，也不发出任何一次按键（铁律 3）**：
/// 接缝给的是本测试进程自己的 `AXUIElement`（没有 GUI，读属性一律失败，
/// 所以树里只有根节点一个——而这一组要的恰恰只是「映射表里有一条」），
/// 全程只问 `resolve`，`press` / `setValue` 一次都不调用。
final class LiveAXAccessEpochGuardTests: XCTestCase {
    /// 一台只认得本进程自己的 `LiveAXAccess`。
    private func selfAccess() -> LiveAXAccess {
        LiveAXAccess(locateApp: { AXUIElementCreateApplication(getpid()) })
    }

    /// 前提先钉住：这道接缝下映射表**真的有东西**。
    /// 空表的话下面那条会因为「本来就取不到」而永远绿，等于空转。
    func testTheSeamReallyPutsSomethingInTheElementMap() throws {
        let access = selfAccess()
        let nodes = access.snapshotTree()
        XCTAssertEqual(nodes.count, 1,
                       "本进程没有 GUI，树里该只有根节点一个；实际 \(nodes.count) 个，"
                           + "下面那条测试的前提要重新确认")
        let root = try XCTUnwrap(nodes.first)
        XCTAssertNotNil(access.resolve(root.element),
                        "刚取到的引用当场就认不出来——映射表根本没被填，这一组等于空转")
    }

    func testAReferenceFromThepreviousSnapshotIsRefusedEvenThoughItsRawIDStillExists() throws {
        let access = selfAccess()
        let stale = try XCTUnwrap(access.snapshotTree().first).element

        let fresh = try XCTUnwrap(access.snapshotTree().first).element
        // 关键前提：两趟的编号一模一样，只有代次不同。
        // 编号不同的话，「认不出来」可能只是因为查不到那个编号，与代次校验无关。
        XCTAssertEqual(stale.rawID, fresh.rawID,
                       "两趟快照的编号不一样，这条测试证不到代次那一行")
        XCTAssertNotEqual(stale.epoch, fresh.epoch, "代次没有涨，`snapshotTree()` 那句 +1 丢了")

        XCTAssertNil(access.resolve(stale),
                     "上一趟快照留下的旧引用还认得——它会静默命中新树里编号相同的另一个元素，"
                         + "本工具就会在 ChatGPT 里按到别的控件上")
        XCTAssertNotNil(access.resolve(fresh), "当前这一趟的引用反而认不出来了")
    }
}
