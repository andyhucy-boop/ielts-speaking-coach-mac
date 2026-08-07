import Foundation
import IELTSCoachCore

/// 7 个 tool 的装配点。**名字与顺序照抄 spec 第 4.4 节，一个字都不能改。**
public enum ToolCatalog {
    public static func tools(environment: MCPEnvironment) -> [MCPTool] {
        [
            InitializeWorkspaceTool.make(environment: environment),
            OpenDashboardTool.make(environment: environment)
        ]
    }
}
