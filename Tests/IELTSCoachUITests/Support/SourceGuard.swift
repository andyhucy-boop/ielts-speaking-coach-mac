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
        case noEnumCases(name: String)
        case switchNotFound(subject: String)
        case noButtonTitles
        case noToggleTitles
        case noViewBody(type: String)
        case noSidebarTitles(found: Int, expected: Int)
        case noUILocations(found: [String])
        case settingsSceneNotFound
        case viewTypeNotFound(type: String)

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
            case .noEnumCases(let name):
                return "`enum \(name)` 里一个 case 声明都没扫到。状态清单一空，"
                    + "「每个状态都得有出口」那条断言就变成了恒真——最坏的一种空转。"
                    + "下一步：确认这个枚举还在、case 的写法没变（例如被改成了 struct 常量）。"
            case .switchNotFound(let subject):
                return "这段代码里找不到 `switch \(subject)`（或者它后面没有配对的大括号），"
                    + "「逐个状态问出口」那一趟一条分支都切不出来，断言等于空转。"
                    + "下一步：改了这个 switch 的写法就同步改调用处的 subject；"
                    + "整个 switch 被删掉的话，先想清楚每个状态的按钮现在由谁决定。"
            case .noButtonTitles:
                return "扫遍 \(uiSourceRelativeRoot) 一颗 `Button(\"…\")` 都没找到。"
                    + "整个界面一颗按钮都没有是不可能的，所以这多半是扫描写法失效了——"
                    + "而失效之后「文案里指的按钮真的存在吗」那条断言会永远绿。"
                    + "下一步：确认按钮的写法是不是变了（例如改成了自定义组件），同步改这里的扫描。"
            case .noToggleTitles:
                return "扫遍 \(uiSourceRelativeRoot) 一个 `Toggle(\"…\")` 都没找到。"
                    + "这个 App 至少有「保存我的回答录音」和「记录对话逐字稿」两个开关，"
                    + "所以这多半是扫描写法失效了——而失效之后「文案里指的开关真的存在吗」"
                    + "那条断言会永远绿。"
                    + "下一步：确认开关的写法是不是变了（例如标题改成了变量），同步改这里的扫描。"
            case .noViewBody(let type):
                return "\(type) 里找不到 `var body: some View`，"
                    + "「每一段渲染都得从 body 走得到」这条断言对它就无从谈起。"
                    + "下一步：确认这个类型还是不是一个 SwiftUI 视图。"
            case .noSidebarTitles(let found, let expected):
                return "`SidebarItem` 声明了 \(expected) 项，但 `title` 那个 switch 只读出 \(found) 个名字。"
                    + "「文案指的那一页叫什么」这份对照表缺了几行，"
                    + "指向那几页的文案就没人查得了。"
                    + "下一步：确认 `title` 的写法没变（例如某一支改成了插值或查表）。"
            case .noUILocations(let found):
                return "从 `RootView` 的 detail switch 里只推出了 \(found.count) 个页面"
                    + "（\(found.joined(separator: "、"))），太少了，多半是那个 switch 的写法变了。"
                    + "页面清单一空，「文案指的控件在不在那一页」就恒真——最坏的一种空转。"
                    + "下一步：确认 `RootView` 里还是 `switch current { case .today: TodayView(…) }` 这种写法。"
            case .settingsSceneNotFound:
                return "在 \(appSceneRelativePath) 里找不到 `Settings { … }` 那个场景，"
                    + "也就无从知道 ⌘, 打开的窗口是哪一页。"
                    + "指向「设置」的文案会因此完全没人查——而本项目正是在那里踩过一次坑"
                    + "（把「记录对话逐字稿」说成在设置窗口里，其实在训练记录页）。"
                    + "下一步：确认那个场景还在；真的删掉了，就同步把这一段推导删掉，"
                    + "不要让它安静地退化成空清单。"
            case .viewTypeNotFound(let type):
                return "扫遍 \(uiSourceRelativeRoot) 找不到 `struct \(type)` 的声明，"
                    + "定位不了它在哪个目录，那一页上有哪些控件就无从谈起。"
                    + "下一步：类型改名或挪到别的模块了的话，同步改这里的推导。"
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

    /// 测试自己的源码目录。
    ///
    /// **为什么测试要读测试**：手写的「逐行钉死取值」清单有个通病——新加的那一行没人写进来。
    /// 要问出「Metrics.swift 里新加的这个令牌到底有没有人钉它」，就只能去看那条测试的函数体。
    static let testSourceRelativeRoot = "Tests/IELTSCoachUITests"

    /// 读测试源码并去掉行注释。找不到照样抛错——读不到就等于那条元测试在空转。
    static func testCode(_ relativePath: String) throws -> String {
        let url = try repositoryRoot()
            .appending(path: testSourceRelativeRoot).appending(path: relativePath)
        return stripLineComments(
            try read(contentsOf: url, describedAs: "\(testSourceRelativeRoot)/\(relativePath)"))
    }

    // MARK: - 界面模块之外的源码

    /// 按**仓库根**的相对路径读源码原文（含注释）。找不到照样抛错。
    ///
    /// 下面那组 `read(_:)` / `code(_:)` 都以 `Sources/IELTSCoachUI` 为基准，
    /// 而有些必须守住的东西不在界面模块里——最典型的是
    /// `Sources/IELTSCoachApp/main.swift` 里的窗口场景：`WindowGroup` 还是 `Window`
    /// 这一个词决定了整个进程里有几份 `AppState`、开机会不会跑两遍 preflight。
    static func repositoryRead(_ relativePath: String) throws -> String {
        let url = try repositoryRoot().appending(path: relativePath)
        return try read(contentsOf: url, describedAs: relativePath)
    }

    /// 同上，并去掉行注释。**扫「不许出现某个词」时必须用这一个**：
    /// 本项目的注释风格就是要在注释里写清「为什么不用那种写法」，
    /// 连注释一起扫的话，那条断言会被自己的说明绊倒。
    static func repositoryCode(_ relativePath: String) throws -> String {
        stripLineComments(try repositoryRead(relativePath))
    }

    /// 遍历仓库里任意目录下的全部 `.swift`。目录不存在、或一个都没有，都抛错。
    static func swiftFiles(atRepositoryPath relativeDirectory: String) throws -> [URL] {
        let url = try repositoryRoot().appending(path: relativeDirectory)
        return try swiftFiles(in: url, describedAs: relativeDirectory)
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
            let cut = commentStart(in: line)
            stripped.append(cut.map { String(line[line.startIndex..<$0]) } ?? String(line))
        }
        return stripped.joined(separator: "\n")
    }

    /// 一行里行注释从哪儿开始（没有则 nil）。**认得字符串字面量**，
    /// 所以 `"https://…"` 里的两条斜杠不算。
    ///
    /// 抽出来是因为有两个使用者：去注释的那一步，和「从注释里读豁免」的那一步。
    /// 两边用同一份判断，才不会出现「这条注释被去掉了、豁免却读不到」的错位。
    static func commentStart(in line: Substring) -> String.Index? {
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
                if next < line.endIndex, line[next] == "/" { return index }
            }
            index = line.index(after: index)
        }
        return nil
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

    /// 数某个**标识符本身**出现了几次：前面挂了点号的成员名（`Palette.warning`）
    /// 和只是撞了前缀的更长的名字（`warnings`）都不算。
    ///
    /// **为什么不能用 `occurrences`**：`occurrences(of: "warning")` 是纯子串计数，
    /// `Palette.warning`、`feedback.warnings` 全都算它一次。
    /// `QuestionBankImportResultSheet` 那一行警告正好三样俱全——闭包参数 `warning`、
    /// 颜色令牌 `Palette.warning`、真正画出来的 `Label(warning, …)`——
    /// 于是「至少出现两次」这条断言被前两样凑满，把 `Label(warning, …)` 换成一句
    /// 泛泛之词照样是绿的（2026-08-06 复核实测：换掉文案全绿，
    /// 再把 `Palette.warning` 一并换成别的令牌才变红，证明数到的是那个令牌）。
    /// 凡是「参数收下了有没有真的用上」这类断言，都要用这个，不要用 `occurrences`。
    static func standaloneOccurrences(of identifier: String, in source: String) -> Int {
        guard !identifier.isEmpty else { return 0 }
        func isWordCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_"
        }
        var count = 0
        var cursor = source.startIndex
        while let found = source.range(of: identifier, range: cursor..<source.endIndex) {
            cursor = found.upperBound
            // 后面还接着字母/数字/下划线 = 撞上了更长的名字（warning 之于 warnings）。
            if found.upperBound < source.endIndex, isWordCharacter(source[found.upperBound]) {
                continue
            }
            if found.lowerBound > source.startIndex {
                let before = source[source.index(before: found.lowerBound)]
                // 前面是点号 = 成员访问（Palette.warning），不是这个标识符本身。
                // 前面是字母/数字/下划线 = 同样撞上了更长的名字。
                if before == "." || isWordCharacter(before) { continue }
            }
            count += 1
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

    /// 按函数名取函数体，**并且要求这个名字在文件里只认得出一处**。
    ///
    /// `memberBody(of:in:)` 取的是第一处文字匹配，这在「测试去读测试」的场合会咬人：
    /// 一条元测试自己就得把被查的函数名写成字符串（`named: "testFoo"`），
    /// 那个字符串要是排在真正的声明前面，切出来的就是元测试自己的函数体——
    /// 于是它检查的是自己，永远绿。这条路本次真踩了一次，所以这里干脆做成：
    /// **匹配到不是一处，就抛错，不猜。**
    static func functionBody(named name: String, in code: String) throws -> String {
        let marker = "func \(name)("
        let count = occurrences(of: marker, in: code)
        guard count == 1 else {
            throw Failure.memberNotFound(
                name: marker,
                hint: count == 0
                    ? "下一步：函数改名了就同步改这里；整条测试被删掉的话，"
                        + "先想清楚它守的那件事现在归谁。"
                    : "在同一份源码里出现了 \(count) 处，切哪一处只能靠猜——"
                        + "猜错就等于这条断言在检查另一段代码。"
                        + "下一步：把重名的那处改掉，或换一个能唯一定位的写法。")
        }
        return try memberBody(of: marker, in: code)
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

        // 字距 / 行距同样是排版取值，同样有令牌（`Tracking.label`），也同样能被随手写成字面数字。
        // 实测：把 `SectionHeader` 的 `.tracking(Tracking.label)` 换成 `.tracking(2.5)`，
        // 那行英文标签当场散架成一串孤零零的字母，而 429 条测试一条不红。
        found += violations(
            matching: #"\.(tracking|kerning|lineSpacing)\s*\(\s*-?[0-9.]"#, in: text, starts: starts,
            rule: "字距/行距写了字面数字",
            nextStep: "改成 `Tracking` 里的令牌（行距用 `Spacing`）。规范第 4 节只说「字距略宽」，"
                + "具体数值收在令牌里改一处，散到视图里就变成每处各调各的。")

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

        // 引用了令牌、却在视图里再乘一次不透明度——**这是「灰上加灰」的最后一条通道**。
        // `Palette.textSecondary` 的 56% 是按 4.5:1 那条底线定的，
        // 再 `.opacity(0.35)` 一下就掉到 2:1 上下，而它引用着令牌，前面每条规则都放它过去（实测）。
        found += violations(
            matching: #"\bPalette\s*\.\s*[A-Za-z_][A-Za-z0-9_]*\s*\.\s*opacity\s*\("#,
            in: text, starts: starts,
            rule: "在视图里给令牌颜色再调一次不透明度",
            nextStep: "令牌的不透明度是按 4.5:1 的对比度底线定的，视图里再乘一次就绕开了"
                + "`DesignSystemTests` 那几条对比度断言。真需要淡一档，往 `Palette` 里加一个令牌，"
                + "让它跟着对比度测试一起走。")

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

        // 投影没有令牌，因为规范第 4 节写的是**一个都不要有**：
        // 「设计稿里的卡片靠边框和留白分层，不靠阴影。滥用投影是让界面显脏的常见原因。」
        // 所以这里不检查参数写没写字面值，出现即违规。
        found += violations(
            matching: #"\.shadow\s*\("#, in: text, starts: starts,
            rule: "视图里加了投影",
            nextStep: "第 4 节明写卡片「不加投影」，分层靠 `Palette.cardBorder` 那道发丝边框"
                + "和 `Spacing` 的留白。真要改这条，先改规范第 4 节，再改这里——"
                + "不要在某一个视图里单独破例。")

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

    /// 四类合起来：视图里不该出现的字面样式值。**入参是已经去过注释的代码。**
    static func designTokenViolations(in source: String) -> [Violation] {
        (fontViolations(in: source) + colorViolations(in: source)
            + shapeViolations(in: source) + spacingViolations(in: source))
            .sorted { ($0.line, $0.rule) < ($1.line, $1.rule) }
    }

    // MARK: - 豁免：写在代码里、必须说得出理由、只管一行

    /// 豁免注释的写法：`// 设计令牌豁免：<理由>`，写在被豁免那一行的行尾或它的上一行。
    ///
    /// ```swift
    /// // 设计令牌豁免：这是 macOS 窗口最小尺寸，不是间距令牌
    /// .frame(minWidth: 900)
    /// ```
    ///
    /// 三条硬规矩，都是冲着「随手豁免」来的：
    ///
    /// 1. **只覆盖两行**（注释那行和它的下一行）。一条注释豁免一整段的话，
    ///    一次随手豁免就能把整个文件的守卫关掉。
    /// 2. **理由太短等于没写**，它自己就是一条违规——`// 设计令牌豁免：临时` 不算理由。
    /// 3. **豁免了却没有对应的违规，也是一条违规。** 否则规则一变，
    ///    这些「过期豁免」就静静躺在代码里，下一个人只会以为这儿本来就该破例，
    ///    而且它会替将来真正的违规挡枪。
    static let exemptionMarker = "设计令牌豁免"

    /// 理由的最短长度。8 个字够写一句「这是窗口最小尺寸」，写不下「临时」「TODO」。
    static let minimumExemptionReasonLength = 8

    struct Exemption: Equatable {
        let line: Int
        let reason: String

        var reasonIsGoodEnough: Bool { reason.count >= minimumExemptionReasonLength }
    }

    /// 从**原始源码**（含注释）里读豁免。注意不能传去过注释的文本——那时豁免已经被剪掉了。
    static func exemptions(in rawSource: String) -> [Exemption] {
        var found: [Exemption] = []
        for (offset, line) in rawSource.split(separator: "\n",
                                              omittingEmptySubsequences: false).enumerated() {
            guard let commentAt = commentStart(in: line) else { continue }
            let comment = line[commentAt...]
            guard let markerAt = comment.range(of: exemptionMarker) else { continue }
            let tail = comment[markerAt.upperBound...]
                .drop(while: { $0 == "：" || $0 == ":" || $0 == " " })
            found.append(Exemption(line: offset + 1,
                                   reason: tail.trimmingCharacters(in: .whitespaces)))
        }
        return found
    }

    /// 扫一段**原始源码**：先去注释找违规，再按豁免注释过滤，最后把不合格的豁免本身算成违规。
    static func designTokenViolations(inRawSource rawSource: String) -> [Violation] {
        let raw = designTokenViolations(in: stripLineComments(rawSource))
        let declared = exemptions(in: rawSource)
        let usable = declared.filter(\.reasonIsGoodEnough)

        var covered: Set<Int> = []
        for exemption in usable {
            covered.insert(exemption.line)
            covered.insert(exemption.line + 1)   // 写在上一行的写法
        }

        var found = raw.filter { !covered.contains($0.line) }

        for exemption in declared where !exemption.reasonIsGoodEnough {
            found.append(Violation(
                rule: "豁免没说清理由",
                line: exemption.line,
                evidence: "// \(exemptionMarker)：\(exemption.reason)",
                nextStep: "豁免必须写清为什么这一处非用字面值不可（至少 "
                    + "\(minimumExemptionReasonLength) 个字）。写不出理由，说明它该改成令牌。"))
        }

        for exemption in usable
        where !raw.contains(where: { $0.line == exemption.line || $0.line == exemption.line + 1 }) {
            found.append(Violation(
                rule: "豁免是多余的",
                line: exemption.line,
                evidence: "// \(exemptionMarker)：\(exemption.reason)",
                nextStep: "这一行现在并没有违规，豁免却还挂着。留着它，下一个人会以为这儿"
                    + "本来就该破例，而且它会替将来真正的违规挡枪。下一步：删掉这条豁免。"))
        }

        return found.sorted { ($0.line, $0.rule) < ($1.line, $1.rule) }
    }

    /// 直接扫一个文件。读不到会抛错，不会静默给空串。
    static func designTokenViolations(inFileAt relativePath: String) throws -> [Violation] {
        designTokenViolations(inRawSource: try read(relativePath))
    }

    // MARK: - 令牌清单：手写的表容易漏掉新加的那一行

    /// 取某个 `public enum` 里声明的全部 `public static let` 名字（按源码顺序）。
    ///
    /// **它服务的是「表的完整性」这类断言**：`DesignSystemTests` 把令牌取值逐行钉死，
    /// 那是一份手写清单，而手写清单的通病是新加的那一行没人写进来——
    /// 实测往 `Metrics.swift` 里加一个 `Radius.sheet = 3` 并在卡片上用它，全套测试一条不红。
    static func declaredTokenNames(inEnum name: String, of code: String) throws -> [String] {
        let body = try memberBody(of: "public enum \(name)", in: code)
        return captures(of: #"public\s+static\s+let\s+([A-Za-z_][A-Za-z0-9_]*)"#, in: body)
    }

    /// 一个文件里声明了哪些 `public enum`。
    ///
    /// 上面那个函数要按名字问，那「名字的清单」本身也不能是手写的：
    /// 手写的话，往 `Metrics.swift` 里新加一整个 `public enum Elevation` 照样没人管。
    static func declaredEnumNames(in code: String) -> [String] {
        captures(of: #"public\s+enum\s+([A-Za-z_][A-Za-z0-9_]*)"#, in: code)
    }

    private static func captures(of pattern: String, in source: String) -> [String] {
        let text = source as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: source, range: NSRange(location: 0, length: text.length))
            .compactMap { $0.numberOfRanges > 1 ? text.substring(with: $0.range(at: 1)) : nil }
    }

    // MARK: - 视图成员：写好了，和摆上屏幕了，是两件事

    /// 一个 SwiftUI 类型里声明的视图成员，以及**从 `body` 出发走不到**的那些。
    ///
    /// ## 为什么要有它
    ///
    /// 上一轮已经给 `PracticeSheet` 补过逐个成员的断言（「`stageBlock` 得摆在 `practiceBody` 里」）。
    /// 那是手写的清单，于是漏掉了更上面一层：本次实测把 `body` 里
    /// `practiceBody(for: running)` 和 `actions` 那两句一起换掉，**465 条一条不红**——
    /// 而那时整张 sheet 只剩一行题目：没有进度、没有失败信息、一颗按钮都没有，
    /// 用户开一场练习就再也退不出来。
    ///
    /// 逐个手写补不完，因为下一次漏的会是下一个成员。所以这里换成结构性的问法：
    /// **从 `body` 出发顺着调用关系，能不能走到每一个 `some View` 成员？**
    /// 走不到就是没上屏。新写一段渲染却忘了摆进去，同样会在这里报出来。
    ///
    /// ## 它拦不住什么
    ///
    /// 只看「名字在那段大括号里出现过没有」。「调用还在但条件永远为假」拦不住，
    /// 摆得好不好看也拦不住——那部分归人工验收。
    struct ViewType {
        let name: String
        /// 名字 → 大括号里的内容。只收 `some View` 的成员。
        let viewMembers: [(name: String, body: String)]
        /// 声明了、但从 `body` 顺着调用关系走不到的成员名。
        let unreachable: [String]
    }

    /// 声明一个视图成员的两种写法：计算属性和返回 `some View` 的方法。
    ///
    /// 两种都得认：`PracticeSheet` 里 `stageBlock` 是属性、`practiceBody(for:)` 是方法，
    /// 只认一种的话，另一种被摘掉照样绿。
    private static let viewMemberPatterns = [
        #"(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*some\s+View\s*\{"#,
        #"func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*(?:async\s+)?(?:throws\s+)?->\s*some\s+View\s*\{"#
    ]

    /// 把一份源码里的 SwiftUI 视图类型逐个切出来分析。**入参是已经去过注释的代码。**
    ///
    /// 没有 `body` 的类型（协议实现、测试替身、纯数据结构）直接跳过——它们不是视图。
    static func viewTypes(in code: String) -> [ViewType] {
        var result: [ViewType] = []
        for (typeName, typeBody) in typeBodies(in: code) {
            var members: [(name: String, body: String)] = []
            var seen = Set<String>()
            for pattern in viewMemberPatterns {
                for (name, body) in declarations(matching: pattern, in: typeBody)
                where seen.insert(name).inserted {
                    members.append((name, body))
                }
            }
            guard members.contains(where: { $0.name == "body" }) else { continue }
            result.append(ViewType(name: typeName,
                                   viewMembers: members,
                                   unreachable: unreachable(from: "body", among: members)))
        }
        return result
    }

    /// 从 `root` 出发做一次广度优先，收集走不到的成员。
    private static func unreachable(from root: String,
                                    among members: [(name: String, body: String)]) -> [String] {
        let bodies = Dictionary(uniqueKeysWithValues: members.map { ($0.name, $0.body) })
        var reached: Set<String> = [root]
        var queue = [root]
        while let current = queue.popLast() {
            guard let body = bodies[current] else { continue }
            for candidate in members.map(\.name) where !reached.contains(candidate) {
                guard mentions(candidate, in: body) else { continue }
                reached.insert(candidate)
                queue.append(candidate)
            }
        }
        return members.map(\.name).filter { !reached.contains($0) }
    }

    /// 一段代码里有没有**以本类型成员的身份**提到某个名字。
    ///
    /// 两条讲究，缺一条这个扫描就没用了：
    ///
    /// - 前面不许紧挨着点号：`runner.stage` 里的 `stage` 是别人的属性，
    ///   认成「调用了本类型的 stage」的话会凭空多出一堆「走得到」，守卫等于关掉。
    /// - `self.actions` 与 `actions` 得算同一处引用，所以先把 `self.` 去掉再判——
    ///   否则谁写一句 `self.` 就把那段渲染从可达图里摘出去了。
    static func mentions(_ name: String, in text: String) -> Bool {
        let stripped = text.replacingOccurrences(of: "self.", with: "")
        let pattern = #"(?<![A-Za-z0-9_.])\#(NSRegularExpression.escapedPattern(for: name))\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let nsText = stripped as NSString
        return regex.firstMatch(in: stripped,
                                range: NSRange(location: 0, length: nsText.length)) != nil
    }

    /// 把源码里每个 `struct` / `class` / `enum` 的名字与大括号内容切出来。
    private static func typeBodies(in code: String) -> [(name: String, body: String)] {
        declarations(
            matching: #"\b(?:struct|class|enum|extension)\s+([A-Za-z_][A-Za-z0-9_]*)"#, in: code)
    }

    /// 按一个「第一个捕获组是名字」的正则找声明，并取它后面那对大括号里的内容。
    private static func declarations(matching pattern: String,
                                     in code: String) -> [(name: String, body: String)] {
        let text = code as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var found: [(String, String)] = []
        for match in regex.matches(in: code, range: NSRange(location: 0, length: text.length))
        where match.numberOfRanges > 1 {
            let name = text.substring(with: match.range(at: 1))
            // **从匹配的开头往后找那对大括号，不是从结尾。** 从结尾找的话，
            // 正则里那个收尾的 `{` 已经被跳过，`balancedBody` 会去认函数体内部的下一个 `{`，
            // 切出来的是半截东西——而半截东西照样能让 `contains` 恒真，那就是空转。
            guard let start = Range(NSRange(location: match.range.location, length: 0),
                                    in: code)?.lowerBound,
                  let body = balancedBody(after: start, in: code) else { continue }
            found.append((name, body))
        }
        return found
    }

    // MARK: - 每个状态都得有一条出口

    /// 取某个 `enum` 里**声明**的 case 名字（按源码顺序）。
    ///
    /// ## 为什么要有它
    ///
    /// 「每个状态下界面上都得有一颗能点的按钮」这句话，只有在**状态清单不是手写的**
    /// 时候才守得住。手写清单的通病本项目已经吃过好几次：新加的那一项没人写进来，
    /// 于是断言看着在守，实际上守的是一份过期的表。
    ///
    /// 只认声明：`switch` 里的模式匹配（`case .failed:`）以点开头，不会被当成声明；
    /// `case .capturingReview, .needsManualCopy:` 同理。
    ///
    /// 边界：嵌套类型里声明的 case 也会被算进来（界面模块里没有这种写法）。
    static func declaredCaseNames(inEnum name: String, of code: String) throws -> [String] {
        let body = try memberBody(of: "enum \(name)", in: code)
        var names: [String] = []
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("case ") else { continue }
            let tail = trimmed.dropFirst("case ".count).trimmingCharacters(in: .whitespaces)
            // 以点开头的是模式匹配，不是声明。
            guard let first = tail.first, first != "." else { continue }
            names += splitTopLevel(tail).compactMap(leadingIdentifier)
        }
        guard !names.isEmpty else { throw Failure.noEnumCases(name: name) }
        return names
    }

    /// `switch` 的一条分支。
    struct SwitchBranch: Equatable {
        /// 标签原文（不含冒号），例如 `case .practicing`、`default`。
        let label: String
        /// 这条分支接住的 case 名（不带点）。`default` 分支是空数组。
        let cases: [String]
        /// 标签底下那段代码，到下一个标签为止。
        let body: String

        var isDefault: Bool { cases.isEmpty }
    }

    /// 把一段代码里 `switch <subject>` 的分支逐条切出来。
    ///
    /// **为什么不能只扫全文**：同一个文件里往往有好几份「装饰用」的 switch
    /// （`PracticeSheet` 的 `stageIcon` / `stageTint` 就是），扫全文的话，
    /// 把按钮那一段的某个分支整块掏空，别处的同名 case 照样扫得到，测试仍然是绿的。
    /// 要问「这个状态下有没有按钮」，就得先把**那个状态自己的那一段**切出来。
    ///
    /// 边界：模式里带三元表达式（`case x where a ? b : c:`）会切错——界面模块里没有这种写法。
    static func switchBranches(over subject: String, in code: String) throws -> [SwitchBranch] {
        guard let head = code.range(of: "switch \(subject)"),
              let bodyRange = balancedBodyRange(after: head.upperBound, in: code) else {
            throw Failure.switchNotFound(subject: subject)
        }
        let body = String(code[bodyRange])

        var labels: [(start: String.Index, afterColon: String.Index, text: String)] = []
        var depth = 0
        var inString = false
        var escaped = false
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            if escaped {
                escaped = false
            } else if inString {
                if character == "\\" { escaped = true } else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
            } else if depth == 0, isBranchKeyword(at: index, in: body),
                      let colon = branchLabelColon(from: index, in: body) {
                let after = body.index(after: colon)
                labels.append((index, after, String(body[index..<colon])))
                index = after
                continue
            }
            index = body.index(after: index)
        }

        return labels.enumerated().map { offset, label in
            let end = offset + 1 < labels.count ? labels[offset + 1].start : body.endIndex
            return SwitchBranch(label: label.text.trimmingCharacters(in: .whitespacesAndNewlines),
                                cases: caseNames(inLabel: label.text),
                                body: String(body[label.afterColon..<end]))
        }
    }

    /// 一颗**用户一定点得到**的按钮。
    struct ExitButton: Equatable {
        /// `Button(` 那对括号里的原文（报错时贴出来，好知道少的是哪一颗）。
        let label: String
        /// 按下去真的会发生事情吗。空闭包的按钮是铁律 5 说的静默失败：
        /// 界面上看着有出口，点了却什么都不发生。
        let isWired: Bool
    }

    /// 一段视图代码里**无条件画出来、没有被 `.disabled` 关掉**的按钮。
    ///
    /// 三个限定缺一不可，因为「这个状态下有出口吗」问的是**一定点得到**的那一颗：
    ///
    /// - 写在 `if let retry = runner.retry { … }` 里的按钮，条件不成立时界面上就没有它；
    /// - `.disabled(picked == nil)` 那颗看得见、按不动；
    /// - `Button("取消") { }` 按得动、什么都不发生。
    ///
    /// 边界：只看写法，不执行代码。`if true { … }` 这种照样算「有条件」。
    static func unconditionalButtons(in viewCode: String) -> [ExitButton] {
        let unconditional = removingConditionalBlocks(from: viewCode)
        let marker = "Button("
        var starts: [String.Index] = []
        var cursor = unconditional.startIndex
        while let hit = unconditional.range(of: marker, range: cursor..<unconditional.endIndex) {
            starts.append(hit.lowerBound)
            cursor = hit.upperBound
        }

        var found: [ExitButton] = []
        for (offset, start) in starts.enumerated() {
            let end = offset + 1 < starts.count ? starts[offset + 1] : unconditional.endIndex
            let segment = String(unconditional[start..<end])
            // `.disabled(` 跟在这颗按钮后面 —— 它看得见，但按不动，不算出口。
            guard !segment.contains(".disabled(") else { continue }
            let argument = balancedArgument(in: segment as NSString,
                                            openParenAt: marker.count - 1) ?? ""
            found.append(ExitButton(label: argument.trimmingCharacters(in: .whitespacesAndNewlines),
                                    isWired: isWired(argument: argument, segment: segment)))
        }
        return found
    }

    /// 这颗按钮接上动作了吗：`action:` 参数非空，或者尾随闭包里真的写了东西。
    private static func isWired(argument: String, segment: String) -> Bool {
        if let action = argument.range(of: "action:"),
           !argument[action.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        guard let closure = balancedBody(after: segment.startIndex, in: segment) else { return false }
        return !closure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 去掉所有条件块（`if` / `else` / `guard` / 嵌套 `switch`）连同它们的大括号。
    ///
    /// 留下来的就是「一定会画出来」的那部分。`Button("x") { act() }` 的尾随闭包不会被误删——
    /// 它前面不是这几个关键字。
    static func removingConditionalBlocks(from code: String) -> String {
        var result = code
        var searchFrom = result.startIndex
        while let keyword = nextConditionalKeyword(in: result, from: searchFrom) {
            guard let inner = balancedBodyRange(after: keyword.upperBound, in: result) else {
                searchFrom = keyword.upperBound
                continue
            }
            let blockEnd = result.index(after: inner.upperBound)   // 连收尾的 `}` 一起吃掉
            result.removeSubrange(keyword.lowerBound..<blockEnd)
            searchFrom = keyword.lowerBound
        }
        return result
    }

    /// 下一个条件关键字在哪儿。
    ///
    /// 不收 `for` / `while`：`practiceBody(for: setup)` 里那个 `for` 是参数标签，
    /// 认成关键字的话会把后面一整块渲染当成条件块删掉——那样扫描就开始撒谎了。
    /// 同理这里要求关键字后面不是冒号。
    private static func nextConditionalKeyword(in code: String,
                                               from start: String.Index) -> Range<String.Index>? {
        let pattern = #"(?<![A-Za-z0-9_.])(if|else|guard|switch)\b(?!\s*:)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let text = code as NSString
        let utf16Start = String(code[..<start]).utf16.count
        guard utf16Start <= text.length else { return nil }
        let searchRange = NSRange(location: utf16Start, length: text.length - utf16Start)
        guard let match = regex.firstMatch(in: code, range: searchRange) else { return nil }
        return Range(match.range, in: code)
    }

    /// 这个位置上是不是一条 `case` / `default` 分支标签的开头。
    ///
    /// `.defaultAction` 不算（前面紧挨着点号）；`if case .failed = x` 也不算
    /// （`case` 前面那个词是 `if`）。
    private static func isBranchKeyword(at index: String.Index, in body: String) -> Bool {
        guard isTokenStart(at: index, in: body) else { return false }
        let rest = body[index...]
        if rest.hasPrefix("default") {
            let after = body.index(index, offsetBy: "default".count)
            return after >= body.endIndex || !isIdentifierCharacter(body[after])
        }
        guard rest.hasPrefix("case") else { return false }
        let after = body.index(index, offsetBy: "case".count)
        guard after < body.endIndex, body[after].isWhitespace else { return false }
        return !["if", "guard", "while"].contains(precedingWord(before: index, in: body))
    }

    /// 从分支标签的开头往后找那个收尾的冒号。
    ///
    /// 走到大括号还没见到冒号就返回 nil——那说明这不是一条分支标签
    /// （最典型的是 `if case .failed = runner.stage {`）。
    private static func branchLabelColon(from start: String.Index, in body: String) -> String.Index? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < body.endIndex {
            let character = body[index]
            if escaped {
                escaped = false
            } else if inString {
                if character == "\\" { escaped = true } else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if character == "(" || character == "[" {
                depth += 1
            } else if character == ")" || character == "]" {
                depth -= 1
            } else if depth == 0 {
                if character == ":" { return index }
                if character == "{" || character == "}" { return nil }
            }
            index = body.index(after: index)
        }
        return nil
    }

    /// 一条标签接住哪几个 case（`default` 与 `case let …` 都返回空数组）。
    private static func caseNames(inLabel label: String) -> [String] {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("case") else { return [] }
        return splitTopLevel(String(trimmed.dropFirst("case".count))).compactMap { piece in
            let text = piece.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix(".") else { return nil }
            return leadingIdentifier(String(text.dropFirst()))
        }
    }

    /// 按顶层逗号切开（括号、方括号、字符串里的逗号不算）。
    private static func splitTopLevel(_ text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var depth = 0
        var inString = false
        var escaped = false
        for character in text {
            if escaped {
                escaped = false
            } else if inString {
                if character == "\\" { escaped = true } else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if character == "(" || character == "[" {
                depth += 1
            } else if character == ")" || character == "]" {
                depth -= 1
            } else if character == ",", depth == 0 {
                pieces.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        pieces.append(current)
        return pieces
    }

    private static func leadingIdentifier(_ text: String) -> String? {
        let identifier = text.trimmingCharacters(in: .whitespaces).prefix(while: isIdentifierCharacter)
        return identifier.isEmpty ? nil : String(identifier)
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// 这个位置前面不是标识符的一部分，也不是点号（`.defaultAction` 里的 `default` 不算）。
    private static func isTokenStart(at index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        let previous = text[text.index(before: index)]
        return !isIdentifierCharacter(previous) && previous != "."
    }

    /// 这个位置前面（跳过空白）的那个词。
    private static func precedingWord(before index: String.Index, in text: String) -> String {
        var cursor = index
        while cursor > text.startIndex, text[text.index(before: cursor)].isWhitespace {
            cursor = text.index(before: cursor)
        }
        var word = ""
        while cursor > text.startIndex, isIdentifierCharacter(text[text.index(before: cursor)]) {
            cursor = text.index(before: cursor)
            word.insert(text[cursor], at: word.startIndex)
        }
        return word
    }

    // MARK: - 文案里指的按钮，界面上真有吗

    /// 界面模块里**字面写死的**按钮标题清单。
    ///
    /// 一颗都扫不到就抛错：那说明扫描写法失效了，而失效之后
    /// 「文案里指的按钮真的存在吗」那条断言会恒真——最坏的一种空转。
    static func literalButtonTitles() throws -> Set<String> {
        var titles: Set<String> = []
        for url in try swiftFiles() {
            let source = stripLineComments(
                try read(contentsOf: url, describedAs: try relativePath(of: url)))
            titles.formUnion(captures(of: #"Button\s*\(\s*"([^"\\]+)""#, in: source))
        }
        guard !titles.isEmpty else { throw Failure.noButtonTitles }
        return titles
    }

    /// 界面模块里**字面写死的**开关标题清单（`Toggle("…")`）。
    ///
    /// 与按钮同理，一个都扫不到就抛错。
    static func literalToggleTitles() throws -> Set<String> {
        var titles: Set<String> = []
        for url in try swiftFiles() {
            let source = stripLineComments(
                try read(contentsOf: url, describedAs: try relativePath(of: url)))
            titles.formUnion(captures(of: #"Toggle\s*\(\s*"([^"\\]+)""#, in: source))
        }
        guard !titles.isEmpty else { throw Failure.noToggleTitles }
        return titles
    }

    /// 用户在界面上**点得到**、且标题是字面量的控件：按钮加开关。
    ///
    /// **「下一步：点『X』」里的 X 不一定是按钮。** 麦克风权限那几句话指的就是
    /// `Toggle("保存我的回答录音")`——一颗开关。只拿按钮清单去查的话，
    /// 指对了开关反而会被报成「幽灵控件」，然后这条守卫会被人以「误报」为由删掉；
    /// 反过来，把开关排除在清单外，也就没人能证明那句话指对了东西。
    static func literalControlTitles() throws -> Set<String> {
        try literalButtonTitles().union(literalToggleTitles())
    }

    /// 一句面向用户的话里，指名让用户去点的那些东西：`点「X」`、`点一下「X」`。
    ///
    /// 铁律 4 要求每句话都说清「下一步做什么」，而「下一步」最常见的形态就是「点某颗按钮」。
    /// 指的按钮界面上不存在的话，这句话比不写还糟——用户会一直找。
    /// 本项目实测踩过：`ReviewParser`（Core，命令行也在用）那句
    /// 「下一步：点「补生成复盘报告」…」被界面原样转述，而全 App 没有这颗按钮。
    static func clickTargets(in message: String) -> [String] {
        captures(of: #"点(?:一下)?「([^」]+)」"#, in: message)
    }

    /// 同上，但用于扫源码：跳过带字符串插值的那些（`点「\(retry.buttonTitle)」`）。
    ///
    /// 插值的取值要跑起来才知道，扫源码判不了；那部分交给运行期的断言
    /// （`PracticeRunnerTests` 会真的把运行器跑进失败态，再拿 `clickTargets` 查一遍）。
    static func literalClickTargets(in code: String) -> [String] {
        clickTargets(in: code).filter { !$0.contains("\\(") }
    }

    // MARK: - 文案指的那个控件，真在它说的那一页上吗

    /// 一个「用户找得到的地方」：文案里可以让用户走过去的一页或一个窗口。
    struct UILocation: Equatable, CustomStringConvertible {
        /// 文案里可以怎么称呼它。设置窗口有两个叫法，所以是数组不是单值。
        let names: [String]
        /// 画它的那些源码在哪个目录（相对 `Sources/IELTSCoachUI`）。
        let directory: String
        /// 这一页上字面写死的按钮与开关标题。
        let controls: Set<String>

        var description: String {
            "\(names.joined(separator: " / "))（\(directory)/）：\(controls.sorted().joined(separator: "、"))"
        }
    }

    /// 从一句文案里认出来的一条「到 X 那一页去找 Y 这个控件」。
    struct Direction: Equatable, CustomStringConvertible {
        let location: String
        let control: String

        var description: String { "到「\(location)」找「\(control)」" }
    }

    /// 把源码里**用 `+` 连起来的相邻字符串字面量**拼成一段，按出现顺序返回。
    ///
    /// **为什么必须先拼**：本项目的文案基本都是折行写的——
    /// `"到「训练记录」页右上角" + "确认「记录对话逐字稿」是开着的。"`。
    /// 逐个字面量看的话，地点在前一段、控件在后一段，「这一对」永远配不上，
    /// 而配不上的后果不是报错，是这条守卫安静地永远绿。
    ///
    /// 边界：不认多行字符串（`"""`）与插值里再嵌字符串。界面模块里没有这两种写法。
    static func copySegments(in code: String) -> [String] {
        var segments: [String] = []
        var current: String?
        var index = code.startIndex
        while index < code.endIndex {
            guard code[index] == "\"", let literal = stringLiteral(startingAt: index, in: code) else {
                index = code.index(after: index)
                continue
            }
            current = (current ?? "") + literal.text
            // 后面跟着的如果是 `+` 再接一个字面量，就是同一段文案的下一截。
            if let next = continuationLiteralStart(after: literal.end, in: code) {
                index = next
                continue
            }
            segments.append(current ?? "")
            current = nil
            index = literal.end
        }
        if let tail = current { segments.append(tail) }
        return segments
    }

    /// 读一个从 `start` 开始的字符串字面量：返回引号之间的内容，以及收尾引号之后的位置。
    private static func stringLiteral(startingAt start: String.Index,
                                      in code: String) -> (text: String, end: String.Index)? {
        guard start < code.endIndex, code[start] == "\"" else { return nil }
        var text = ""
        var index = code.index(after: start)
        var escaped = false
        while index < code.endIndex {
            let character = code[index]
            if escaped {
                escaped = false
                text.append(character)
            } else if character == "\\" {
                escaped = true
                text.append(character)
            } else if character == "\"" {
                return (text, code.index(after: index))
            } else {
                text.append(character)
            }
            index = code.index(after: index)
        }
        return nil
    }

    /// `end` 之后如果只隔着空白和一个 `+` 就又是一个字面量，返回那个字面量的起点。
    private static func continuationLiteralStart(after end: String.Index,
                                                 in code: String) -> String.Index? {
        var index = end
        func skipWhitespace() {
            while index < code.endIndex, code[index].isWhitespace { index = code.index(after: index) }
        }
        skipWhitespace()
        guard index < code.endIndex, code[index] == "+" else { return nil }
        index = code.index(after: index)
        skipWhitespace()
        return index < code.endIndex && code[index] == "\"" ? index : nil
    }

    /// 从一段文案里认出「到 X 那一页去找 Y 这个控件」。
    ///
    /// 只认**同一小句里紧挨着的一对**：地点在前、控件在后，中间不许隔着分句标点，
    /// 也不许隔得太远。这两条限制不是为了省事，是为了不误报——真源码里有一句
    /// 「到「训练记录」页逐条删，或点下面的「打开录音文件夹」」，
    /// 后半句那颗按钮说的是当前这一页，跟前半句那一页无关。
    /// 误报几次，这条守卫就会被人整条删掉。
    ///
    /// 带插值的 `「\(x)」` 一律跳过：取值要跑起来才知道，扫源码判不了。
    static func directions(in segment: String,
                           locationNames: Set<String>,
                           controlTitles: Set<String>) -> [Direction] {
        let tokens = bracketTokens(in: segment)
        var found: [Direction] = []
        for (offset, token) in tokens.enumerated() where offset + 1 < tokens.count {
            let next = tokens[offset + 1]
            guard locationNames.contains(token.text), controlTitles.contains(next.text) else {
                continue
            }
            let gap = segment[token.end..<next.start]
            guard gap.count <= maximumDirectionGap,
                  !gap.contains(where: { clauseSeparators.contains($0) }) else { continue }
            found.append(Direction(location: token.text, control: next.text))
        }
        return found
    }

    /// 地点与控件之间最多能隔多少个字。「页右上角确认」是 6 个字，
    /// 放宽到 12 是留给别的说法（「里的」「那一页顶上」），再宽就开始把不相干的两截凑成一对了。
    private static let maximumDirectionGap = 12

    /// 分句标点。隔着其中任何一个，前后就不是同一句指路了。
    ///
    /// **ASCII 逗号不在里面**：`到「录音设置」（⌘,）点「打开录音文件夹」` 那句里的逗号
    /// 是快捷键 ⌘, 的一部分，算成分句的话，那一句就没人查了。
    private static let clauseSeparators: Set<Character> = ["。", "；", "！", "？", "，", "、", ";", "\n"]

    /// 一段文字里的 `「…」`，连同它在原文里的位置。带插值的跳过。
    private static func bracketTokens(
        in text: String) -> [(text: String, start: String.Index, end: String.Index)] {
        var tokens: [(String, String.Index, String.Index)] = []
        var cursor = text.startIndex
        while let open = text.range(of: "「", range: cursor..<text.endIndex),
              let close = text.range(of: "」", range: open.upperBound..<text.endIndex) {
            let inner = String(text[open.upperBound..<close.lowerBound])
            if !inner.contains("\\(") {
                tokens.append((inner, open.lowerBound, close.upperBound))
            }
            cursor = close.upperBound
        }
        return tokens.map { (text: $0.0, start: $0.1, end: $0.2) }
    }

    /// ⌘, 那个窗口在文案里的两种叫法。
    ///
    /// 它不在侧边栏里，名字也不来自本项目的源码——菜单项「设置」是 macOS 给的，
    /// 而 `RecordingPlayerView` 那句话里管它叫「录音设置」。所以这两个名字只能写在这儿。
    /// 写漏一个的后果是「指向那个窗口的文案没人查」，所以 `SourceGuardTests` 钉着它们。
    static let settingsWindowNames = ["设置", "录音设置"]

    /// 界面上有哪些「用户找得到的地方」，每个地方上有哪些按钮和开关。
    ///
    /// 三份来源全部从源码推，没有一份是手写清单：
    ///
    /// - **哪一页由谁画**：`RootView` 的 detail `switch current`；
    /// - **那一页叫什么**：`SidebarItem.title`；
    /// - **⌘, 那个窗口是谁**：App 层的 `Settings { … }` 场景。
    ///
    /// 推不出来一律抛错，绝不返回空清单——空清单会让「这个控件在不在那一页」恒真。
    static func uiLocations() throws -> [UILocation] {
        var entries: [(names: [String], type: String)] = []

        let titles = try sidebarTitles()
        for branch in try switchBranches(over: "current", in: try code("RootView.swift")) {
            guard let caseName = branch.cases.first, let title = titles[caseName],
                  let type = firstViewTypeName(in: branch.body) else { continue }
            entries.append((names: [title], type: type))
        }
        guard entries.count >= 4 else { throw Failure.noUILocations(found: entries.map(\.type)) }

        let appCode = try repositoryCode(appSceneRelativePath)
        guard let settingsBody = try? memberBody(of: "Settings", in: appCode),
              let settingsType = firstViewTypeName(in: settingsBody) else {
            throw Failure.settingsSceneNotFound
        }
        entries.append((names: settingsWindowNames, type: settingsType))

        let files = try swiftFiles()
        var located: [UILocation] = []
        for entry in entries {
            guard let file = try files.first(where: { url in
                let source = stripLineComments(
                    try read(contentsOf: url, describedAs: try relativePath(of: url)))
                return source.range(of: #"\bstruct\s+\#(entry.type)\b"#, options: .regularExpression)
                    != nil
            }) else {
                throw Failure.viewTypeNotFound(type: entry.type)
            }
            let directory = try relativePath(of: file).split(separator: "/").dropLast()
                .joined(separator: "/")
            located.append(UILocation(names: entry.names,
                                      directory: directory,
                                      controls: try literalControlTitles(under: directory)))
        }
        return located
    }

    /// 侧边栏每一项的 case 名 → 它在界面上的名字，从 `SidebarItem.title` 那个 `switch` 读。
    ///
    /// 「应该有几项」也从源码读（`enum SidebarItem` 声明的 case 数），不写死一个 10：
    /// 写死的话，将来加了第十一项、`title` 那个 `switch` 漏写一支，这里照样绿。
    static func sidebarTitles() throws -> [String: String] {
        let navigation = try code("Navigation.swift")
        let declared = try declaredCaseNames(inEnum: "SidebarItem", of: navigation)
        let body = try memberBody(of: "public var title", in: navigation)
        var titles: [String: String] = [:]
        for branch in try switchBranches(over: "self", in: body) {
            guard let literal = captures(of: #"return\s+"([^"\\]+)""#, in: branch.body).first else {
                continue
            }
            for name in branch.cases { titles[name] = literal }
        }
        guard titles.count == declared.count else {
            throw Failure.noSidebarTitles(found: titles.count, expected: declared.count)
        }
        return titles
    }

    /// 一段代码里第一个被构造出来的视图/场景类型名。
    private static func firstViewTypeName(in code: String) -> String? {
        captures(of: #"\b([A-Z][A-Za-z0-9_]*(?:View|Scene))\s*\("#, in: code).first
    }

    /// 某个目录下字面写死的按钮与开关标题。
    ///
    /// **这一个不抛「一个都没扫到」**：不是每一页上都有按钮，那是正常的。
    /// 「扫描写法整体失效」由模块级的 `literalButtonTitles()` / `literalToggleTitles()` 管。
    static func literalControlTitles(under relativeDirectory: String) throws -> Set<String> {
        var titles: Set<String> = []
        for url in try swiftFiles(under: relativeDirectory) {
            let source = stripLineComments(
                try read(contentsOf: url, describedAs: try relativePath(of: url)))
            titles.formUnion(captures(of: #"Button\s*\(\s*"([^"\\]+)""#, in: source))
            titles.formUnion(captures(of: #"Toggle\s*\(\s*"([^"\\]+)""#, in: source))
        }
        return titles
    }

    /// App 层那个场景文件。侧边栏之外的窗口（⌘, 设置）只在这里能查到是谁画的。
    static let appSceneRelativePath = "Sources/IELTSCoachApp/main.swift"

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
        // 这里读的是**原始源码**（不去注释）：豁免注释要靠它才读得到。
        // 去注释这一步在 `designTokenViolations(inRawSource:)` 里面做。
        do {
            let found = designTokenViolations(inRawSource: try read(relativePath))
            guard !found.isEmpty else { return }
            reporter("\(relativePath) 有 \(found.count) 处样式没走设计令牌（铁律 6）：\n"
                        + found.map { "  • " + $0.description }.joined(separator: "\n"),
                     file, line)
        } catch {
            reporter("\(error)", file, line)
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
