import Foundation
import XCTest

/// 扫 `AVAudioEngineCapture.swift` 源码的守门员。
///
/// ## 为什么这一处只能扫源码
///
/// 那个类一调 `start()` 就打开真麦克风，而 `swift test` 跑的是没有 bundle id、
/// 没有 Info.plist 的命令行进程——真去构造它要么崩、要么挂住，何况铁律 3 明写
/// **不许真的开麦克风录音**。它内部真正可测的那一部分（什么时候可以就地停引擎、
/// 两条线不能同时进采集器）已经拆进了 `CaptureWorkQueue`，由 `CaptureWorkQueueTests`
/// 逐条钉住。
///
/// 但那样只钉住了工具，**没钉住有没有人用这个工具**：上一轮给这个文件做的两处修复
/// （`stop()` 走 `work.performOffTheTapThread`、tap 回调外包一层 `markingTapCallback`）
/// 复审实测把整个文件还原回自锁版本，768 条测试一条不红。
/// 那两处一旦掉回去，用户遇到的是：磁盘写满时 `RecordingSession.append` 在 tap 回调里
/// 调 `stop()`，而 `AVAudioEngine.stop()` / `removeTap` 会等当前这条 tap 回调返回——
/// **在 tap 回调里等 tap 回调结束**，练习当场卡死，连「我练完了」都点不动，
/// 已经录到的部分也永远收不了尾。
///
/// ## 这组测试拦得住什么、拦不住什么
///
/// 扫源码不执行代码。「写法对了但跑不到」拦不住，真机上 `AVAudioEngine` 的脾气更拦不住
/// （那部分归 Task 11 的人工验收）。它拦得住的正是已经真实发生过的那一种退化：
/// **整个文件被还原成自锁版本，而测试全绿。**
///
/// 扫描规则本身不许空转：读不到文件、切不出函数体一律抛错（绝不返回空串——空串会让
/// 每条 `contains` 恒假、每条 `!contains` 恒真），而且
/// `testTheScannerRealyReportsTheSelfLockingVersion` 拿一段手写的自锁版本喂给同一套规则，
/// 断言它真的报得出来。
private enum CaptureSource {
    static let relativePath = "Sources/IELTSCoachAudio/AVAudioEngineCapture.swift"

    enum Failure: Error, CustomStringConvertible {
        case repositoryRootNotFound(startedAt: String)
        case sourceNotFound(resolved: String)
        case sourceIsEmpty(resolved: String)
        case unreadable(resolved: String, underlying: String)
        case markerNotFound(marker: String)

        var description: String {
            switch self {
            case .repositoryRootNotFound(let startedAt):
                return "从 \(startedAt) 一路往上都没找到 Package.swift，定位不了仓库根，"
                    + "这条扫源码的测试就失去了依据。"
                    + "下一步：确认这个测试文件仍在仓库内，也不要改成写死的绝对路径——换台机器就废了。"
            case .sourceNotFound(let resolved):
                return "找不到 \(relativePath)（期望路径 \(resolved)）。读不到内容就等于空转，"
                    + "所以这里直接报错。下一步：文件改名或挪了位置的话，同步改这里的相对路径。"
            case .sourceIsEmpty(let resolved):
                return "\(relativePath) 是空文件（\(resolved)）。空内容会让下面每一条断言恒真，"
                    + "整组测试当场变成空转。下一步：确认这个文件的内容是不是被误删了。"
            case .unreadable(let resolved, let underlying):
                return "读不了 \(relativePath)（\(resolved)）：\(underlying)。"
                    + "下一步：确认文件编码是 UTF-8、权限可读。"
            case .markerNotFound(let marker):
                return "源码里找不到「\(marker)」（或它后面没有配对的大括号），"
                    + "靠它切出来的那些断言全部空转。"
                    + "下一步：改了这段声明的写法就同步改这里的 marker；"
                    + "整段被删掉的话，先想清楚它守的那件事现在归谁——"
                    + "不要为了让这条测试变绿而把 marker 改成一段随便什么都匹配得上的文字。"
            }
        }
    }

    /// 这个文件自己的路径。**必须在这里取 `#filePath`**：写成函数默认参数的话，
    /// 取到的是调用方的文件，仓库根就会跟着调用方跑。
    private static let ownFilePath = URL(fileURLWithPath: #filePath)

    static func repositoryRoot() throws -> URL {
        var directory = ownFilePath.deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: directory.appending(path: "Package.swift").path) {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        throw Failure.repositoryRootNotFound(startedAt: ownFilePath.path)
    }

    /// 读被扫的源码并去掉行注释。
    ///
    /// 去注释这一步不能省：这个项目的注释风格就是要在注释里写清「反例长什么样」
    /// （`AVAudioEngineCapture` 的文档注释里就写着 `AVAudioEngine.stop()` 与 `removeTap`），
    /// 连注释一起扫的话，测试会被自己的说明绊倒。
    static func code() throws -> String {
        let url = try repositoryRoot().appending(path: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Failure.sourceNotFound(resolved: url.path)
        }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw Failure.unreadable(resolved: url.path, underlying: String(describing: error))
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.sourceIsEmpty(resolved: url.path)
        }
        return stripLineComments(text)
    }

    /// 去掉 `//` 之后的内容，但认得字符串字面量（`"https://…"` 里的两条斜杠不算注释）。
    static func stripLineComments(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var inString = false
                var escaped = false
                var index = line.startIndex
                while index < line.endIndex {
                    let character = line[index]
                    if escaped {
                        escaped = false
                    } else if inString, character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        inString.toggle()
                    } else if !inString, character == "/" {
                        let next = line.index(after: index)
                        if next < line.endIndex, line[next] == "/" {
                            return String(line[line.startIndex..<index])
                        }
                    }
                    index = line.index(after: index)
                }
                return String(line)
            }
            .joined(separator: "\n")
    }

    /// 取 `marker` 后面那对大括号中间的内容（大括号配对，吃得下嵌套，跳过字符串字面量）。
    /// 找不到就抛错，绝不返回空串。
    static func body(after marker: String, in code: String) throws -> String {
        guard let declaration = code.range(of: marker),
              let open = code[declaration.upperBound...].firstIndex(of: "{") else {
            throw Failure.markerNotFound(marker: marker)
        }
        var depth = 0
        var inString = false
        var escaped = false
        var index = open
        while index < code.endIndex {
            let character = code[index]
            if escaped {
                escaped = false
            } else if inString, character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    if depth == 0 { return String(code[code.index(after: open)..<index]) }
                }
            }
            index = code.index(after: index)
        }
        throw Failure.markerNotFound(marker: marker)
    }

    // MARK: - 规则一：stop() 不许就地停引擎

    /// `AudioCaptureEngine.stop()` 的契约明写它可能在 onBuffer 回调里被调用
    /// （磁盘写满时 `RecordingSession.append` 当场收摊），而 `AVAudioEngine.stop()` 与
    /// `removeTap(onBus:)` 会等当前这条 tap 回调返回。就地做 = 在 tap 回调里等 tap 回调结束。
    static func stopViolations(in code: String) throws -> [String] {
        let stopBody = try body(after: "public func stop()", in: code)
        var found: [String] = []

        let handedOff = (try? body(after: "work.performOffTheTapThread", in: stopBody)) ?? ""
        if handedOff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            found.append("`stop()` 没有把停引擎/拆 tap 交给 `work.performOffTheTapThread`。"
                + "下一步：把这两件事放回 `work.performOffTheTapThread { … }` 里——"
                + "身处 tap 回调时它会挪到采集队列上做，别的线程上仍然是「返回时麦克风真的关了」。")
        }
        let inPlace = handedOff.isEmpty
            ? stopBody : stopBody.replacingOccurrences(of: handedOff, with: "")

        for call in ["engine.stop()", "removeTap"] {
            if inPlace.contains(call) {
                found.append("`stop()` 在 `work.performOffTheTapThread` 之外调了 `\(call)`："
                    + "写盘失败时这句话就在 tap 回调里跑，等于在 tap 回调里等 tap 回调结束，"
                    + "练习当场卡死。下一步：把它挪进 `work.performOffTheTapThread { … }`。")
            }
            if !handedOff.contains(call) {
                found.append("挪走了却没有真的停：`\(call)` 不在 "
                    + "`work.performOffTheTapThread` 那一段里。"
                    + "推迟不等于不做——练习结束了麦克风还开着，那盏灯没人再去关。"
                    + "下一步：确认停引擎与拆 tap 都写在那段闭包里。")
            }
        }
        return found
    }

    // MARK: - 规则二：tap 回调必须打上标记

    /// 上面那条判断靠的是「这条线程是不是正在跑 tap 回调」，而这个标记只有 tap 回调
    /// 自己打得上。不打的话，`stop()` 永远以为自己不在 tap 回调里，规则一等于没有。
    static func tapCallbackViolations(in code: String) throws -> [String] {
        let tapClosure = try body(after: "installTap(", in: code)
        var found: [String] = []

        let marked = (try? body(after: "markingTapCallback", in: tapClosure)) ?? ""
        if marked.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            found.append("tap 回调没有外包 `work.markingTapCallback { … }`。"
                + "没有这个标记，写盘失败时的 `stop()` 分辨不出自己身处 tap 回调，"
                + "会就地停引擎——那就是自锁。下一步：把回调体包回 `work.markingTapCallback` 里。")
        }
        let unmarked = marked.isEmpty
            ? tapClosure : tapClosure.replacingOccurrences(of: marked, with: "")

        if unmarked.contains("onBuffer(") {
            found.append("`onBuffer(…)` 在 `work.markingTapCallback` 之外被调用："
                + "标记盖不住它，它里面调到的 `stop()` 照样会就地停引擎。"
                + "下一步：把这次调用挪进 `work.markingTapCallback { … }`。")
        }
        if !marked.contains("onBuffer(") {
            found.append("包了一层 `work.markingTapCallback`，里面却没有调 `onBuffer(…)`："
                + "麦克风采到的音频没有交给任何人，用户练完什么都拿不到。"
                + "下一步：确认音频真的从这里交给了 `RecordingSession`。")
        }
        return found
    }
}

/// 上一轮给 `AVAudioEngineCapture` 做的两处修复，一行都没被钉住（复审实测：整个文件
/// 还原回自锁版本，768 条全绿）。这组测试就是那两处的看守。
final class AVAudioEngineCaptureWiringTests: XCTestCase {

    /// 停引擎与拆 tap 必须交给采集队列，不许在 `stop()` 里就地做。
    ///
    /// 就地做的后果不是「慢一点」：磁盘写满时 `RecordingSession.append` 在 **tap 回调里**
    /// 调 `stop()`，而 `AVAudioEngine.stop()` / `removeTap` 会等当前这条 tap 回调返回——
    /// 练习当场卡死，用户连「我练完了」都点不动，已经录到的部分也永远收不了尾。
    func testStopHandsTheWorkToTheCaptureQueueInsteadOfDoingItInPlace() throws {
        let violations = try CaptureSource.stopViolations(in: CaptureSource.code())
        XCTAssertEqual(violations, [], violations.joined(separator: "\n"))
    }

    /// tap 回调必须打上「这条线程正在跑 tap 回调」的标记。
    ///
    /// 上面那条规则靠的就是这个标记：不打，`stop()` 永远以为自己不在 tap 回调里，
    /// 于是就地停引擎——上一条守的那件事等于没守。
    func testTheTapCallbackIsMarkedSoStopCanTellWhichThreadItIsOn() throws {
        let violations = try CaptureSource.tapCallbackViolations(in: CaptureSource.code())
        XCTAssertEqual(violations, [], violations.joined(separator: "\n"))
    }

    /// **这条测试测的是上面两条会不会红。**
    ///
    /// 扫源码的规则最坏的失效方式是悄悄变成恒真（切不出函数体、匹配写法过期），
    /// 那时上面两条会一直绿着，而文件早就退回去了。所以这里手写一份**自锁版本**
    /// ——正是复审还原出来、768 条全绿的那一种——喂给同一套规则，断言它真的报得出来。
    func testTheScannerReallyReportsTheSelfLockingVersion() throws {
        let selfLocking = """
        public final class AVAudioEngineCapture: AudioCaptureEngine, @unchecked Sendable {
            private let lock = NSLock()
            private let engine = AVAudioEngine()
            private var tapped = false

            public func stop() {
                lock.lock()
                defer { lock.unlock() }
                if engine.isRunning { engine.stop() }
                guard tapped else { return }
                engine.inputNode.removeTap(onBus: 0)
                tapped = false
            }

            private func startCapturing(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
                input.installTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in
                    onBuffer(buffer)
                }
                tapped = true
            }
        }
        """

        let stopViolations = try CaptureSource.stopViolations(in: selfLocking)
        XCTAssertTrue(
            stopViolations.contains { $0.contains("engine.stop()") },
            "自锁版本的 `stop()` 就地停了引擎，扫描却一条都没报出来——"
                + "上面那条测试是恒绿的，等于没有人在看这个文件")
        XCTAssertTrue(
            stopViolations.contains { $0.contains("performOffTheTapThread") },
            "自锁版本压根没有 `work.performOffTheTapThread`，扫描却没提这件事")

        let tapViolations = try CaptureSource.tapCallbackViolations(in: selfLocking)
        XCTAssertTrue(
            tapViolations.contains { $0.contains("markingTapCallback") },
            "自锁版本的 tap 回调没打标记，扫描却一条都没报出来")
    }

    /// 规则找不到要扫的东西时必须**抛错**，不许悄悄放行。
    ///
    /// 函数改名、`installTap` 换了写法、整个文件被删空——这些情况下「没有违规」
    /// 和「扫了个空」长得一模一样，而后者是最坏的一种空转：看着有人守，实际没有。
    func testAMissingDeclarationIsAnErrorRatherThanASilentPass() {
        let noStop = "public final class AVAudioEngineCapture { public func halt() { } }"
        XCTAssertThrowsError(try CaptureSource.stopViolations(in: noStop),
                             "切不出 `stop()` 的函数体却当成「没有违规」，这条守卫就成了摆设")
        XCTAssertThrowsError(try CaptureSource.tapCallbackViolations(in: noStop),
                             "找不到 `installTap` 却当成「没有违规」，同上")
    }
}
