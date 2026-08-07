import XCTest
import IELTSCoachCore
@testable import IELTSCoachMCP

/// `MCPEnvironment` 是 7 个 tool 共用的运行环境，它自己也必须被测住，
/// 否则「注入」这件事只是看起来注入了。这里守住三件事：
///
/// 1. `store` 一定落在**注入进来的目录**里。写成 `DataDirectory.resolve()` 的话，
///    Task 6–9 的每一条 tool 测试都会往用户真实的训练记录里写，而测试照样全绿。
/// 2. `timestamp` 用的是**注入进来的时刻**，格式是全项目统一的 ISO8601。
///    各处格式不一致会让按 startedAt 的字符串排序错乱。
/// 3. `timeZone` 是**注入进来的那个**，不是跑测试这台机器的。
final class MCPEnvironmentTests: XCTestCase {
    private var directory: DataDirectory!
    private var opener: FakeDashboardOpener!

    override func setUpWithError() throws {
        directory = makeTemporaryDirectory()
        opener = FakeDashboardOpener()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.root)
    }

    func testStoreWritesIntoTheInjectedDirectory() throws {
        let environment = makeEnvironment(directory: directory, opener: opener)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.stateFile.path),
                       "临时目录一开始就该是空的，否则下面那条断言什么也证明不了")

        try environment.store.mutate { $0.learner.displayName = "临时目录守卫" }

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.stateFile.path),
                      "environment.store 必须写进注入的目录 \(directory.root.path)。"
                      + "写到别处就意味着 tool 测试会去动用户真实的训练记录")
        XCTAssertEqual(try environment.store.load().learner.displayName, "临时目录守卫")
        XCTAssertEqual(environment.directory, directory)
    }

    func testTimestampUsesTheInjectedInstantInTheProjectFormat() {
        XCTAssertEqual(makeEnvironment(directory: directory, opener: opener).timestamp,
                       "2026-08-06T12:00:00Z")
        // 换一个时刻再断言一次：把 timestamp 写死成任何一个常量，都会挂在其中一条上。
        XCTAssertEqual(makeEnvironment(directory: directory, opener: opener,
                                       nowISO: "2031-12-31T23:59:07Z").timestamp,
                       "2031-12-31T23:59:07Z")
    }

    func testTimeZoneIsTheInjectedOneNotTheMachineDefault() {
        XCTAssertEqual(makeEnvironment(directory: directory, opener: opener).timeZone,
                       TimeZone(identifier: "UTC")!)
        // 同上：两个不同的时区各断言一次，写死哪个都会挂；
        // 只断言 UTC 的话，机器本身就在 UTC 时区时，改成 .current 也照样绿。
        let shanghai = MCPEnvironment(directory: directory, opener: opener,
                                      now: { Date() },
                                      timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        XCTAssertEqual(shanghai.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
    }

    func testOpenerIsTheInjectedFakeAndNothingIsOpenedByItself() throws {
        let environment = makeEnvironment(directory: directory, opener: opener)
        XCTAssertTrue(opener.opened.isEmpty, "构造运行环境本身不该唤起任何东西")

        try environment.opener.open(URL(string: "ieltscoach://dashboard")!)

        XCTAssertEqual(opener.opened.map(\.absoluteString), ["ieltscoach://dashboard"],
                       "environment.opener 必须就是注入的那个假实现——"
                       + "单元测试里一次都不许真的去开一个应用窗口")
    }
}
