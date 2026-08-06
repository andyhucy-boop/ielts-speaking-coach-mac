import XCTest

/// SwiftUI 预览的安全网。
///
/// `#Preview` 里的代码在 Xcode 打开画布时会**真的跑起来**，而本项目里不带参数的
/// `AppState()` 用的是生产那一份默认值：
/// - `preflight` 默认是 `AppState.livePreflight` → `AXDriver.preflight()` →
///   `LiveAXAccess.launchTarget()` → `NSWorkspace.shared.open(ChatGPT.app)`，
///   会在用户账号里真的把 ChatGPT 启起来并唤醒它的无障碍树（铁律 5 的红线）；
/// - `directory` 默认是 `DataDirectory.resolve()` → 在用户真实的
///   `~/Library/Application Support/IELTS Speaking Coach` 下建目录和 `.state.lock`。
///
/// 也就是说，一句 `#Preview { RootView() }` 就足以让「打开画布看一眼布局」产生真实副作用。
/// 而计划的 Architecture 一节是明确鼓励用预览的，所以这不是个假想风险。
///
/// 单元测试跑不到 `#Preview` 的代码（它只在 Xcode 画布里执行，`swift test` 只编译不运行），
/// 所以这里退一步扫源码：预览体里不许出现不带参数的 `AppState()` / `RootView()`。
/// 扫源码这一招在本项目有先例（Phase 10 Task 18 用同样的办法守「问题反馈页不许联网」）。
final class PreviewSafetyTests: XCTestCase {
    func testNoPreviewConstructsTheLiveAppState() throws {
        // 目录不在、或一个文件都没扫到，`SourceGuard` 会抛错而不是给个空数组——
        // 空数组会让下面整个循环一次都不跑，而这条测试照样是绿的。
        let files = try SourceGuard.swiftFiles()

        var scannedPreviews = 0
        var previewMarkers = 0
        for file in files {
            let source = try SourceGuard.read(contentsOf: file,
                                              describedAs: file.lastPathComponent)
            previewMarkers += SourceGuard.occurrences(of: "#Preview", in: source)
            for body in Self.previewBodies(in: source) {
                scannedPreviews += 1
                for forbidden in ["AppState()", "RootView()"] {
                    XCTAssertFalse(
                        body.contains(forbidden),
                        "\(file.lastPathComponent) 的 #Preview 里出现了「\(forbidden)」，"
                            + "打开 Xcode 画布会真的启动 ChatGPT，并在用户真实的数据目录里建文件。"
                            + "下一步：给预览注入假的 preflight 和临时 DataDirectory"
                            + "（照 PermissionGateView 的预览那样纯参数注入），"
                            + "不打算维护这个预览就把它删掉。")
                }
                // 两个参数得一起注入。只塞假 preflight 不换目录，ChatGPT 是不动了，
                // 但 `DataDirectory.resolve()` 照样会在用户真实的「应用程序支持」目录里
                // 建目录和 .state.lock；只换目录不塞假 preflight 则更糟，ChatGPT 会被启起来。
                if body.contains("AppState(") {
                    for required in ["directory:", "preflight:"] {
                        XCTAssertTrue(
                            body.contains(required),
                            "\(file.lastPathComponent) 的 #Preview 构造了 AppState 却没传「\(required)」，"
                                + "走的是生产默认值。下一步：把 directory 换成临时目录、"
                                + "preflight 换成固定返回值的假实现，两个都要传。")
                    }
                }
            }
        }
        XCTAssertGreaterThan(
            scannedPreviews, 0,
            "一个 #Preview 都没扫到。要么预览全被删了（那这条测试可以一起删），"
                + "要么 previewBodies 的解析写坏了、这条测试已经在空转。下一步：两种都得看一眼。")
        // **每一个 `#Preview` 都得被切出来。** 只断言「切到了至少一个」的话，
        // 解析器少切一个（比如遇到空预览体就提前收工）就等于那几个预览悄悄没人守了——
        // 而它们恰恰是会真的启动 ChatGPT 的那种代码。
        XCTAssertEqual(
            scannedPreviews, previewMarkers,
            "源码里有 \(previewMarkers) 个 `#Preview`，只切出来 \(scannedPreviews) 个预览体，"
                + "剩下的没有被检查。下一步：看 `previewBodies` 的大括号配对是不是漏了某种写法。")
    }

    // MARK: - 扫源码用的小工具

    // 遍历目录、读文件、大括号配对这三件事都收在 `Support/SourceGuard.swift` 里，
    // 那边有一整组自测钉着「读不到源码时必须抛错」。这里只留预览体的切分。

    /// 取出源码里每个 `#Preview` 后面那对大括号中间的内容（大括号配对，能吃下嵌套，
    /// 跳过字符串字面量里的括号——配对逻辑与 `SourceGuard.memberBody` 共用一份）。
    ///
    /// 注意：这个解析看不懂注释。源文件的注释里别写反引号包起来的 `#Preview` + 左大括号，
    /// 否则会把后面的代码当成预览体扫进来。
    static func previewBodies(in source: String) -> [String] {
        var bodies: [String] = []
        var cursor = source.startIndex
        while let marker = source.range(of: "#Preview", range: cursor..<source.endIndex) {
            cursor = marker.upperBound
            // 用区间推进游标，而不是「拿内容再去原文里找一遍」——
            // 两个预览体一模一样时，那种找法会原地打转。
            guard let body = SourceGuard.balancedBodyRange(after: cursor, in: source) else { break }
            bodies.append(String(source[body]))
            cursor = body.upperBound
        }
        return bodies
    }
}
