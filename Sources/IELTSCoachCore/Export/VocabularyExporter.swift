import Foundation

/// 一份导出结果。`skipped` 必须被界面显示出来——
/// 静默少导出几条，用户在 Anki 里根本不会发现。
public struct ExportDocument: Equatable, Sendable {
    public let text: String
    public let suggestedFileName: String
    public let exportedCount: Int
    /// 每条都是一句中文说明，含「发生了什么 + 下一步做什么」。
    public let skipped: [String]

    public init(text: String, suggestedFileName: String, exportedCount: Int, skipped: [String]) {
        self.text = text; self.suggestedFileName = suggestedFileName
        self.exportedCount = exportedCount; self.skipped = skipped
    }
}

public enum VocabularyExportFormat: String, CaseIterable, Identifiable, Sendable {
    /// 制表符分隔的 Anki 导入文件。
    case ankiTSV
    /// 可以原样 POST 给 AnkiConnect 的 addNotes 请求体。
    case ankiConnectJSON

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ankiTSV: return "Anki 导入文件（.txt）"
        case .ankiConnectJSON: return "AnkiConnect 请求（.json）"
        }
    }

    public var fileExtension: String {
        switch self {
        case .ankiTSV: return "txt"
        case .ankiConnectJSON: return "json"
        }
    }

    /// 界面必须把这段话显示在导出入口旁边。导出一个文件却不说怎么用，
    /// 等于没做这个功能。
    public var howToUse: String {
        switch self {
        case .ankiTSV:
            return "在 Anki 里选「文件 › 导入」，选中这个文件即可。"
                + "牌组、笔记类型、分隔符、标签列都已经写在文件开头，正常情况下不用改导入对话框里的任何设置。"
                + "下一步：如果你的 Anki 版本较老、导入对话框没有自动带出这些设置，"
                + "在对话框里手动把分隔符选成「制表符」，并把第 3 列指定为标签列。"
        case .ankiConnectJSON:
            return "这是一份可以直接发给 AnkiConnect 的 addNotes 请求。"
                + "下一步：确认 Anki 正在运行且已安装 AnkiConnect 插件，然后执行"
                + " curl -s localhost:8765 -d @<这个文件的路径>。"
        }
    }
}

public enum VocabularyExporter {
    public static let defaultDeckName = "IELTS Speaking Coach"
    public static let defaultNoteType = "Basic"
    public static let baseTag = "ielts-speaking"

    public static func export(_ records: [VocabularyRecord],
                              format: VocabularyExportFormat,
                              deckName: String = defaultDeckName,
                              noteType: String = defaultNoteType,
                              exportedAt: Date = Date(),
                              calendar: Calendar = .current) -> ExportDocument {
        let built = notes(from: records)
        var skipped = built.skipped
        if records.isEmpty {
            skipped.append("词汇本还是空的，导出的文件里没有任何卡片。"
                + "下一步：先练一场并让 ChatGPT 生成复盘，推荐词汇会自动进词汇本。")
        }

        let fileName = "ielts-vocabulary-"
            + CoachTime.dayString(exportedAt, calendar: calendar)
            + ".\(format.fileExtension)"

        let text: String
        switch format {
        case .ankiTSV:
            text = tsvText(built.notes, deckName: deckName, noteType: noteType)
        case .ankiConnectJSON:
            let outcome = jsonText(built.notes, deckName: deckName, noteType: noteType)
            text = outcome.text
            if let failure = outcome.failure { skipped.append(failure) }
        }

        return ExportDocument(text: text, suggestedFileName: fileName,
                              exportedCount: built.notes.count, skipped: skipped)
    }

    // MARK: - 从记录到卡片

    private struct Note {
        let front: String
        let back: String
        let tags: [String]
    }

    private static func notes(from records: [VocabularyRecord]) -> (notes: [Note], skipped: [String]) {
        var notes: [Note] = []
        var skipped: [String] = []

        for record in records {
            let front = sanitize(record.basicWord)
            // ⚠️ 下面两句「下一步」提到的两条路**都必须真的做得到**，这不是修辞。
            // 2026-08-08 复审第 11 条实测：那时两条都是死路——全应用（含命令行与 MCP）
            // 没有删除单条词汇的能力，而 `ReviewArchiver.mergeVocabulary` 按 basicWord
            // 命中已有记录之后只加一次出现次数，缺掉的字段一个都不回填。
            // 现在两条都补上了：删除入口是「我的词汇」页每条词右边的「删掉这个词」，
            // 回填在 `mergeVocabulary` 里（只填空字段，不覆盖已有内容）。
            // 哪天要动这两处任意一处，这两句话得跟着改。
            guard !front.isEmpty else {
                skipped.append("跳过了一条词汇：它没有「原来的说法」，而 Anki 会拒收正面为空的卡片。"
                    + "下一步：到「我的词汇」页点这条右边的「删掉这个词」，"
                    + "或等下一次复盘再推荐到这个词时自动把它补全。")
                continue
            }
            let parts = [sanitize(record.betterExpression), sanitize(record.collocation)]
                .filter { !$0.isEmpty }
            guard !parts.isEmpty else {
                skipped.append("跳过了「\(front)」：它既没有更好的说法，也没有搭配，做成卡片背面是空的。"
                    + "下一步：等下一次复盘再推荐到这个词，缺的部分会自动补上；"
                    + "不想等就到「我的词汇」页点它右边的「删掉这个词」。")
                continue
            }
            notes.append(Note(front: front,
                              back: parts.joined(separator: "<br>"),
                              tags: [baseTag, VocabularyPriority.normalize(record.priority).ankiTag]))
        }
        return (notes, skipped)
    }

    /// 让一段文本可以安全地放进 TSV 的一格里。
    ///
    /// **用清洗而不是加引号**：加引号要处理转义、还要赌 Anki 版本认不认；
    /// 清洗是确定性的、可测的。替换顺序不能变——先处理 \r\n，
    /// 否则会被拆成两个 <br>。
    ///
    /// **修剪必须在替换之前，而且要按 .whitespacesAndNewlines。**
    /// 反过来（先替换、末尾再按 .whitespaces 修剪）会让一个纯换行的字段
    /// 变成 "<br>"：判空时它已经不是空的了，于是下面两处 `guard !...isEmpty`
    /// 都判不出来，一张正面（或背面）在 Anki 里完全空白的卡会被静默导出去，
    /// skipped 里还一个字都没有。
    private static func sanitize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    // MARK: - TSV

    private static func tsvText(_ notes: [Note], deckName: String, noteType: String) -> String {
        // 这五行是 Anki 2.1.55 起支持的导入指令。带上它们，用户导入时
        // 不需要在对话框里点任何东西。#html:true 是必须的——
        // 清洗时把换行换成了 <br>。
        var lines = [
            "#separator:tab",
            "#html:true",
            "#notetype:\(sanitize(noteType))",
            "#deck:\(sanitize(deckName))",
            "#tags column:3"
        ]
        for note in notes {
            lines.append([note.front, note.back, note.tags.joined(separator: " ")]
                .joined(separator: "\t"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - AnkiConnect

    private struct AnkiConnectRequest: Encodable {
        let action: String
        let version: Int
        let params: Params

        struct Params: Encodable { let notes: [Note] }

        struct Note: Encodable {
            let deckName: String
            let modelName: String
            let fields: [String: String]
            let tags: [String]
            let options: Options

            struct Options: Encodable {
                let allowDuplicate: Bool
                let duplicateScope: String
            }
        }
    }

    private static func jsonText(_ notes: [Note], deckName: String,
                                 noteType: String) -> (text: String, failure: String?) {
        let request = AnkiConnectRequest(
            action: "addNotes", version: 6,
            params: .init(notes: notes.map { note in
                .init(deckName: deckName, modelName: noteType,
                      fields: ["Front": note.front, "Back": note.back],
                      tags: note.tags,
                      // allowDuplicate: false —— 同一个词多次复盘都会被推荐，
                      // 重复导入不该在牌组里堆出十张一样的卡。
                      options: .init(allowDuplicate: false, duplicateScope: "deck"))
            }))

        let encoder = JSONEncoder()
        // sortedKeys 让输出稳定：同一份词汇本导两次得到同样的文件，
        // 用户 diff 得出来，测试也断言得了。
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        guard let data = try? encoder.encode(request),
              let text = String(data: data, encoding: .utf8) else {
            return ("", "生成 AnkiConnect 请求失败，这个文件不能用。"
                + "下一步：改用「Anki 导入文件（.txt）」格式导出，它不经过 JSON 编码。")
        }
        return (text, nil)
    }
}
