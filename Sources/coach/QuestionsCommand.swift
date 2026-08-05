import Foundation
import IELTSCoachCore

enum QuestionsCommand {
    static func run(_ args: [String]) -> Int32 {
        guard let sub = args.first else {
            print("用法：coach questions import <文件>  或  coach questions list [1|2|3]")
            return 2
        }
        switch sub {
        case "import": return importBank(path: args.count > 1 ? args[1] : nil)
        case "list":
            if args.count > 1 {
                // 不能用 Int(args[1]) 直接转 —— 输入 "1a" 时它返回 nil，
                // 会静默退化成「列出全部」，用户以为自己在看 Part 1 的题。
                guard let part = Int(args[1]), (1...3).contains(part) else {
                    print("❌ 「\(args[1])」不是有效的 Part。")
                    print("   下一步：用 coach questions list 1（或 2、3）；不带参数则列出全部。")
                    return 2
                }
                return list(partFilter: part)
            }
            return list(partFilter: nil)
        default:
            print("未知子命令：\(sub)。可用：import、list")
            return 2
        }
    }

    private static func importBank(path: String?) -> Int32 {
        guard let path else {
            print("❌ 没有指定题库文件。下一步：coach questions import ~/Downloads/题库.csv")
            return 2
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            print("❌ 「\(url.path)」是个文件夹，不是题库文件。")
            print("   下一步：指定文件夹里那个具体的 .csv 或 .json 文件。")
            return 2
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            print("❌ 读不到文件：\(url.path)")
            print("   下一步：确认路径正确、文件是 UTF-8 编码的文本，然后重试。")
            return 1
        }
        let title = url.deletingPathExtension().lastPathComponent
        do {
            let result = url.pathExtension.lowercased() == "json"
                ? try QuestionBankImporter.importJSON(text, sourceTitle: title)
                : try QuestionBankImporter.importCSV(text, sourceTitle: title)

            result.warnings.forEach { print("⚠️  \($0)") }

            let directory = DataDirectory.resolve()
            try directory.createIfNeeded()
            let total = try StateStore(directory: directory).mutate { state -> Int in
                state.questions = QuestionBankImporter.merge(existing: state.questions,
                                                             incoming: result.questions)
                state.questionSources.append(result.source)
                return state.questions.count
            }
            print("✅ 导入 \(result.questions.count) 题，题库现共 \(total) 题")
            if result.questions.isEmpty {
                print("ℹ️  这次没有导入任何题目。下一步：检查上面的警告。")
            }
            return 0
        } catch {
            print("❌ \(error.localizedDescription)")
            return 1
        }
    }

    private static func list(partFilter: Int?) -> Int32 {
        do {
            let state = try StateStore(directory: DataDirectory.resolve()).load()
            let questions = partFilter == nil ? state.questions
                                              : state.questions.filter { $0.part == partFilter }
            guard !questions.isEmpty else {
                print("题库里没有符合条件的题目。下一步：coach questions import <你的题库文件>")
                return 0
            }
            for question in questions {
                let mark = question.status == "practiced" ? "✓" : " "
                print("\(mark) [\(question.id)] Part \(question.part) · \(question.topic)")
                print("    \(question.prompt)")
            }
            print("\n共 \(questions.count) 题")
            return 0
        } catch {
            print("❌ \(error.localizedDescription)")
            return 1
        }
    }
}
