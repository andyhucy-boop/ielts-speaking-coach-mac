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
        let files = try Self.swiftFiles(in: Self.uiSourceDirectory)
        XCTAssertFalse(
            files.isEmpty,
            "一个界面源文件都没扫到，这条测试等于空转。下一步：确认目录还在——"
                + Self.uiSourceDirectory.path)

        var scannedPreviews = 0
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
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
    }

    // MARK: - 扫源码用的小工具

    /// 被扫的目录：界面模块的全部源码。
    static var uiSourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // IELTSCoachUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
            .appending(path: "Sources/IELTSCoachUI")
    }

    static func swiftFiles(in directory: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil) else {
            throw XCTSkip("无法遍历 \(directory.path)")
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.sorted {
            $0.path < $1.path
        }
    }

    /// 取出源码里每个 `#Preview` 后面那对大括号中间的内容（大括号配对，能吃下嵌套）。
    ///
    /// 注意：这个解析看不懂注释。源文件的注释里别写反引号包起来的 `#Preview` + 左大括号，
    /// 否则会把后面的代码当成预览体扫进来。
    static func previewBodies(in source: String) -> [String] {
        var bodies: [String] = []
        var cursor = source.startIndex
        while let marker = source.range(of: "#Preview", range: cursor..<source.endIndex) {
            cursor = marker.upperBound
            guard let open = source[cursor...].firstIndex(of: "{") else { break }
            var depth = 0
            var index = open
            while index < source.endIndex {
                if source[index] == "{" { depth += 1 }
                if source[index] == "}" {
                    depth -= 1
                    if depth == 0 {
                        bodies.append(String(source[source.index(after: open)..<index]))
                        break
                    }
                }
                index = source.index(after: index)
            }
            cursor = index < source.endIndex ? source.index(after: index) : source.endIndex
        }
        return bodies
    }
}
