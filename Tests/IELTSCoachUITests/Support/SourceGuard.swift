import Foundation
import XCTest

/// 扫界面源码的守门员。**这个文件自己也被 `SourceGuardTests` 逐个函数守着。**
///
/// ## 为什么要有它
///
/// 本项目已经四次独立复审都撞上同一类缺陷：**视图里的一段渲染代码删掉，整套测试照样全绿。**
/// 实测证明过的四个例子：
///
/// - 删掉 `PracticeSheet` 里 `stageBlock` 与 `checklist` 那两句调用 → 369 条全绿。
///   后果：启动语音那九秒界面是纯白板，失败信息一个字都不上屏。
/// - 删掉 `QuestionBankImportResultSheet` 里那段警告渲染 → 279 条全绿。
///   后果：弹窗说「下面 2 条警告指出了文件里有问题的行」，而下面什么都没有。
/// - 把 `Components.swift` 的 `.foregroundStyle(Palette.textSecondary)` 换成一个字面灰色 → 全绿。
/// - 把 `Spacing.lg` 从 24 改成 8、`Radius.card` 从 12 改成 40 → 全绿。
///
/// 逻辑层（视图模型、解析器）测得很扎实，缺的是「这段逻辑真的被画到屏幕上了吗」。
/// `swift test` 不画界面（没有 ViewInspector / 快照那套工具），所以只能退一步扫源码。
///
/// ## 之前为什么不够
///
/// 每次复审都各自临时发明一遍扫源码的写法，一次性、各写各的，而且**已经被证明能绕过**：
/// 旧的字体扫描只认「点开头」的 `font(.`，把 `.font(Typography.label)` 换成 `.font(Font.caption)`
/// 就溜过去了。所以这里把它做成一处共用的实现，并且：
///
/// 1. **路径找不到一定抛错，绝不返回空串。** 空串会让所有 `contains` 断言恒假、
///    所有 `!contains` 断言恒真——那是最坏的一种空转，而且没有任何迹象。
/// 2. **每类违规都认同义写法**，不是只认某一种拼法（见 `fontViolations` / `colorViolations` 等）。
/// 3. **每个函数都有自测**（`SourceGuardTests`）：喂一段人造的、含违规写法的字符串给它，
///    断言它真的报错。断言函数的报错出口 (`Reporter`) 可以换成录音机，
///    所以「该红的时候真的会红」这件事本身也是被测出来的，不是靠肉眼看。
///
/// ## 它拦不住什么（边界要说清）
///
/// 扫源码不执行代码。「代码还在但跑不到」（例如把条件改成 `if let x, false`）拦不住，
/// 排版好不好看也拦不住——那部分归人工验收。它拦得住的是已经真实发生过的那几种退化：
/// 整段渲染被删、按钮体被掏空、写好的组件没摆进页面、样式绕开令牌。
enum SourceGuard {

    // MARK: - 报错出口

    /// 断言函数把失败交给谁。默认是 `XCTFail`；自测时换成录音机，
    /// 这样「该报错时真的报了错」可以被断言，而不是靠人去看测试报告。
    typealias Reporter = (_ message: String, _ file: StaticString, _ line: UInt) -> Void

    /// 生产用的出口：真的让这条测试变红。
    ///
    /// 写成函数而不是 `static let` 闭包，是因为 Swift 6 的并发检查不让全局可变/非 Sendable
    /// 的静态闭包存在；写成函数还顺带让默认参数 `reporter: Reporter = failTest` 在每个调用点
    /// 各自成值，不共享任何状态。
    static func failTest(_ message: String, _ file: StaticString, _ line: UInt) {
        XCTFail(message, file: file, line: line)
    }

    // MARK: - 读不到源码就抛错，绝不返回空串

    enum Failure: Error, LocalizedError, CustomStringConvertible {
        case repositoryRootNotFound(startedAt: String)
        case sourceNotFound(label: String, resolved: String)
        case sourceIsADirectory(label: String, resolved: String)
        case sourceIsEmpty(label: String, resolved: String)
        case unreadable(label: String, resolved: String, underlying: String)
        case directoryNotFound(label: String, resolved: String)
        case noSwiftFiles(label: String, resolved: String)
        case memberNotFound(name: String, hint: String)

        var description: String {
            switch self {
            case .repositoryRootNotFound(let startedAt):
                return "从 \(startedAt) 一路往上都没找到 Package.swift，定位不了仓库根，"
                    + "所有扫源码的测试都会失去依据。"
                    + "下一步：确认这个测试文件仍在仓库内（`Tests/IELTSCoachUITests/Support/`），"
                    + "别把它挪到仓库外；也不要改成写死的绝对路径——那样换台机器就废了。"
            case .sourceNotFound(let label, let resolved):
                return "找不到源码文件 \(label)。扫源码的测试读不到内容就等于空转"
                    + "（空串会让 contains 恒假、!contains 恒真），所以这里直接报错。"
                    + "下一步：文件改名或挪了位置的话，同步改调用处的相对路径——期望路径是 \(resolved)"
            case .sourceIsADirectory(let label, let resolved):
                return "\(label) 是个目录不是文件（\(resolved)）。"
                    + "下一步：把相对路径写到具体的 .swift 文件上，或改用 `swiftFiles(under:)`。"
            case .sourceIsEmpty(let label, let resolved):
                return "\(label) 是空文件（\(resolved)）。空内容会让后面每一条 contains 断言恒假、"
                    + "每一条 !contains 断言恒真，整组测试当场变成空转。"
                    + "下一步：确认这个文件的内容是不是被误删了。"
            case .unreadable(let label, let resolved, let underlying):
                return "读不了 \(label)（\(resolved)）：\(underlying)。"
                    + "下一步：确认文件编码是 UTF-8、权限可读。"
            case .directoryNotFound(let label, let resolved):
                return "找不到目录 \(label)（\(resolved)），这一趟一个文件都扫不到，测试等于空转。"
                    + "下一步：目录改名或挪了位置的话，同步改调用处的相对路径。"
            case .noSwiftFiles(let label, let resolved):
                return "目录 \(label)（\(resolved)）里一个 .swift 都没有，这一趟扫了个空，测试等于空转。"
                    + "下一步：确认源码是不是被挪走了。"
            case .memberNotFound(let name, let hint):
                return "源码里找不到「\(name)」这段声明，扫描范围失效，靠它的断言全部空转。\(hint)"
            }
        }

        var errorDescription: String? { description }
    }

    // MARK: - 定位仓库（不许写死绝对路径）

    /// 这个文件自己的路径。**必须在这里取 `#filePath`**：写成函数的默认参数的话，
    /// 取到的是调用方的文件，仓库根就会跟着调用方跑。
    private static let ownFilePath = URL(fileURLWithPath: #filePath)

    /// 从本文件往上找到含 `Package.swift` 的那一层。
    ///
    /// **不硬编码绝对路径**（成品标准第 10 条的精神）：换台机器、换个克隆目录都得照样能跑。
    static func repositoryRoot() throws -> URL {
        var directory = ownFilePath.deletingLastPathComponent()
        for _ in 0..<12 {
            let manifest = directory.appending(path: "Package.swift")
            if FileManager.default.fileExists(atPath: manifest.path) { return directory }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        throw Failure.repositoryRootNotFound(startedAt: ownFilePath.path)
    }

    /// 被扫的模块。所有相对路径都以它为基准。
    static let uiSourceRelativeRoot = "Sources/IELTSCoachUI"

    static func uiSourceRoot() throws -> URL {
        try repositoryRoot().appending(path: uiSourceRelativeRoot)
    }

    // MARK: - 读源码

    /// 按相对路径读 `Sources/IELTSCoachUI/` 下的源码原文（**含注释**）。
    ///
    /// 找不到、是目录、读不出来、内容为空——四种情况一律抛错。
    static func read(_ relativePath: String) throws -> String {
        let url = try uiSourceRoot().appending(path: relativePath)
        return try read(contentsOf: url, describedAs: "\(uiSourceRelativeRoot)/\(relativePath)")
    }

    /// 读任意路径。抽出来是为了让「空文件也要抛错」这条能拿临时文件自测。
    static func read(contentsOf url: URL, describedAs label: String) throws -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw Failure.sourceNotFound(label: label, resolved: url.path)
        }
        guard !isDirectory.boolValue else {
            throw Failure.sourceIsADirectory(label: label, resolved: url.path)
        }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw Failure.unreadable(label: label, resolved: url.path,
                                     underlying: String(describing: error))
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.sourceIsEmpty(label: label, resolved: url.path)
        }
        return text
    }

    /// 读源码并去掉行注释。
    ///
    /// 几乎所有断言都该用这一个：源文件的文档注释里必然要解释「反例长什么样」
    /// （本项目的注释风格就是这样），连注释一起扫的话，测试会被自己的说明绊倒。
    static func code(_ relativePath: String) throws -> String {
        stripLineComments(try read(relativePath))
    }

    /// 遍历模块下（或某个子目录下）的全部 `.swift`。目录不存在、或一个文件都没有，都抛错。
    static func swiftFiles(under relativeDirectory: String = "") throws -> [URL] {
        let root = try uiSourceRoot()
        let directory = relativeDirectory.isEmpty ? root : root.appending(path: relativeDirectory)
        let label = relativeDirectory.isEmpty
            ? uiSourceRelativeRoot : "\(uiSourceRelativeRoot)/\(relativeDirectory)"
        return try swiftFiles(in: directory, describedAs: label)
    }

    /// 遍历任意目录下的全部 `.swift`。与上面同一份实现——
    /// 有的守卫要扫的是整个 `Sources/`（例如「全工程有没有人往 sessions 里写」），不止界面模块。
    static func swiftFiles(in directory: URL, describedAs label: String) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let walker = FileManager.default.enumerator(at: directory,
                                                          includingPropertiesForKeys: nil) else {
            throw Failure.directoryNotFound(label: label, resolved: directory.path)
        }
        let files = walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
        guard !files.isEmpty else {
            throw Failure.noSwiftFiles(label: label, resolved: directory.path)
        }
        return files
    }

    /// 把绝对 URL 换算回模块内的相对路径（报错信息里用得上）。
    static func relativePath(of url: URL) throws -> String {
        let root = try uiSourceRoot().path
        guard url.path.hasPrefix(root) else { return url.path }
        return String(url.path.dropFirst(root.count).drop(while: { $0 == "/" }))
    }

    // MARK: - 切出一段来扫

    /// 去掉 `//` 之后的内容，**但认得字符串字面量**——`"https://…"` 里的两条斜杠不算注释。
    ///
    /// 行数保持不变（每行原地截断），这样违规报告里的行号仍然对得上源文件。
    ///
    /// 边界：不认多行字符串（`"""`）与块注释（`/* */`）。界面模块里目前一个都没有
    /// （`SourceGuardTests` 之外没人写），真要开始写就得把这里换成正经的词法扫描。
    static func stripLineComments(_ source: String) -> String {
        var stripped: [String] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            var inString = false
            var escaped = false
            var cut: String.Index?
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
                    if next < line.endIndex, line[next] == "/" { cut = index; break }
                }
                index = line.index(after: index)
            }
            stripped.append(cut.map { String(line[line.startIndex..<$0]) } ?? String(line))
        }
        return stripped.joined(separator: "\n")
    }

    /// 数某段文字出现了几次。
    ///
    /// **这是「声明一次、用一次」那类断言的基础**：只问「出现过吗」的话，
    /// 把 `body` 里那句调用删掉、只留下面 `private var xxx` 的声明，断言照样绿——
    /// 而那正是本项目已经发生过的退化形态。
    static func occurrences(of needle: String, in source: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var cursor = source.startIndex
        while let found = source.range(of: needle, range: cursor..<source.endIndex) {
            count += 1
            cursor = found.upperBound
        }
        return count
    }

    /// 取出某个声明后面那对大括号中间的内容（大括号配对，吃得下嵌套，跳过字符串字面量）。
    ///
    /// **为什么需要它**：同一个文件里往往有好几处「残影」——纯装饰用的 `switch`、
    /// `redo(_:)` 里对同一个方法的另一处调用。扫全文的话，把真正那颗按钮整颗删掉，
    /// 残影照样扫得到，测试仍然是绿的（复审突变 M14 / M15 实测）。
    ///
    /// `marker` 传一段能唯一定位到那个声明的文字，例如 `"private var actions"`。
    static func memberBody(of marker: String, in code: String) throws -> String {
        guard let declaration = code.range(of: marker) else {
            throw Failure.memberNotFound(
                name: marker,
                hint: "下一步：改了这段声明的名字就同步改调用处的 marker；"
                    + "整段被删掉的话，先想清楚它画的东西现在由谁负责。")
        }
        guard let body = balancedBody(after: declaration.upperBound, in: code) else {
            throw Failure.memberNotFound(
                name: marker,
                hint: "找到了声明却没找到配对的大括号。"
                    + "下一步：确认这段声明后面确实有一对完整的 `{ … }`。")
        }
        return body
    }

    /// 从 `start` 往后找第一个 `{`，返回它与配对 `}` 之间的内容。找不到返回 nil。
    static func balancedBody(after start: String.Index, in source: String) -> String? {
        balancedBodyRange(after: start, in: source).map { String(source[$0]) }
    }

    /// 同上，但返回的是区间——连着扫好几段时用它推进游标，
    /// 比「拿内容再去原文里找一遍」可靠（两段内容一模一样时那种找法会原地打转）。
    static func balancedBodyRange(after start: String.Index,
                                  in source: String) -> Range<String.Index>? {
        guard let open = source[start...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = open
        while index < source.endIndex {
            let character = source[index]
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
                    if depth == 0 { return source.index(after: open)..<index }
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    // MARK: - 违规：一条违规长什么样

    struct Violation: Equatable, CustomStringConvertible {
        /// 违反的是哪一类规矩（报告里的抬头）。
        let rule: String
        /// 1 起算的行号，对得上源文件。
        let line: Int
        /// 命中的那一小段原文。
        let evidence: String
        /// 下一步做什么（铁律 4：说清「发生了什么」和「下一步做什么」）。
        let nextStep: String

        var description: String {
            "第 \(line) 行 · \(rule)：「\(evidence)」。下一步：\(nextStep)"
        }
    }

    // MARK: - 字体：`.font(` 与 `Font.` 与 `.weight(` 都要认

    /// 视图里不许自己拼字体。**三种同义写法都得认**，这正是旧扫描漏掉的地方：
    ///
    /// - `.font(.caption)` —— 直接写语义字体（旧扫描只认这一种）；
    /// - `.font(Font.caption)` —— 换个拼法就绕过去了（**实测能溜**）；
    /// - `.fontWeight(.bold)` / `.weight(.medium)` / `.bold()` —— 在视图里单独改字重。
    ///
    /// 为什么较真：DESIGN-SYSTEM 第 1 节的字体表里「字重」是单独一列，
    /// 而 SwiftUI 只有一部分语义字体自带字重（`.headline` 是 semibold，
    /// `.caption`、`.title`、`.largeTitle` 默认都是 regular）。
    /// 写 `.font(.caption)` 编得过、跑得动，只是比规范轻一档——
    /// 而 `.caption` 的标签本来就压在 56% 黑上，再轻一档正是那种「说不上哪儿不对」。
    /// `SectionHeader` 已经这么掉过一次。
    ///
    /// 注意：`.monospacedDigit()` 不算违规。它管的是数字对齐（表里对数字那一行的硬性要求），
    /// 不是字号也不是字重。
    static func fontViolations(in source: String) -> [Violation] {
        var found: [Violation] = []
        let text = source as NSString
        let starts = lineStartOffsets(in: text)

        // 每一处 `.font(…)` 的参数都必须引用 Typography 令牌。
        // 取的是配对括号里的整段，所以三元表达式
        // （`.font(highlighted ? Typography.cardTitle : Typography.body)`）不会被误判。
        for range in ranges(of: #"\.font\s*\("#, in: text) {
            let openParen = range.location + range.length - 1
            guard let argument = balancedArgument(in: text, openParenAt: openParen) else { continue }
            guard !argument.contains("Typography.") else { continue }
            found.append(Violation(
                rule: "字体没走 Typography 令牌",
                line: lineNumber(forOffset: range.location, starts: starts),
                evidence: ".font(\(argument))",
                nextStep: "换成 `Typography` 里对应的那一档（DESIGN-SYSTEM 第 1 节字体表）；"
                    + "表里没有的档位，先往 `Typography` 里加一个令牌再用。"))
        }

        found += violations(
            matching: #"\bFont\s*\."#, in: text, starts: starts,
            rule: "视图里直接引用了 SwiftUI 语义字体（Font.…）",
            nextStep: "字体一律从 `Typography` 取。`.font(Font.caption)` 与 `.font(.caption)` "
                + "是同一件事，只是拼法不同——两种都绕开了字体表的字重那一列。")

        found += violations(
            matching: #"\.(fontWeight|weight|fontDesign|fontWidth)\s*\("#, in: text, starts: starts,
            rule: "在视图里单独指定字重/字形",
            nextStep: "字重由 DESIGN-SYSTEM 第 1 节的字体表说了算，写在视图里就等于"
                + "把那一列交给了这一处视图。改成引用 `Typography` 里已经带好字重的令牌。")

        found += violations(
            matching: #"\.(bold|italic)\s*\(\s*\)"#, in: text, starts: starts,
            rule: "在视图里单独加粗/倾斜",
            nextStep: "同上：改成 `Typography` 里对应档位的令牌。")

        return found.sorted { $0.line < $1.line }
    }

    // MARK: - 颜色：字面构造色与字面语义色都要认

    /// 视图里不许出现字面颜色。**两大类同义写法都得认**：
    ///
    /// - 字面构造：`Color(red:…)`、`Color(.sRGB…)`、`Color(white:…)`、`#colorLiteral(…)`、`NSColor(…)`；
    /// - 字面语义色：`Color.gray`、`.foregroundStyle(.secondary)`、`.tint(.blue)`。
    ///
    /// 为什么较真：把 `.foregroundStyle(Palette.textSecondary)` 换成一个字面灰色，
    /// 全套测试一条都不红（实测），而 `Palette.textSecondary` 的 56% 不透明度是按
    /// 4.5:1 的对比度底线定的，随手换个灰就掉到「灰上加灰」——界面显廉价的头号原因。
    /// 另外深色模式（Phase 10 Task 12/13）只改 `Palette` 一个文件，
    /// 颜色一旦散到视图里，加深色模式就变成一次全局重写。
    static func colorViolations(in source: String) -> [Violation] {
        var found: [Violation] = []
        let text = source as NSString
        let starts = lineStartOffsets(in: text)

        found += violations(
            matching: #"Color\s*\(\s*(red\s*:|hue\s*:|white\s*:|\.sRGB|\.displayP3|cgColor\s*:|nsColor\s*:)"#,
            in: text, starts: starts,
            rule: "视图里写了字面构造色",
            nextStep: "颜色一律从 `Palette` 取。取值只允许写在 "
                + "`DesignSystem/Palette.swift` 里，那是深色模式唯一要改的文件。")

        found += violations(
            matching: #"#colorLiteral\s*\("#, in: text, starts: starts,
            rule: "视图里写了颜色字面量",
            nextStep: "同上，改成 `Palette` 里的令牌。")

        found += violations(
            matching: #"\b(NSColor|UIColor)\s*\("#, in: text, starts: starts,
            rule: "视图里直接构造了平台颜色",
            nextStep: "同上，改成 `Palette` 里的令牌。")

        found += violations(
            matching: #"\bColor\s*\.\s*(\#(semanticColorNames))\b"#, in: text, starts: starts,
            rule: "视图里写了字面语义色",
            nextStep: "`Color.gray` 和 `.gray` 是同一件事，只是拼法不同。改成 `Palette` 里"
                + "有对比度测试守着的那个令牌。")

        // 点开头的语义色（`.foregroundStyle(.secondary)`）只在「吃颜色的修饰符」参数里算数，
        // 否则 `Typography.secondary`、`.top`、`.leading` 这些会被误伤。
        let semanticInArgument = try? NSRegularExpression(
            pattern: #"(?<![A-Za-z0-9_])\.(\#(semanticColorNames))\b"#)
        for modifier in colorTakingModifiers {
            for range in ranges(of: #"\.\#(modifier)\s*\("#, in: text) {
                let openParen = range.location + range.length - 1
                guard let argument = balancedArgument(in: text, openParenAt: openParen) else { continue }
                let argumentText = argument as NSString
                guard let regex = semanticInArgument,
                      let hit = regex.firstMatch(
                        in: argument, range: NSRange(location: 0, length: argumentText.length))
                else { continue }
                found.append(Violation(
                    rule: "视图里写了字面语义色",
                    line: lineNumber(forOffset: range.location, starts: starts),
                    evidence: ".\(modifier)(…\(argumentText.substring(with: hit.range))…)",
                    nextStep: "改成 `Palette` 里的令牌。系统语义色（`.secondary`、`.gray`）"
                        + "不受这个设计系统的对比度测试保护，也不会跟着 Phase 10 的深色模式走。"))
            }
        }

        return found.sorted { $0.line < $1.line }
    }

    /// SwiftUI 自带的语义色名。视图里出现其中任何一个都算绕开了 `Palette`。
    private static let semanticColorNames = "red|orange|yellow|green|mint|teal|cyan|blue|indigo"
        + "|purple|pink|brown|white|black|gray|grey|clear"
        + "|primary|secondary|tertiary|quaternary|accentColor"

    /// 会吃颜色的修饰符。点开头的语义色只在这些的参数里判违规。
    private static let colorTakingModifiers = [
        "foregroundStyle", "foregroundColor", "background", "backgroundStyle",
        "tint", "fill", "stroke", "strokeBorder", "border", "accentColor",
        "shadow", "underline", "strikethrough", "listRowBackground"
    ]

    // MARK: - 圆角与描边：认 `cornerRadius: <数字>`

    /// 圆角、描边宽度不许写字面数字。
    ///
    /// 为什么较真：把 `Radius.card` 从 12 改成 40 全套测试都不红（实测），
    /// 说明这一档本来就没人守；再让视图各写各的字面值，就会出现「圆角差 2pt、
    /// 边框深浅不一」的三种卡片——界面显得业余的头号原因，而且不会体现在任何一条测试上。
    static func shapeViolations(in source: String) -> [Violation] {
        let text = source as NSString
        let starts = lineStartOffsets(in: text)
        var found: [Violation] = []

        found += violations(
            matching: #"cornerRadius\s*:\s*-?[0-9]"#, in: text, starts: starts,
            rule: "圆角写了字面数字",
            nextStep: "改成 `Radius.card` / `Radius.control` / `Radius.pill`"
                + "（DESIGN-SYSTEM 第 3 节）。")

        found += violations(
            matching: #"\.cornerRadius\s*\(\s*-?[0-9]"#, in: text, starts: starts,
            rule: "圆角写了字面数字",
            nextStep: "同上，改成 `Radius` 里的令牌。")

        found += violations(
            matching: #"lineWidth\s*:\s*-?[0-9]"#, in: text, starts: starts,
            rule: "描边宽度写了字面数字",
            nextStep: "改成 `BorderWidth.hairline`。边框粗细一旦散落到各个视图里，"
                + "就再没有「统一改一次」的机会了。")

        return found.sorted { $0.line < $1.line }
    }

    // MARK: - 间距：认字面 padding / spacing

    /// 内边距、行间距不许写字面数字（`.frame(width:)` 那类版面尺寸不算，它们不是设计令牌）。
    static func spacingViolations(in source: String) -> [Violation] {
        let text = source as NSString
        let starts = lineStartOffsets(in: text)
        var found: [Violation] = []

        found += violations(
            matching: #"\.padding\s*\(\s*-?[0-9]"#, in: text, starts: starts,
            rule: "内边距写了字面数字",
            nextStep: "改成 `Spacing` 里的令牌（页面内边距 `Spacing.xl`，卡片 `Spacing.lg`）。")

        found += violations(
            matching: #"\.padding\s*\(\s*\.[A-Za-z]+\s*,\s*-?[0-9]"#, in: text, starts: starts,
            rule: "内边距写了字面数字",
            nextStep: "同上，改成 `Spacing` 里的令牌。")

        found += violations(
            matching: #"\bspacing\s*:\s*-?[0-9]"#, in: text, starts: starts,
            rule: "间距写了字面数字",
            nextStep: "改成 `Spacing` 里的令牌。设计稿里的留白很足，那是它显得高级的主要原因——"
                + "不要为了多塞内容压缩留白。")

        return found.sorted { $0.line < $1.line }
    }

    /// 四类合起来：视图里不该出现的字面样式值。
    static func designTokenViolations(in source: String) -> [Violation] {
        (fontViolations(in: source) + colorViolations(in: source)
            + shapeViolations(in: source) + spacingViolations(in: source))
            .sorted { ($0.line, $0.rule) < ($1.line, $1.rule) }
    }

    /// 直接扫一个文件（自动去注释）。读不到会抛错，不会静默给空串。
    static func designTokenViolations(inFileAt relativePath: String) throws -> [Violation] {
        designTokenViolations(in: try code(relativePath))
    }

    // MARK: - 断言：这段渲染必须在

    /// 断言某文件里某段渲染 / 某个符号存在，且至少出现 `atLeast` 次。
    ///
    /// **`atLeast: 2` 是常用值**，含义是「声明一次、用一次」：只要求出现过的话，
    /// 把 `body` 里那句调用删掉、只留 `private var xxx` 的声明，断言照样绿——
    /// 而那时用户已经一个字都看不到了。
    static func assertRenders(_ needle: String,
                              in relativePath: String,
                              atLeast minimum: Int = 1,
                              because reason: String,
                              reporter: Reporter = failTest,
                              file: StaticString = #filePath,
                              line: UInt = #line) {
        withCode(of: relativePath, reporter: reporter, file: file, line: line) { code in
            let count = occurrences(of: needle, in: code)
            guard count < minimum else { return }
            let shortfall = minimum == 1
                ? "「\(needle)」在 \(relativePath) 里一次都没出现。"
                : "「\(needle)」在 \(relativePath) 里只出现了 \(count) 次，至少要 \(minimum) 次"
                    + "（\(minimum) 次的含义通常是：声明一次、在 body 里真的用一次）。"
            reporter(shortfall + reason, file, line)
        }
    }

    /// 同上，但只在某个声明的大括号里找。
    ///
    /// 用于那些「同一个文件里另有残影」的场合：纯装饰用的 `switch`、别处的另一次调用。
    /// 扫全文会把残影当成还在，扫这一段才问得出「真正画出来的那处还在不在」。
    static func assertRenders(_ needle: String,
                              inBodyOf marker: String,
                              of relativePath: String,
                              atLeast minimum: Int = 1,
                              because reason: String,
                              reporter: Reporter = failTest,
                              file: StaticString = #filePath,
                              line: UInt = #line) {
        withCode(of: relativePath, reporter: reporter, file: file, line: line) { code in
            do {
                let body = try memberBody(of: marker, in: code)
                let count = occurrences(of: needle, in: body)
                guard count < minimum else { return }
                reporter("\(relativePath) 的「\(marker)」那一段里，「\(needle)」只出现了 \(count) 次，"
                            + "至少要 \(minimum) 次。" + reason, file, line)
            } catch {
                reporter("\(relativePath)：\(error)", file, line)
            }
        }
    }

    /// 断言某文件**不含**某种写法。
    static func assertOmits(_ needle: String,
                            in relativePath: String,
                            because reason: String,
                            reporter: Reporter = failTest,
                            file: StaticString = #filePath,
                            line: UInt = #line) {
        withCode(of: relativePath, reporter: reporter, file: file, line: line) { code in
            guard code.contains(needle) else { return }
            reporter("\(relativePath) 里出现了「\(needle)」。" + reason, file, line)
        }
    }

    /// 断言某文件的样式全部走设计令牌：字面字体、字面颜色、字面圆角、字面间距一个都不许有。
    ///
    /// 这一条守的是「同一类缺陷还能从哪儿溜过去」——它认同义写法，
    /// 所以把 `.font(Typography.label)` 换成 `.font(Font.caption)`、
    /// 把 `Palette.textSecondary` 换成 `.gray` 或 `Color(white: 0.55)`，
    /// 三种绕法都会在这里变红。
    static func assertUsesDesignTokens(in relativePath: String,
                                       reporter: Reporter = failTest,
                                       file: StaticString = #filePath,
                                       line: UInt = #line) {
        withCode(of: relativePath, reporter: reporter, file: file, line: line) { code in
            let found = designTokenViolations(in: code)
            guard !found.isEmpty else { return }
            reporter("\(relativePath) 有 \(found.count) 处样式没走设计令牌（铁律 6）：\n"
                        + found.map { "  • " + $0.description }.joined(separator: "\n"),
                     file, line)
        }
    }

    /// 读源码这一步失败时，**必须报错**而不是拿空串继续跑：
    /// 空串会让后面每条 `contains` 恒假、每条 `!contains` 恒真。
    private static func withCode(of relativePath: String,
                                 reporter: Reporter,
                                 file: StaticString,
                                 line: UInt,
                                 body: (String) -> Void) {
        do {
            body(try code(relativePath))
        } catch {
            reporter("\(error)", file, line)
        }
    }

    // MARK: - 正则与偏移量换行号

    private static func ranges(of pattern: String, in text: NSString) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text as String,
                             range: NSRange(location: 0, length: text.length)).map(\.range)
    }

    private static func violations(matching pattern: String,
                                   in text: NSString,
                                   starts: [Int],
                                   rule: String,
                                   nextStep: String) -> [Violation] {
        ranges(of: pattern, in: text).map { range in
            Violation(rule: rule,
                      line: lineNumber(forOffset: range.location, starts: starts),
                      evidence: text.substring(with: range).trimmingCharacters(in: .whitespaces),
                      nextStep: nextStep)
        }
    }

    private static func lineStartOffsets(in text: NSString) -> [Int] {
        var starts = [0]
        for offset in 0..<text.length where text.character(at: offset) == 0x0A {
            starts.append(offset + 1)
        }
        return starts
    }

    private static func lineNumber(forOffset offset: Int, starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        return low + 1
    }

    /// 取 `openParenAt` 那个 `(` 与配对 `)` 之间的内容。跳过字符串字面量里的括号。
    ///
    /// 用它而不是「读到行尾」，是因为参数经常跨行，例如
    /// `.background(Palette.card,\n            in: RoundedRectangle(cornerRadius: Radius.control))`。
    ///
    /// 边界：字符串插值里如果再出现引号会认错。界面模块里没有这种写法。
    static func balancedArgument(in text: NSString, openParenAt start: Int) -> String? {
        guard start < text.length, text.character(at: start) == 0x28 else { return nil }
        var depth = 0
        var inString = false
        var index = start
        while index < text.length {
            let unit = text.character(at: index)
            if inString {
                if unit == 0x5C { index += 2; continue }   // 反斜杠转义
                if unit == 0x22 { inString = false }
            } else if unit == 0x22 {
                inString = true
            } else if unit == 0x28 {
                depth += 1
            } else if unit == 0x29 {
                depth -= 1
                if depth == 0 {
                    return text.substring(with: NSRange(location: start + 1,
                                                        length: index - start - 1))
                }
            }
            index += 1
        }
        return nil
    }
}
