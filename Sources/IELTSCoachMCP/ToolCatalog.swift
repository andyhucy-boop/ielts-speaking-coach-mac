import Foundation
import IELTSCoachCore

/// 7 个 tool 的装配点。**名字与顺序照抄 spec 第 4.4 节，一个字都不能改。**
public enum ToolCatalog {
    public static func tools(environment: MCPEnvironment) -> [MCPTool] {
        // 名字与顺序照抄 spec 第 4.4 节，一个字都不能改。
        [
            InitializeWorkspaceTool.make(environment: environment),
            OpenDashboardTool.make(environment: environment),
            SetTrainingSelectionTool.make(environment: environment),
            GetTrainingContextTool.make(environment: environment),
            SaveSessionReviewTool.make(environment: environment),
            ListPracticeHistoryTool.make(environment: environment),
            GetDashboardDataTool.make(environment: environment)
        ]
    }
}
