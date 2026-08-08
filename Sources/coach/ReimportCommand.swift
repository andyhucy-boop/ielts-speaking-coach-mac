import Foundation
import IELTSCoachCore

/// 把 pending-reviews 目录里已经落盘、但当时没能成功归档的复盘文件重新入库。
///
/// 存在的原因（spec 2.3.8）：`ReviewRequestPrompt` 曾经只规定了顶层键名，没规定
/// 每条内部的字段名，导致 ChatGPT 的实际输出和 `ReviewArchiver` 读取的字段名对不上——
/// 复盘完整落盘，却归档 0 条，且不报错。`PracticeCommand` 已经在「先落盘再解析」，
/// 这条命令就是把这些当时被吞掉的复盘，在指令/归档逻辑修好之后原样补入库，
/// 不用逼用户重新练一遍。
enum ReimportCommand {
    /// 成功归档后给文件追加的后缀，而不是删除或原样保留。
    ///
    /// - 不删：用户可能想再打开看当时 ChatGPT 到底写了什么，pending-reviews 目录
    ///   本来就是给人回溯用的。
    /// - 不能原样保留（不打标记）：这里的 sessionID 取自文件名，同一个文件反复跑
    ///   `coach reimport` 会得到完全相同的 sessionID，不做标记的话每次运行都会把
    ///   全部历史复盘重新过一遍，输出里的「新增 N 条」也就再也读不懂了。
    ///   加后缀能保证同一份复盘只真正处理一次：扫描只认 `.txt`，
    ///   打上后缀的文件不会被扫到，但原文一字不改地留在磁盘上。
    ///
    ///   数字本身不靠这道标记兜底：`ReviewArchiver.mergeIssues` 按 sessionID 去重，
    ///   同一场归档多少次，`IssueRecord.occurrences` 都一样
    ///   （`ReviewArchiverTests.testArchivingTheSameSessionTwiceDoesNotInflateOccurrences`）。
    ///   两道防线各管各的，不能互相顶替——标记这一步自己就会失败（改名撞名）。
    private static let importedSuffix = ".imported"

    static func run() -> Int32 {
        let directory = DataDirectory.resolve()
        do {
            try directory.createIfNeeded()
        } catch {
            print("❌ \(error.localizedDescription)")
            return 1
        }

        let files: [URL]
        do {
            files = try FileManager.default
                .contentsOfDirectory(at: directory.pendingReviewsDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "txt" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            print("❌ 读不到待入库目录：\(directory.pendingReviewsDirectory.path)")
            print("   \(error.localizedDescription)")
            return 1
        }

        guard !files.isEmpty else {
            print("ℹ️  \(directory.pendingReviewsDirectory.path) 下没有待入库的复盘文件（.txt）。")
            return 0
        }

        let store = StateStore(directory: directory)
        var succeededFiles = 0
        var failedFiles = 0
        var totalIssuesAdded = 0
        var totalVocabularyAdded = 0
        var filesWithSkipped: [(name: String, skipped: [String])] = []

        for file in files {
            let name = file.lastPathComponent
            print("\n▶︎ \(name)")

            let raw: String
            do {
                raw = try String(contentsOf: file, encoding: .utf8)
            } catch {
                print("  ❌ 读不到文件：\(error.localizedDescription)")
                failedFiles += 1
                continue
            }

            let report: JSONValue
            do {
                report = try ReviewParser.parse(raw, requireAnswerUpgrades: false)
            } catch {
                print("  ❌ 解析失败：\(error.localizedDescription)")
                print("     下一步：打开这个文件确认内容是否完整；若确实不是标准格式，"
                    + "本命令不会动它，可以手动处理后再跑一次 coach reimport。")
                failedFiles += 1
                continue
            }

            // 去掉扩展名当 sessionID。文件名是 `PendingReviewStore.write` 起的，
            // 正常情况下就是那一场的会话编号（形如 2026-08-06-001.txt）——所以同一次练习
            // 不管是当场归档还是事后 reimport，落进档案的 sessionID 都是同一个值。
            //
            // 两种对不上的情况，都只影响「归档用的编号能不能对上训练记录里的某一场」，
            // 不影响错题与词汇本身能不能补进档案：
            // - 同一场落了第二份原文时，`PendingReviewStore.write` 会命名成 `<编号>-2.txt`，
            //   这里会把 `<编号>-2` 整个当成 sessionID（界面那条路会先把 `-2` 去掉再归档，
            //   见 `PendingReviewRow.linkedSessionID`）。
            // - Phase 4 之前落盘的老文件叫 sync-1785940167.txt 那样，那是当时的请求时间戳，
            //   压根不是任何一场练习的会话编号。
            let sessionID = file.deletingPathExtension().lastPathComponent

            // questionID 无从得知：pending-reviews 目录里的文件名不含题目 id，
            // 复盘 JSON 本身也不保证带这项信息。这里传空字符串——
            // ReviewArchiver.advancePlan / markPracticed 找不到 id 为空字符串的题目
            // （firstIndex(where: { $0.id == "" })，题库里不会有空 id 的题），
            // 会自然地无操作，不会误伤任何真实题目的进度或状态，是可接受的降级。
            // 错题、词汇、重训目标这三项归档跟 questionID 无关，不受影响。
            let questionID = ""
            let timestamp = ISO8601DateFormatter().string(from: Date())

            let issuesAdded: Int
            let vocabularyAdded: Int
            let skipped: [String]
            do {
                (issuesAdded, vocabularyAdded, skipped) = try store.mutate { state -> (Int, Int, [String]) in
                    let issuesBefore = state.issues.count
                    let vocabularyBefore = state.vocabulary.count
                    let outcome = ReviewArchiver.archive(report: report, into: state,
                                                         sessionID: sessionID, questionID: questionID,
                                                         at: timestamp)
                    state = outcome.state
                    // 用归档前后的记录数之差报告「新增了几条」，而不是「处理了几条」——
                    // 命中已有记录（同一句话第二次出现）会让 occurrences 增加但不新增
                    // 记录，这里如实只统计新增的记录数，不夸大战果。
                    return (state.issues.count - issuesBefore,
                           state.vocabulary.count - vocabularyBefore,
                           outcome.skipped)
                }
            } catch {
                print("  ❌ 归档失败：\(error.localizedDescription)")
                failedFiles += 1
                continue
            }

            succeededFiles += 1
            totalIssuesAdded += issuesAdded
            totalVocabularyAdded += vocabularyAdded
            print("  ✅ 归入错题 \(issuesAdded) 条，词汇 \(vocabularyAdded) 条")
            if !skipped.isEmpty {
                filesWithSkipped.append((name: name, skipped: skipped))
                print("  ⚠️  \(skipped.joined(separator: "、")) 存在但一条都没能归进档案，字段名可能仍不对。")
            }

            let markedURL = file.deletingLastPathComponent()
                .appendingPathComponent(name + importedSuffix)
            do {
                try FileManager.default.moveItem(at: file, to: markedURL)
                print("  ▶︎ 已标记为入库：重命名为 \(markedURL.lastPathComponent)（原文未删除，仍可打开查看）")
            } catch {
                print("  ⚠️  已成功归档，但重命名标记失败，下次运行可能会重复处理这个文件："
                    + "\(error.localizedDescription)")
            }
        }

        print("\n———")
        print("共处理 \(files.count) 个文件：\(succeededFiles) 个成功入库，\(failedFiles) 个失败。")
        print("累计新增错题 \(totalIssuesAdded) 条，词汇 \(totalVocabularyAdded) 条。")
        if !filesWithSkipped.isEmpty {
            print("以下文件有顶层键存在但一条都没归进去，字段名可能仍对不上：")
            for entry in filesWithSkipped {
                print("  - \(entry.name)：\(entry.skipped.joined(separator: "、"))")
            }
        }
        return failedFiles == 0 ? 0 : 1
    }
}
