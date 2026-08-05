import SwiftUI

/// **临时实现，Task 4 会整页替换。**
/// 计划：`docs/superpowers/plans/2026-08-05-phase3-gui-shell.md` 的「Task 4: 训练题库页」。
/// 说明同 `TodayView`。
struct QuestionBankView: View {
    let app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(SidebarItem.questionBank.title).font(.largeTitle).bold()
            Text("这一页还在建设中：导入题库、按 Part 筛选、按话题分组都会出现在这里。")
                .font(.body)
            Text("下一步：导入功能做好之前，这一页不会动到你已有的题目；"
                 + "当前题库里共有 \(app.state.questions.count) 道题。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: 640, alignment: .leading)
    }
}
