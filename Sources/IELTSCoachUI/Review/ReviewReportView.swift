import SwiftUI

/// **临时实现，Task 5 会整页替换。**
/// 计划：`docs/superpowers/plans/2026-08-05-phase3-gui-shell.md` 的「Task 5: 复盘报告页」。
/// 说明同 `TodayView`。
struct ReviewReportView: View {
    let app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(SidebarItem.reviewReports.title).font(.largeTitle).bold()
            Text("这一页还在建设中：历次练习的复盘、必须纠正的表达、词汇升级和下一个目标"
                 + "都会出现在这里。")
                .font(.body)
            Text("下一步：这一页做好之前，复盘原文一直存在数据目录的 reports 里，"
                 + "不会因为界面没做完而丢失；已归档的练习共 \(app.state.sessions.count) 次。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: 640, alignment: .leading)
    }
}
