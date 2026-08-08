import IELTSCoachCore
import SwiftUI

/// 「重新导入待处理的复盘」的收件箱：列出 `pending-reviews/` 里还没入库的复盘原文，
/// 每一条都能**重新导入、查看原文、删除**。
///
/// 版式全部走 Task 7 的组件与令牌（`CoachCard` / `EmptyStateView`、
/// `Palette` / `Spacing` / `Radius` / `Typography`）。**这里不许出现字面颜色、字号、圆角。**
///
/// **为什么这一页必须存在**（跨阶段决策 2）：复盘自动取回失败时，原文确实落在
/// `pending-reviews/` 里没丢（硬标准第 7 条成立），但把它补进库的唯一途径原本是
/// 终端里跑 `coach reimport`——硬标准第 2 条「全程不需要打开终端」恰恰在最需要它成立的
/// 时候不成立。所以这一页的每一句提示都不许再把用户推回终端。
@MainActor
struct PendingReviewInboxView: View {
    /// 由 `ReviewReportView` 造好传进来（数据目录在 `AppState` 手上，这一页自己不解析目录）。
    let model: PendingReviewViewModel
    /// 关掉这张表。开合状态在 `ReviewReportView` 手上，与本项目其他弹层的做法一致。
    let onClose: () -> Void

    /// 正在看原文的是哪一条。**存 id 不存整条记录**：列表会随刷新重建，
    /// 存对象会在刷新之后指着一份旧的。
    @State private var openedRowID: String?
    /// 读回来的那份原文全文。
    @State private var openedRawText: String?
    /// 正在等用户确认删除的那一条。非 nil 时确认框开着。
    @State private var pendingDeletion: PendingReviewRow?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            // `notice` 是这一页与用户之间唯一的对话通道，非 nil 时必须完整显示。
            if let notice = model.notice { noticeCard(notice) }
            if model.isEmpty {
                emptyState
            } else {
                rowList
            }
        }
        .padding(Spacing.xl)
        .frame(minWidth: 720, minHeight: 520, alignment: .topLeading)
        .background(Palette.canvas)
        .confirmationDialog(pendingDeletion.map(deletionTitle) ?? "",
                            isPresented: isConfirmingDeletion,
                            titleVisibility: .visible,
                            presenting: pendingDeletion) { row in
            // 默认焦点不给这一颗：`.cancel` 那颗才是回车/ESC 落点。
            Button("删掉这份原文", role: .destructive) { destroy(row) }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: { row in
            Text("删掉之后这份复盘原文就没了，无法恢复——它是那一场练习唯一的复盘来源，"
                 + "本工具没有第二份备份。"
                 + "下一步：确实不需要了再删；只是暂时导不进去的话，留着它不占什么地方"
                 + "（\(row.entry.fileName)，\(row.sizeText)）。")
        }
    }

    // MARK: - 抬头

    /// 抬头要把「这一页是干什么的」说清楚：用户多半是顺着别处的错误提示找过来的。
    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("重新导入待处理的复盘")
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text("复盘自动取回失败时，原文会先存进数据目录的 pending-reviews 里，一个字都不会丢。"
                     + "在这一页可以把它补进档案、打开看原文，或者删掉。")
                    .font(Typography.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.md)
            // 「刷新」不是摆设：用户可能刚在访达里把某个 .imported 后缀去掉，
            // 也可能是列表读失败之后按提示重试（`refresh()` 那句话指的就是这一颗）。
            Button("刷新") { model.refresh() }
                .buttonStyle(.bordered)
            Button("关闭", action: onClose)
                .buttonStyle(.bordered)
        }
    }

    // MARK: - 每次操作之后那句话

    /// **不做成一闪而过的提示。** 这几句话有的很长（归档 0 条那句要指路去改文件名），
    /// 用一秒钟就消失的提示，用户根本来不及读，而里面写着他接下来唯一能做的事（铁律 4、7）。
    private func noticeCard(_ message: String) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    // 里面有文件名和目录名，用户要拿它去访达里找文件。
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("知道了") { model.clearNotice() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 列表

    private var rowList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(model.rows) { row in
                    rowCard(row)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 一行 = 一份待入库的复盘原文。三项缺一不可：什么时候落的盘、属于哪道题、有多大。
    ///
    /// 大小这一项不是凑数的：几十字节的那份多半是半截内容（当时就被截断了），
    /// 值不值得重试，看这个数最快。
    private func rowCard(_ row: PendingReviewRow) -> some View {
        CoachCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                    Text(row.timeText)
                        .font(Typography.cardTitle)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                    Text(row.sessionID)
                        .font(Typography.label)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                    Spacer(minLength: Spacing.sm)
                    // 等宽数字：从「998 字节」跳到「1.2 KB」时整行不该跟着抖。
                    Text(row.sizeText)
                        .font(Typography.label)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                }
                Text(row.questionText)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                actions(for: row)
                if openedRowID == row.id { rawTextPane }
            }
        }
    }

    /// 三个操作。**「重新导入」排第一且最醒目**——这一整页存在的理由就是它。
    private func actions(for row: PendingReviewRow) -> some View {
        HStack(spacing: Spacing.sm) {
            Button("重新导入") { model.reimport(row) }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
            Button("查看原文") { showRawText(of: row) }
                .buttonStyle(.bordered)
            Spacer(minLength: Spacing.sm)
            Button("删除", role: .destructive) { pendingDeletion = row }
                .buttonStyle(.bordered)
        }
    }

    /// 展开的那份原文。可滚动、可选中复制——本工具解析不了的复盘，用户唯一的出路
    /// 就是自己打开看一眼，再把它贴回 ChatGPT 让它按格式重新输出一次。
    @ViewBuilder private var rawTextPane: some View {
        if let openedRawText {
            ScrollView {
                Text(openedRawText)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 240)
            .padding(Spacing.sm)
            .background(Palette.canvas)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(Palette.cardBorder, lineWidth: BorderWidth.hairline))
        }
    }

    /// 读原文。**读不到时不展开一块空白面板**——那样用户会以为这份原文是空的；
    /// 真正的原因（文件被手工删了之类）由 `model.notice` 说清楚，上面那张卡片会显示它。
    private func showRawText(of row: PendingReviewRow) {
        guard let text = model.rawText(of: row) else {
            openedRowID = nil
            openedRawText = nil
            return
        }
        openedRowID = row.id
        openedRawText = text
    }

    // MARK: - 删除

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } })
    }

    /// 确认框的标题要说清是**哪一份**。一列长得差不多的记录里只问「确定删除吗」，用户不敢按。
    private func deletionTitle(_ row: PendingReviewRow) -> String {
        "删掉 \(row.timeText) 那份复盘原文（\(row.sessionID)）？"
    }

    private func destroy(_ row: PendingReviewRow) {
        pendingDeletion = nil
        if openedRowID == row.id {
            openedRowID = nil
            openedRawText = nil
        }
        model.delete(row)
    }

    // MARK: - 一份都没有

    /// 空状态给足三样：一句现状、一句下一步、一个能直接点的按钮（DESIGN-SYSTEM 第 4 节）。
    ///
    /// 计划里写的是「不需要按钮」，但 `EmptyStateView` 的三个参数都不是可选的——
    /// 那是刻意设计的（见它的注释：只写一句「暂无数据」这种写法要编不过去）。
    /// 这里给的是「刷新」，不是为了凑数：用户可能刚在访达里手工放了一份原文进去，
    /// 或者刚把某个 `.imported` 后缀去掉，点一下就能看见。
    private var emptyState: some View {
        EmptyStateView(
            message: "没有待处理的复盘。",
            hint: "复盘自动取回失败时，原文会先存到这里，然后就能在这一页把它补进库。"
                + "现在这里是空的，说明每一场练习的复盘都已经归档了。",
            actionTitle: "刷新",
            action: { model.refresh() })
    }
}

/// 预览一律注入临时目录，不碰用户真实的训练数据（见 `PreviewSafetyTests` 的说明）。
#Preview("一份待处理的复盘都没有") {
    let directory = DataDirectory(root: URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "ielts-coach-preview-pending"))
    return PendingReviewInboxView(
        model: PendingReviewViewModel(directory: directory,
                                      store: StateStore(directory: directory)),
        onClose: {})
}
