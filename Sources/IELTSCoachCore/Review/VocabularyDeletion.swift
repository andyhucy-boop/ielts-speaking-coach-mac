import Foundation

/// 删掉词汇本里的一条词。
///
/// ## 为什么必须有这个入口
///
/// 复盘偶尔会给出只有原词、既没有「更好的说法」也没有搭配的条目。那条记录在
/// 「我的词汇」页上渲染成「word →（空白）」，导出时每次都被跳过，而跳过的提示里
/// 写着两条下一步：「等下一次复盘补上，或到「我的词汇」页把这条删掉」。
/// 第二条从前是假的——**全应用（含命令行与 MCP）都没有删除单条词汇的能力**，
/// 用户站在那一页上翻遍整页也找不到入口，唯一的出路是手动去改 state.json
///（2026-08-08 复审第 11 条实测）。第一条也曾经是假的，已由
/// `ReviewArchiver.mergeVocabulary` 的回填补上。
///
/// ## 为什么是 Core 里的纯函数
///
/// 「删哪一条、删完之后剩什么、要跟用户说什么」这几件事必须能被单元测试问出来。
/// 放在视图里的话，扫源码只问得出「这儿有个删除按钮」，问不出它到底删了什么——
/// 而删错一条是不可撤销的。
public enum VocabularyDeletion {

    /// 删除前给用户看的那段确认文案。
    ///
    /// **必须逐条说清删掉什么、什么不会跟着删。** 词汇本上的一条词挂着
    /// 「出现在 N 场练习里」，用户完全可能以为删掉它会连带动到那几场练习。
    public static func confirmationText(for record: VocabularyRecord) -> String {
        let sessions = Set(record.sourceSessionIds).count
        let word = record.basicWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = word.isEmpty ? "这条没有原词的记录" : "「\(word)」"
        return "删掉之后，\(name)会从「我的词汇」页消失，导出的 Anki 卡片里也不会再有它。"
            + "它出现过的那 \(sessions) 场练习、复盘报告、错题本都不受影响，一个字都不会动。"
            + "下次复盘要是又推荐了这个词，它会作为一条新记录重新出现。"
            + "下一步：想留着就点「取消」；确认之后立刻生效，不进废纸篓，也没有撤销。"
    }

    /// 从词汇本里删掉 id 为 `id` 的那一条。
    ///
    /// **按 id 删，而且只删这一条。** 按 `basicWord` 删的话，
    /// 被外部工具写坏、出现两条同词记录时会一次删掉两条，而用户只点了一条。
    ///
    /// - Returns: 真的删掉了返回 true；那条记录已经不在了返回 false
    ///   （调用方必须把这件事说出来，不能装作删成功了）。
    @discardableResult
    public static func remove(id: String, from state: inout CoachState) -> Bool {
        let before = state.vocabulary.count
        state.vocabulary.removeAll { $0.id == id }
        return state.vocabulary.count != before
    }

    /// 删完之后那句反馈。**成功也要说话**：一行悄悄消失，用户分不清
    /// 「删掉了」和「点了没反应」。
    public static func successNotice(for record: VocabularyRecord, remaining: Int) -> String {
        let word = record.basicWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = word.isEmpty ? "那条没有原词的记录" : "「\(word)」"
        return "已经把 \(name) 从词汇本里删掉了，现在还剩 \(remaining) 个词。"
            + "这条词出现过的练习记录、复盘报告和错题本都没有动。"
            + "下一步：想把剩下的词做成 Anki 卡片，用上面的「导出…」或「复制到剪贴板」。"
    }

    /// 那条记录已经不在了（多半是另一个窗口或命令行同期改过数据）。
    /// **不许装作删成功了**——那会让用户以为界面在骗他。
    public static func alreadyGoneNotice(remaining: Int) -> String {
        "没有删除：这条词在词汇本里已经找不到了，多半是另一个窗口或者命令行刚刚改过训练数据。"
            + "词汇本现在有 \(remaining) 个词，屏幕上这一份可能是旧的。"
            + "下一步：切到别的页面再切回来（会重新读一次数据），确认它是不是已经不在了。"
    }
}
