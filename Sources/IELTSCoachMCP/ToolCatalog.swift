import Foundation
import IELTSCoachCore

/// tool 的装配点。**spec 第 4.4 节那 7 个的名字与顺序一个字都不能改**；
/// 后加的排在它们后面。
public enum ToolCatalog {
    public static func tools(environment: MCPEnvironment) -> [MCPTool] {
        // 名字与顺序照抄 spec 第 4.4 节，一个字都不能改。
        [
            InitializeWorkspaceTool.make(environment: environment),
            OpenDashboardTool.make(environment: environment),
            // **`list_question_bank` 排在 `set_training_selection` 前面**：
            // 它是选题的第一步（先看有哪些题，再挑一道），上游的调用顺序也是这样。
            // 在这之前这个服务一个题号都吐不出来，而 `set_training_selection`
            // 的 questionId 是必填——模型只能反过来叫用户打开 App 自己抄一串题号过来。
            ListQuestionBankTool.make(environment: environment),
            SetTrainingSelectionTool.make(environment: environment),
            GetTrainingContextTool.make(environment: environment),
            SaveSessionReviewTool.make(environment: environment),
            ListPracticeHistoryTool.make(environment: environment),
            GetDashboardDataTool.make(environment: environment)
        ]
    }
}
