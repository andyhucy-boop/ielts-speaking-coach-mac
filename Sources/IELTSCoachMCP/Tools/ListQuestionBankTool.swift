import Foundation
import IELTSCoachCore

/// **列出题库里的题。**
///
/// ## 它补的是一个死循环
///
/// 在这之前，这个 MCP 服务**一个题号都吐不出来**：唯一带题目的返回是
/// `get_dashboard_data`，而它只取「学习计划里今天那几道」——没有计划时是空数组。
/// 于是两句「下一步」正好互相指着对方：
///
/// - `get_dashboard_data` 说「还没有学习计划。下一步：可以直接用 set_training_selection 挑一道题」；
/// - `set_training_selection` 的 questionId 是必填，它的报错说「下一步：调用 get_dashboard_data
///   看看现在有哪些题」。
///
/// 用户本机的 state.json 正是这一格（258 道题、没有计划），
/// 也就是说在 Codex 里说一句「随便挑一道 Part 2 练一下」时，模型一道题都看不到，
/// 只能反过来叫他打开 App 自己抄一串 `p2-xxx` 过来。
///
/// 这正是本项目铁律 4 要拦的那种事——「下一步」指向一个够不着的东西。
///
/// ## 只读
///
/// 它不改任何东西。选题仍然归 `set_training_selection`：
/// 让「看一眼有哪些题」顺手把这一场也定下来，等于替用户做了他没做的决定。
enum ListQuestionBankTool {
    private struct Row: Encodable {
        let questionId: String
        let part: Int
        let topic: String
        let prompt: String
        /// 这道题下面的参考问句有几条。**逐条返回会把上下文撑爆**——
        /// 258 道题、每道六七句，光这一个工具就能吐出上千行。
        /// 要看具体问句的是 `get_training_context`，那时已经选定了一道题。
        let referenceQuestionCount: Int
        let practiced: Bool
    }

    private struct Payload: Encodable {
        /// 题库总数（不受这次筛选影响）。
        let total: Int
        /// 这次筛选之后有多少道（不受 limit 影响）。**必须和 returned 分开**：
        /// 只报 returned 的话，模型会把「截断了」当成「就这么多」。
        let matched: Int
        let returned: Int
        let questions: [Row]
        let note: String
    }

    static func make(environment: MCPEnvironment) -> MCPTool {
        MCPTool.throwing(
            name: "list_question_bank",
            description: "列出题库里的题，可按 Part 筛、按关键词搜。"
                + "拿到 questionId 之后交给 set_training_selection 选题。只读，不改任何东西。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "part": .object([
                        "type": .string("integer"), "minimum": .number(1), "maximum": .number(3),
                        "description": .string("只看这一个 Part（1/2/3）；省略则三个都看。")
                    ]),
                    "search": .object([
                        "type": .string("string"),
                        "description": .string("关键词，匹配题干、话题与参考问句，不分大小写。")
                    ]),
                    "onlyUnpracticed": .object([
                        "type": .string("boolean"),
                        "description": .string("只看还没练过的；默认 false（全都看）。")
                    ]),
                    "limit": .object([
                        "type": .string("integer"), "minimum": .number(1), "maximum": .number(200),
                        "description": .string("最多返回几条，默认 20。")
                    ])
                ]),
                "additionalProperties": .bool(false)
            ])
        ) { arguments in
            let part = try arguments.optionalInt("part", in: 1...3, default: 0,
                hint: "part 传 1、2 或 3；省略则三个 Part 都看。")
            let limit = try arguments.optionalInt("limit", in: 1...200, default: 20,
                hint: "limit 传 1–200 之间的整数；省略则返回 20 条。")
            let search = try arguments.optionalString("search") ?? ""
            let onlyUnpracticed = try arguments.optionalBool("onlyUnpracticed")
            let state = try environment.store.load()

            // **筛选走界面用的那同一份**（`QuestionSearch` 在 UI 里，Core 不能依赖它，
            // 所以这里按同一条规则重写了一遍——两处对同一个关键词必须给出同一批题）。
            var matched = state.questions
            if part > 0 { matched = matched.filter { $0.part == part } }
            if onlyUnpracticed { matched = matched.filter { $0.status != "practiced" } }
            let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
            if !needle.isEmpty {
                matched = matched.filter { question in
                    question.prompt.localizedCaseInsensitiveContains(needle)
                        || question.topic.localizedCaseInsensitiveContains(needle)
                        || question.followups.contains {
                            $0.localizedCaseInsensitiveContains(needle)
                        }
                }
            }

            let rows = matched.prefix(limit).map {
                Row(questionId: $0.id, part: $0.part, topic: $0.topic, prompt: $0.prompt,
                    referenceQuestionCount: $0.followups.count,
                    practiced: $0.status == "practiced")
            }

            var note: String
            if state.questions.isEmpty {
                note = "题库还是空的。下一步：用 open_dashboard 打开「训练题库」页导入题库文件，"
                    + "或者在命令行跑 `coach questions import <文件>`。"
            } else if matched.isEmpty {
                note = "题库里有 \(state.questions.count) 道题，但这次的条件一道都没匹配上。"
                    + "下一步：把 search 改短一点，或者去掉 part / onlyUnpracticed 再试一次。"
            } else {
                note = "拿其中一条的 questionId 交给 set_training_selection 就能选定这一场，"
                    + "再用 get_training_context 取考官提示词。"
                // **截断了必须说**：不说的话，模型会把这 20 条当成题库的全部，
                // 然后对用户说「你的题库里只有这些」。
                if matched.count > rows.count {
                    note += "另外还有 \(matched.count - rows.count) 道符合条件的没有返回"
                        + "（limit 是 \(limit)）。下一步：把 limit 调大，或者用 search 缩小范围。"
                }
            }

            return try ToolJSON.text(Payload(
                total: state.questions.count,
                matched: matched.count,
                returned: rows.count,
                questions: Array(rows),
                note: note))
        }
    }
}
