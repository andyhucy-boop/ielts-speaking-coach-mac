import SwiftUI

/// **临时实现，Task 6 会整页替换。**
/// 计划：`docs/superpowers/plans/2026-08-05-phase3-gui-shell.md` 的「Task 6: 今日训练页」。
/// Task 3 只要求让工程编得过、并让侧边栏点得进来，所以这里先按占位页的标准写：
/// 说清这一页是什么状态、将来会有什么、现在该往哪走。
struct TodayView: View {
    let app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(SidebarItem.today.title).font(.largeTitle).bold()
            Text("这一页还在建设中：今天练什么、四条练习路线、本周进度和最近几次练习都会出现在这里。")
                .font(.body)
            Text("下一步：练习入口做好之前，可以先到「训练题库」把题库准备好；"
                 + "已有的练习数据不受影响。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: 640, alignment: .leading)
    }
}
