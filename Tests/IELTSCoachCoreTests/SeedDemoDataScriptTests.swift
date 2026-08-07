import XCTest
@testable import IELTSCoachCore

/// `scripts/seed-demo-data.swift` 的测试。
///
/// **跑的是真实脚本，不是脚本逻辑的副本**——副本被改坏不会变红，
/// 而这个脚本会覆盖 `state.json`：它的安全闸必须由测试真的守着，
/// 不能靠读一遍代码认为它对（这一点与 `IconPipelineTests` 的做法一致）。
///
/// 计划（Phase 7 Task 10）里只安排了人工验一次安全闸。这里补成自动化的，
/// 理由是「一跑就可能抹掉用户全部练习记录」这件事，不该只在有人想起来的时候验。
///
/// **测试里绝不拿用户真实的数据目录当靶子。** 用 `CFFIXED_USER_HOME` 把
/// 「真实数据目录」整体挪到临时位置（实测：`HOME` 改不动 `FileManager` 的
/// `applicationSupportDirectory`，`CFFIXED_USER_HOME` 可以），
/// 这样即便安全闸失效，被覆盖的也只是临时目录里的哨兵文件——测试变红，数据无恙。
final class SeedDemoDataScriptTests: XCTestCase {

    // MARK: - 写进指定目录（顺带当一次独立的 schema 校验）

    func testWritesDemoDataThatTheAppCanActuallyRead() throws {
        let run = SeedDemoFixture.successfulRun
        XCTAssertEqual(run.status, 0, "脚本非零退出。stdout=\(run.stdout) stderr=\(run.stderr)")
        XCTAssertTrue(run.stdout.contains("✅"),
                      "写成功时应当打印成功标记。stdout=\(run.stdout) stderr=\(run.stderr)")
        XCTAssertTrue(run.stdout.contains("下一步"),
                      "输出里必须告诉用户下一步怎么用这份数据。stdout=\(run.stdout)")

        // 脚本手写 JSON、刻意不 import IELTSCoachCore，所以这一步同时是一次独立的
        // schema 校验：App 读不出这份文件，说明模型的容错解码有问题。
        let state = try StateStore(directory: DataDirectory(root: run.target)).load()
        XCTAssertEqual(state.sessions.count, 12, "演示数据要有 12 场练习，趋势窗口才划得开")
        XCTAssertEqual(state.issues.count, 5)
        XCTAssertEqual(state.vocabulary.count, 6)
        XCTAssertEqual(state.targets.count, 1)
        XCTAssertEqual(state.settings.weeklyGoal, 5)
    }

    func testDemoIssueOccurrencesMatchTheirSourceSessions() throws {
        // `IssueRecord` 的恒等式：occurrences == sourceSessionIds.count（读盘时会算回来）。
        // 演示数据若写了个对不上的数，用户打开 state.json 看到 6、界面上看到 5，
        // 会以为界面算错了——验收时白白耗掉一轮排查。
        let state = try StateStore(directory: DataDirectory(root: SeedDemoFixture.successfulRun.target))
            .load()
        let raw = try JSONSerialization.jsonObject(
            with: Data(contentsOf: SeedDemoFixture.successfulRun.target.appending(path: "state.json")))
        let issues = try XCTUnwrap((raw as? [String: Any])?["issues"] as? [[String: Any]])

        for issue in issues {
            let id = issue["id"] as? String ?? "?"
            let occurrences = issue["occurrences"] as? Int
            let sources = (issue["sourceSessionIds"] as? [String])?.count
            XCTAssertEqual(occurrences, sources,
                           "\(id) 写进文件的 occurrences 与 sourceSessionIds 条数对不上")
        }
        XCTAssertEqual(state.issues.count, issues.count)
    }

    // MARK: - 演示数据必须真的覆盖到要验收的每个分支

    func testDemoDataCoversEveryTrendBranch() throws {
        let state = try StateStore(directory: DataDirectory(root: SeedDemoFixture.successfulRun.target))
            .load()

        var trends: [String: IssueTrend] = [:]
        for result in IssueTrendAnalyzer.analyze(state: state) { trends[result.issueID] = result.trend }

        XCTAssertEqual(trends["issue-decreasing"], .decreasing)
        XCTAssertEqual(trends["issue-gone"], .gone)
        XCTAssertEqual(trends["issue-increasing"], .increasing)
        XCTAssertEqual(trends["issue-steady"], .steady)
        XCTAssertEqual(trends["issue-fresh"], .fresh)

        let stats = TrainingStats.compute(state: state)
        XCTAssertEqual(stats.totalSessions, 12)
        XCTAssertEqual(stats.improvingIssueCount, 2,
                       "首页第四格在演示数据上应当是 2（出现变少 + 最近没再出现）")
        XCTAssertEqual(stats.undatedSessionCount, 0)
        XCTAssertEqual(stats.sessionsMissingDuration, 0, "每场都该有能算出时长的 endedAt")
    }

    func testDemoDataDoesNotTripTheTimelineWarnings() throws {
        // 演示数据里被引用到的每一场都在 state.sessions 里。若不是这样，
        // 验收时问题档案页顶上会先糊一片数据警告，把真正要验的东西盖住。
        let state = try StateStore(directory: DataDirectory(root: SeedDemoFixture.successfulRun.target))
            .load()
        let timeline = SessionTimeline.build(state: state)
        XCTAssertEqual(timeline.warnings, [], "演示数据不该触发数据警告")
        XCTAssertEqual(timeline.orderedSessionIDs.count, 12)
    }

    func testDemoVocabularyExercisesTheExportSkipPathAndTheSanitizer() throws {
        // Task 11 Step 5 要验两件事：导出后显示「跳过了哪几条、为什么」，
        // 以及正文里带制表符/换行的那条导出后仍是一行三列。
        // 演示数据里必须真有这两条，否则那两步根本验不了。
        let state = try StateStore(directory: DataDirectory(root: SeedDemoFixture.successfulRun.target))
            .load()

        let document = VocabularyExporter.export(state.vocabulary, format: .ankiTSV)
        XCTAssertEqual(document.exportedCount, 5, "6 条里应当有 1 条因为背面为空被跳过")
        XCTAssertEqual(document.skipped.count, 1)
        XCTAssertTrue(document.skipped.first?.contains("nice") ?? false,
                      "跳过说明里应当指名是哪一条：\(document.skipped)")

        let messy = try XCTUnwrap(state.vocabulary.first { $0.id == "vocab-6" })
        XCTAssertTrue(messy.betterExpression.contains("\t"),
                      "vocab-6 应当带制表符，用来验证 TSV 清洗")
        XCTAssertTrue(messy.collocation.contains("\n"),
                      "vocab-6 应当带换行，用来验证 TSV 清洗")
    }

    func testDemoVocabularyCoversAllThreePriorityBuckets() throws {
        let state = try StateStore(directory: DataDirectory(root: SeedDemoFixture.successfulRun.target))
            .load()
        let buckets = Set(state.vocabulary.map { VocabularyPriority.normalize($0.priority) })
        XCTAssertEqual(buckets, Set(VocabularyPriority.allCases),
                       "三个档次都要有，词汇页的排序才验得出来")
    }

    // MARK: - 安全闸：拿真实数据目录当参数必须当场拒绝

    func testRefusesToOverwriteTheRealDataDirectory() throws {
        let home = try FakeHome()
        let run = SeedDemoScript.run(target: home.coachDirectory.path, fakeHome: home.root)

        let message = run.stdout + run.stderr
        XCTAssertTrue(message.contains("拒绝写入真实数据目录"),
                      "拿真实数据目录当参数，脚本没有拒绝。输出=\(message)")
        XCTAssertNotEqual(run.status, 0, "拒绝了却以 0 退出，调用方分辨不出成功还是失败")
        XCTAssertTrue(message.contains("下一步"), "拒绝时没说下一步做什么。输出=\(message)")
        XCTAssertFalse(message.contains("✅"), "拒绝了还打印成功标记，正是铁律 7 禁止的静默失败")
        XCTAssertEqual(try home.stateFileContents(), FakeHome.sentinel,
                       "真实数据目录里的 state.json 被脚本改动了")
    }

    func testRefusesToWriteIntoASubdirectoryOfTheRealDataDirectory() throws {
        // 「那我写到它下面的子目录总行了吧」——不行。那同样在用户的数据目录里，
        // 而且会让 App 下次扫到一堆假记录。
        let home = try FakeHome()
        let inside = home.coachDirectory.appending(path: "demo")
        let run = SeedDemoScript.run(target: inside.path, fakeHome: home.root)

        let message = run.stdout + run.stderr
        XCTAssertTrue(message.contains("拒绝写入真实数据目录"),
                      "真实数据目录下的子目录也该拒绝。输出=\(message)")
        XCTAssertNotEqual(run.status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inside.path),
                       "拒绝了，却已经在真实数据目录里建好了子目录")
        XCTAssertEqual(try home.stateFileContents(), FakeHome.sentinel)
    }

    func testRefusesTheRealDataDirectoryWithATrailingSlash() throws {
        // 用 Tab 补全出来的路径末尾就是带斜杠的，这才是用户最可能敲出来的形状。
        let home = try FakeHome()
        let run = SeedDemoScript.run(target: home.coachDirectory.path + "/", fakeHome: home.root)

        let message = run.stdout + run.stderr
        XCTAssertTrue(message.contains("拒绝写入真实数据目录"),
                      "末尾多一个斜杠就绕过了安全闸。输出=\(message)")
        XCTAssertNotEqual(run.status, 0)
        XCTAssertEqual(try home.stateFileContents(), FakeHome.sentinel)
    }

    func testRefusesATildePathThatExpandsIntoTheRealDataDirectory() throws {
        // 加了引号的 "~/..." 不会被 shell 展开，得由脚本自己展开。不展开就等于绕过
        // 安全闸：脚本会在当前目录下造一个名叫 "~" 的目录，用户却以为自己指的是
        // 真实数据目录，下次找不到数据也不知道发生了什么。
        //
        // **实测（Swift 6.3.3）`URL(fileURLWithPath:)` 自己就把 "~" 展开了**，
        // 所以脚本里没有、也不需要单写一行展开——写了反而没有任何测试能让它变红。
        // 这条测试守的是那个前提：哪天工具链不再展开波浪号，它会红，
        // 那时候才该往脚本里补 expandingTildeInPath。
        let home = try FakeHome()
        let run = SeedDemoScript.run(target: "~/Library/Application Support/IELTS Speaking Coach",
                                     fakeHome: home.root)

        let message = run.stdout + run.stderr
        XCTAssertTrue(message.contains("拒绝写入真实数据目录"),
                      "展开后落在真实数据目录里的波浪号路径也该拒绝。输出=\(message)")
        XCTAssertNotEqual(run.status, 0)
        XCTAssertEqual(try home.stateFileContents(), FakeHome.sentinel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: run.workingDirectory.appending(path: "~").path),
                       "波浪号没被展开，脚本在当前目录下造了个名叫 ~ 的目录")
    }

    func testRefusesARelativePathThatResolvesIntoTheRealDataDirectory() throws {
        // 「我人就站在数据目录里，写个 . 总行了吧」——这是最容易敲出来的形状之一，
        // 也是**唯一一种非得靠脚本第 29 行的 `.standardizedFileURL` 才拦得住**的形状：
        // 相对路径展开出来的是 /private/var/… 这样的物理路径，而 realRoot 是
        // 标准化过的 /var/…，两个字符串对不上，前缀比对就完全失效了。
        //
        // 实测（Swift 6.3.3）：把第 29 行改成 `URL(fileURLWithPath: outputPath)`，
        // 这一跑会打印「✅ 演示数据已写入 …」并把哨兵文件整个覆盖掉。
        let home = try FakeHome()
        let run = SeedDemoScript.run(target: ".", fakeHome: home.root,
                                     workingDirectory: home.coachDirectory)

        let message = run.stdout + run.stderr
        XCTAssertTrue(message.contains("拒绝写入真实数据目录"),
                      "站在真实数据目录里写 . 就绕过了安全闸。输出=\(message)")
        XCTAssertNotEqual(run.status, 0, "拒绝了却以 0 退出，调用方分辨不出成功还是失败")
        XCTAssertFalse(message.contains("✅"), "拒绝了还打印成功标记，正是铁律 7 禁止的静默失败")
        XCTAssertEqual(try home.stateFileContents(), FakeHome.sentinel,
                       "真实数据目录里的 state.json 被脚本覆盖了")
    }

    func testRefusesAPathThatWalksBackIntoTheRealDataDirectoryViaDotDot() throws {
        // 第二种同样要靠标准化才拦得住的形状：路径里带 ..，落点得算过才知道。
        //
        // 刻意**不**用「<真实数据目录>/../IELTS Speaking Coach」——那种写法的字符串
        // 本身就以真实数据目录开头，不标准化也会被前缀比对拦下，当不了这条防线的证人。
        // 这里绕的是它的同级：<Application Support>/nope/../IELTS Speaking Coach，
        // 字符串上看不出落点，文件系统解析后正是真实数据目录。
        let home = try FakeHome()
        let applicationSupport = home.coachDirectory.deletingLastPathComponent()
            .standardizedFileURL.path
        let detour = applicationSupport + "/nope/../\(DataDirectory.folderName)"
        let run = SeedDemoScript.run(target: detour, fakeHome: home.root)

        let message = run.stdout + run.stderr
        XCTAssertTrue(message.contains("拒绝写入真实数据目录"),
                      "带 .. 绕一圈回到真实数据目录就绕过了安全闸。输出=\(message)")
        XCTAssertNotEqual(run.status, 0)
        XCTAssertFalse(message.contains("✅"))
        XCTAssertEqual(try home.stateFileContents(), FakeHome.sentinel,
                       "真实数据目录里的 state.json 被脚本覆盖了")
    }

    func testAcceptsADirectoryThatMerelyLooksLikeTheRealOne() throws {
        // 安全闸只能挡真实数据目录本身与它下面的东西。若它顺手把
        // 「路径里带 IELTS Speaking Coach 字样」的目录也挡了，
        // 用户拿 /tmp/IELTS Speaking Coach-demo 做演示就会莫名其妙被拒。
        let home = try FakeHome()
        let sibling = home.coachDirectory.deletingLastPathComponent()
            .appending(path: "IELTS Speaking Coach-demo")
        let run = SeedDemoScript.run(target: sibling.path, fakeHome: home.root)

        XCTAssertEqual(run.status, 0,
                       "同级的演示目录被误拒了。stdout=\(run.stdout) stderr=\(run.stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.appending(path: "state.json").path))
        XCTAssertEqual(try home.stateFileContents(), FakeHome.sentinel)
    }
}

// MARK: - 跑真实脚本的小工具

enum SeedDemoScript {
    struct Run {
        var status: Int32
        var stdout: String
        var stderr: String
        var target: URL
        /// 脚本进程的工作目录。故意放在临时目录里：万一脚本没展开波浪号，
        /// 那个名叫 "~" 的目录也落不进仓库。
        var workingDirectory: URL
    }

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // IELTSCoachCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
    }

    static var scriptPath: String {
        repositoryRoot.appending(path: "scripts/seed-demo-data.swift").path
    }

    /// - Parameter workingDirectory: 脚本进程的工作目录。只有验相对路径的用例需要指定它
    ///   （站在真实数据目录里敲 `.`）；其余用例用默认的临时目录即可。
    static func run(target: String, fakeHome: URL? = nil,
                    workingDirectory: URL? = nil) -> Run {
        let workingDirectory = workingDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "seed-demo-cwd-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: workingDirectory,
                                                 withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", scriptPath, target]
        process.currentDirectoryURL = workingDirectory
        var environment = ProcessInfo.processInfo.environment
        if let fakeHome { environment["CFFIXED_USER_HOME"] = fakeHome.path }
        process.environment = environment

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return Run(status: -1, stdout: "", stderr: "启动脚本失败：\(error)",
                       target: URL(fileURLWithPath: target),
                       workingDirectory: workingDirectory)
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(status: process.terminationStatus,
                   stdout: String(decoding: outData, as: UTF8.self),
                   stderr: String(decoding: errData, as: UTF8.self),
                   target: URL(fileURLWithPath: target),
                   workingDirectory: workingDirectory)
    }
}

/// 成功那一跑只做一次——`swift scripts/seed-demo-data.swift` 每跑一次都要现编译。
enum SeedDemoFixture {
    static let successfulRun: SeedDemoScript.Run = SeedDemoScript.run(
        target: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "seed-demo-\(UUID().uuidString)").path)
}

/// 一个假的家目录，里面放着「用户真实的 state.json」哨兵文件。
///
/// 脚本通过 `CFFIXED_USER_HOME` 把这里当成真实数据目录的所在地，
/// 于是安全闸可以在完全不碰用户数据的前提下被验证。
private struct FakeHome {
    static let sentinel = #"{"__guard_sentinel__":"这是用户真实的练习记录，脚本绝不能覆盖它"}"#

    let root: URL

    var coachDirectory: URL {
        root.appending(path: "Library/Application Support/IELTS Speaking Coach")
    }

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "seed-demo-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: coachDirectory, withIntermediateDirectories: true)
        try Self.sentinel.write(to: coachDirectory.appending(path: "state.json"),
                                atomically: true, encoding: .utf8)
    }

    func stateFileContents() throws -> String {
        try String(contentsOf: coachDirectory.appending(path: "state.json"), encoding: .utf8)
    }
}
