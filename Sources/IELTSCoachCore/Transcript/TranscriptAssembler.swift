import Foundation

/// 把一次次 AX 采样得到的碎片，拼接去重成一条条对话。
///
/// **为什么必须有这个东西**（spec 2.3.9 实测）：ChatGPT 的文本在 AX 树里是碎片化的，
/// 连复盘的定界标记都被拆成三段。逐字稿每 2~3 秒采样一次，而流式输出让同一条消息
/// 不断变长——一场练习下来，同一条考官提问会被读到十几个长度不同的版本。
///
/// **本类型只做字符串**：不碰 AX、不碰文件、不碰时钟（时间由调用方传进来）。
/// 采样在 `ChatGPTBridge`，拼接在这里，两边各自可测到底。
///
/// 五条规则，实现时不要自己发明第六条：
/// - R1 同一次采样里的两个片段绝不并进同一个槽位（游标只前进不回头）
/// - R2 跨采样时同一槽位只保留最长版本
/// - R3 说话人不同的片段永不合并；unknown 可升级，不可降级
/// - R4 匹配不上就新开槽位，插在这一次采样能确定的位置上（游标处；游标没动过时见 `insertionIndex`）
/// - R5 采样失败只记账、不抛错
public struct TranscriptAssembler: Sendable {
    private struct Slot {
        var speaker: TranscriptSpeaker
        var text: String
        var firstSeenAt: Date
        /// 练习开始那一刻就已经在屏幕上的内容（考官提示词那条消息、侧边栏会话名、
        /// 按钮说明……）。它们不属于本次对话，`turns` 里不出现，
        /// **但必须留在槽位序列里**——正是它们让对齐游标能走到
        /// 「真正的对话从这里开始」的位置。
        var isBaseline: Bool
    }

    /// 一次采样里归一化之后的一个片段。只在 `ingest` 这一趟里活着。
    private struct Piece {
        var speaker: TranscriptSpeaker
        var text: String
    }

    private var slots: [Slot] = []
    private var failures: [String] = []

    public init() {}

    // MARK: - 采集

    /// 记下练习开始那一刻界面上已经有的文本。**只在第一次 `ingest` 之前调用一次。**
    ///
    /// 不用「按内容过滤掉考官提示词里出现过的文字」，因为**今天要练的题干本身
    /// 就写在提示词里**，考官问出口时说的就是那句话——按内容过滤会把整场练习的
    /// 第一个问题一起滤掉，直接违反成品标准第 5 条。
    public mutating func seedBaseline(_ fragments: [TranscriptFragment]) {
        for fragment in fragments {
            let text = Self.normalize(fragment.text)
            guard !text.isEmpty else { continue }
            slots.append(Slot(speaker: fragment.speaker, text: text,
                              firstSeenAt: .distantPast, isBaseline: true))
        }
    }

    /// 并入一次采样的结果。`timestamp` 是这次采样发生的时刻，由调用方给出——
    /// 内部不读时钟，否则这段逻辑就没法测了。
    public mutating func ingest(_ fragments: [TranscriptFragment], at timestamp: Date) {
        // 先归一化、丢掉空白片段，`insertionIndex` 才有一份确定的「这一次还剩哪些片段」可看。
        let sample = fragments
            .map { Piece(speaker: $0.speaker, text: Self.normalize($0.text)) }
            .filter { !$0.text.isEmpty }

        // R1：游标只前进不回头。一次采样看到的是**某一瞬间**的界面，
        // 两个节点就是两条消息，哪怕它们的文本一个是另一个的前缀。
        var cursor = 0
        for (offset, piece) in sample.enumerated() {
            if let hit = matchIndex(speaker: piece.speaker, text: piece.text, from: cursor) {
                merge(at: hit, speaker: piece.speaker, text: piece.text, timestamp: timestamp)
                cursor = hit + 1
            } else {
                // R4：新开一个槽位，插在这一次采样能确定的位置上。
                let insertion = insertionIndex(cursor: cursor,
                                               remaining: sample[(offset + 1)...])
                slots.insert(Slot(speaker: piece.speaker, text: piece.text,
                                  firstSeenAt: timestamp, isBaseline: false), at: insertion)
                cursor = insertion + 1
            }
        }
    }

    /// R5：这一次没读到。**只记账，绝不抛错**——逐字稿是增强，不是必需，
    /// 采样失败不得中断练习（ROADMAP 3.2）。但也绝不静默：
    /// `completenessNote` 会在练完之后如实告诉用户。
    public mutating func noteSamplingFailure(_ message: String) {
        failures.append(message)
    }

    // MARK: - 结果

    public var turns: [PracticeSession.TranscriptTurn] {
        let formatter = ISO8601DateFormatter()
        return slots.filter { !$0.isBaseline }.map {
            PracticeSession.TranscriptTurn(role: $0.speaker.rawValue,
                                           text: $0.text,
                                           capturedAt: formatter.string(from: $0.firstSeenAt))
        }
    }

    public var samplingFailureCount: Int { failures.count }
    public var lastSamplingFailure: String? { failures.last }

    public var unknownSpeakerCount: Int {
        slots.filter { !$0.isBaseline && $0.speaker == .unknown }.count
    }

    /// 逐字稿完不完整。一切正常时是 nil；有问题时给一句中文，
    /// 同时说明「发生了什么」和「下一步做什么」。**非 nil 时界面必须显示它。**
    public var completenessNote: String? {
        var parts: [String] = []
        if let last = failures.last {
            parts.append("有 \(failures.count) 次没能读到 ChatGPT 的界面，"
                + "这几秒里说的话可能没记进来（最后一次的原因：\(last)）")
        }
        if unknownSpeakerCount > 0 {
            parts.append("有 \(unknownSpeakerCount) 段没能判断是考官说的还是你说的，"
                + "已按出现顺序原样保留")
        }
        guard !parts.isEmpty else { return nil }
        return "本次逐字稿可能不完整：" + parts.joined(separator: "；") + "。"
            + "练习本身和复盘都不受影响。"
            + "下一步：到「训练记录」里点开这一场，对照 ChatGPT 窗口看看缺了什么；"
            + "如果每次都这样，多半是这一版 ChatGPT 改了界面，请把这句提示告诉开发者。"
    }

    // MARK: - 私有

    /// R4：一个匹配不上的片段，新槽位该插在哪儿。
    ///
    /// **游标已经走过东西**（`cursor > 0`）：这一次采样里它前面那个片段刚刚定位好，
    /// 这条紧跟在它后面。「采样漏掉过中间那条、下一次又读到」就是这个情形，
    /// 它要回到它本来的位置，而不是被追加到末尾。
    ///
    /// **游标还停在 0**：这一次一条已有消息都还没对上。此时**绝不能直接插到 0**——
    /// 那是把消息插到整份逐字稿最前面。逐字稿的顺序就是这场练习的顺序，顺序乱了
    /// 用户回看时会看到考官的第三个问题排在第一个前面，而且没有任何报错。
    /// 而这不是边缘情况：ChatGPT 的对话区随内容变长而滚动，早先的消息滚出可视区后
    /// AX 树里就读不到了，**一次采样只读到最新一条是常态**。分两种：
    /// - 这一次后面还有片段对得上已有槽位 → 界面往回滚了，读到的是更早的内容；
    ///   已知的只有「这条排在那个槽位前面」，就插在它正前面。
    /// - 后面一个都对不上 → 读到的就是刚冒出来的最新内容。逐字稿是追加式的，
    ///   一场练习里后来的消息永远在后面，所以追加到末尾。
    private func insertionIndex(cursor: Int, remaining: ArraySlice<Piece>) -> Int {
        guard cursor == 0 else { return min(cursor, slots.count) }
        for later in remaining {
            if let anchor = matchIndex(speaker: later.speaker, text: later.text, from: 0) {
                return anchor
            }
        }
        return slots.count
    }

    /// 从 `cursor` 开始往后找第一个能合并的槽位。**不许从 0 开始找**（R1）。
    private func matchIndex(speaker: TranscriptSpeaker, text: String, from cursor: Int) -> Int? {
        guard cursor < slots.count else { return nil }
        for index in cursor..<slots.count
        where Self.canMerge(slots[index].speaker, slots[index].text, speaker, text) {
            return index
        }
        return nil
    }

    private mutating func merge(at index: Int, speaker: TranscriptSpeaker,
                                text: String, timestamp: Date) {
        // R2：只保留最长版本。两者必有一个是另一个的前缀（canMerge 保证），
        // 所以「更长」就等于「内容更全」。
        if text.count > slots[index].text.count { slots[index].text = text }
        // R3：unknown 可以被升级成已知说话人，反过来不行。
        if slots[index].speaker == .unknown && speaker != .unknown {
            slots[index].speaker = speaker
        }
        // 迟到的旧采样带着更早的时间戳，capturedAt 要跟着往前修正。
        if timestamp < slots[index].firstSeenAt { slots[index].firstSeenAt = timestamp }
    }

    static func canMerge(_ existingSpeaker: TranscriptSpeaker, _ existingText: String,
                         _ speaker: TranscriptSpeaker, _ text: String) -> Bool {
        let speakerOK = existingSpeaker == speaker
            || existingSpeaker == .unknown || speaker == .unknown
        guard speakerOK else { return false }
        return existingText.hasPrefix(text) || text.hasPrefix(existingText)
    }

    /// 去掉首尾空白，并把中间连续的空白（含换行）压成一个空格。
    /// AX 读回来的文本带各种换行与缩进，不归一化的话「同一句话」会被当成两句。
    static func normalize(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }
}
