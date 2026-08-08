import Foundation
import IELTSCoachCore
import PDFKit

enum QuestionsCommand {
    static func run(_ args: [String]) -> Int32 {
        guard let sub = args.first else {
            print("用法：coach questions import <文件>")
            print("      coach questions list [1|2|3]")
            print("      coach questions remodel [--apply]")
            return 2
        }
        switch sub {
        case "import": return importBank(path: args.count > 1 ? args[1] : nil)
        case "remodel": return remodel(apply: args.dropFirst().contains("--apply"))
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
            print("未知子命令：\(sub)。可用：import、list、remodel")
            return 2
        }
    }

    /// 把一份 PDF 抽成纯文本。**规则不在这里**——认格式、读文件、分派解析全在
    /// `QuestionBankFile` 里，界面走的也是同一条。这里只补 Core 依赖不了的那一件事：
    /// PDFKit（铁律 7：`IELTSCoachCore` 只许依赖 Foundation）。
    private static func pdfPlainText(at url: URL) -> String? { PDFDocument(url: url)?.string }

    private static func importBank(path: String?) -> Int32 {
        guard let path else {
            print("❌ 没有指定题库文件。下一步：coach questions import ~/Downloads/题库.pdf")
            print("   支持这 \(QuestionBankFile.supportedExtensions.count) 种："
                + "\(QuestionBankFile.supportedExtensionList)。")
            return 2
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            print("❌ 「\(url.path)」是个文件夹，不是题库文件。")
            print("   下一步：指定文件夹里那个具体的 "
                + "\(QuestionBankFile.supportedExtensionList) 文件。")
            return 2
        }

        do {
            // **和界面走的是同一个函数。** 从前这里是「不是 .json 就当 CSV」，
            // 于是 `coach questions import 讲义.docx` 会被当成 CSV 解析，
            // 抛出一句「题库表头缺少必需列「id」」——用户手上那份根本不是 CSV，
            // 这句话把他指向一个不存在的问题。Task 8 加 PDF 时也正是因为这里
            // 各写各的，命令行整整落后了一个格式。
            let result = try QuestionBankFile.importFile(at: url, pdfText: pdfPlainText)
            let title = QuestionBankFile.sourceTitle(ofFileName: url.lastPathComponent)

            result.warnings.forEach { print("⚠️  \($0)") }

            let directory = DataDirectory.resolve()
            try directory.createIfNeeded()
            let outcome = try StateStore(directory: directory)
                .mutate { state -> (total: Int, plan: String?, absorbed: Int, remapped: Int) in
                    // 「导入之前有没有题」在写事务里取，理由见 AppState.applyImport。
                    let hadQuestionsBefore = !state.questions.isEmpty
                    let mergeResult = QuestionBankImporter.merge(existing: state.questions,
                                                                 incoming: result.questions)
                    state.questions = mergeResult.questions
                    // 与 App 走同一条路：旧结构的题被话题题吸收掉时，挂在它们身上的
                    // 练习记录、复训链接与学习计划必须在同一个写事务里搬到新题号上。
                    let remapped = QuestionBankMigration.remapQuestionIDs(
                        in: &state, replacements: mergeResult.replacements)
                    state.questionSources.append(result.source)

                    // 与 App 走同一条规则（PlanBootstrap），不各写各的：
                    // 两边行为不一致的话，用命令行导题库的人回到 App 会发现首页
                    // 没有「按计划练今天」，而引导刚刚亲口说过已经排好了（复审第 9 条）。
                    var planNotice: String?
                    if let bootstrapped = PlanBootstrap.planForFirstImport(
                        state: state, hadQuestionsBefore: hadQuestionsBefore,
                        createdAt: CoachTime.string(from: Date())) {
                        PlanRegenerator.apply(bootstrapped, to: &state)
                        planNotice = PlanBootstrap.notice(for: bootstrapped)
                    }
                    return (state.questions.count, planNotice,
                            mergeResult.replacements.count, remapped)
                }
            print("✅ 从「\(title)」导入 \(result.questions.count) 题，题库现共 \(outcome.total) 题")
            if outcome.absorbed > 0 {
                // 不说的话，用户看到题库从一千多道变成两百多道只会以为导坏了（铁律 7）。
                print("♻️  顺带把 \(outcome.absorbed) 道旧结构（一问一题）的题并进了它们所属的话题，"
                    + "问句一句没丢，成了那道题下面的参考问句；"
                    + "同时改写了 \(outcome.remapped) 处旧题号引用，历史记录没有变成孤儿。")
            }
            if let plan = outcome.plan { print("📅 \(plan)") }
            if result.questions.isEmpty {
                print("ℹ️  这次没有导入任何题目。下一步：检查上面的警告。")
            }
            return 0
        } catch {
            // 失败翻译也和界面共用一份：系统 NSError 只说发生了什么、不说下一步。
            print("❌ \(QuestionBankFile.describeFailure(error, fileName: url.lastPathComponent))")
            return 1
        }
    }

    // MARK: - 原地重建模

    /// 把已经在这台机器上的旧结构题库改成「一个话题一道题」，并把历史记录一起搬过去。
    ///
    /// **默认只干跑（dry run）。** 这条命令要动的是用户唯一一份训练数据，
    /// 「跑一下看看」和「真的改」必须是两个动作——手滑敲错一个子命令就把题库重排了，
    /// 是这类工具最不能有的行为。真要改，显式加 `--apply`。
    ///
    /// **加了 `--apply` 也会先整份备份**（`DataBackup.copy`），并把备份路径打出来。
    /// 备份没做成就不会往下走一步。
    private static func remodel(apply: Bool) -> Int32 {
        let directory = DataDirectory.resolve()
        let store = StateStore(directory: directory)

        let state: CoachState
        do {
            state = try store.load()
        } catch {
            print("❌ \(error.localizedDescription)")
            return 1
        }

        // 先干跑一遍：拿一份内存里的副本算出结果，什么都不写。
        var preview = state
        let previewOutcome = QuestionBankRemodel.apply(to: &preview)

        print("数据目录：\(directory.root.path)")
        print("——— 干跑结果（还没有写盘）———")
        print(QuestionBankRemodel.report(previewOutcome))

        if !previewOutcome.lostPrompts.isEmpty {
            print("❌ 这次迁移会让 \(previewOutcome.lostPrompts.count) 句题干从题库里彻底消失，"
                + "所以**不会**写盘。")
            for prompt in previewOutcome.lostPrompts.prefix(10) { print("   · \(prompt)") }
            print("   下一步：把这条输出发给开发者；在修好之前不要加 --apply。")
            return 1
        }
        if !previewOutcome.newOrphans.isEmpty {
            print("❌ 这次迁移会让 \(previewOutcome.newOrphans.count) 处历史记录指向不存在的题，"
                + "所以**不会**写盘：\(previewOutcome.newOrphans.joined(separator: "、"))")
            print("   下一步：把这条输出发给开发者；在修好之前不要加 --apply。")
            return 1
        }

        guard apply else {
            if previewOutcome.changedAnything {
                print("ℹ️  以上只是预演，磁盘上的数据一个字节都没改。")
                print("   下一步：确认没问题之后运行 coach questions remodel --apply，"
                    + "它会先把整个数据目录备份一份再改。")
            }
            return 0
        }

        // 真改之前先备份。备份放在数据目录**旁边**（同一个父目录），
        // 不去猜「桌面在哪儿」——数据目录可以被 IELTS_SPEAKING_DATA_DIR 改到任何地方。
        let backup: URL
        do {
            backup = try DataBackup.copy(directory,
                                         into: directory.root.deletingLastPathComponent())
        } catch {
            print("❌ \(error.localizedDescription)")
            return 1
        }
        print("💾 已备份整个数据目录到：\(backup.path)")

        do {
            let outcome = try store.mutate { QuestionBankRemodel.apply(to: &$0) }
            print("——— 已经写盘 ———")
            print(QuestionBankRemodel.report(outcome))
            print("ℹ️  想撤销的话：退出 App，把 \(backup.path) 整个复制回 "
                + "\(directory.root.path)（覆盖即可）。")
            return 0
        } catch {
            print("❌ 写盘失败：\(error.localizedDescription)")
            print("   下一步：数据仍是改动前的样子，备份也在 \(backup.path)。"
                + "确认磁盘可写、App 没有同时在运行，然后重跑。")
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
                if !question.followups.isEmpty {
                    // 话题题的题干就是话题名，参考问句全在 followups 里。
                    // 不列出来的话，`coach questions list 1` 看到的是一串光秃秃的话题名，
                    // 用户会以为重建模把问句弄丢了。
                    print("    参考问句 \(question.followups.count) 条（考官挑着问，不会全问）：")
                    for followup in question.followups { print("      - \(followup)") }
                }
            }
            print("\n共 \(questions.count) 题")
            return 0
        } catch {
            print("❌ \(error.localizedDescription)")
            return 1
        }
    }
}
