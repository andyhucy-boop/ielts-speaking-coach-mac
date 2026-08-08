#!/usr/bin/env swift
// 造一份演示用的训练数据，供人工验收问题档案页/词汇页/首页统计。
//
// 用法：swift scripts/seed-demo-data.swift [输出目录]
// 不给参数时写到临时目录。
//
// ⚠️ 这个脚本会覆盖目标目录里的 state.json。它硬性拒绝写入真实数据目录。
//
// 刻意不 import IELTSCoachCore，直接手写 JSON：这样它同时是一次独立的 schema 校验，
// App 读不出这份手写的 state.json，说明模型的容错解码有问题——而那正是要发现的事。
// 安全闸由 Tests/IELTSCoachCoreTests/SeedDemoDataScriptTests.swift 自动化守着
//（那些测试用 CFFIXED_USER_HOME 把「真实数据目录」挪到临时位置，不碰用户数据）。
import Foundation

// MARK: - 目标目录与安全闸

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : NSTemporaryDirectory() + "ielts-demo-data"

// 加了引号的 "~/Library/..." 不会被 shell 展开，得由这一行负责——不展开就等于
// 绕过下面的安全闸：脚本会在当前目录下造一个名叫 "~" 的目录，用户却以为自己
// 指的是真实数据目录。
//
// **实测（Swift 6.3.3）`URL(fileURLWithPath:)` 自己就展开波浪号**，所以这里
// 不再多写一次 `expandingTildeInPath`——多写的那一行没有任何测试能让它变红。
// 这个前提由 testRefusesATildePathThatExpandsIntoTheRealDataDirectory 盯着：
// 哪天工具链不再展开波浪号，那条测试会红，届时再在这里补展开。
let target = URL(fileURLWithPath: outputPath).standardizedFileURL

let realRoot = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appending(path: "IELTS Speaking Coach").standardizedFileURL.path

guard target.path != realRoot, !target.path.hasPrefix(realRoot + "/") else {
    FileHandle.standardError.write(Data("""
    ❌ 拒绝写入真实数据目录：\(realRoot)
       这个脚本会覆盖 state.json，写进真实目录会毁掉你已有的练习记录。
       下一步：换一个目录，例如
         swift scripts/seed-demo-data.swift /tmp/ielts-demo

    """.utf8))
    exit(1)
}

// MARK: - 时间工具

let iso = ISO8601DateFormatter()
iso.formatOptions = [.withInternetDateTime]

let dayFormatter = DateFormatter()
dayFormatter.locale = Locale(identifier: "en_US_POSIX")
dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
dayFormatter.dateFormat = "yyyy-MM-dd"

let now = Date()
func daysAgo(_ count: Int) -> Date { now.addingTimeInterval(TimeInterval(-count * 86_400)) }

// MARK: - 12 场练习：11 天前到今天，每天一场

var sessions: [[String: Any]] = []
var sessionIDs: [String] = []          // 由旧到新

for ago in stride(from: 11, through: 0, by: -1) {
    let started = daysAgo(ago)
    let id = dayFormatter.string(from: started) + "-001"
    sessionIDs.append(id)
    sessions.append([
        "id": id,
        "questionId": "demo-q\(ago)",
        "focusPart": ago % 3 == 1 ? "Part 2" : "Part 1",
        "startedAt": iso.string(from: started),
        // 时长在 18–24 分钟之间变化，让「本周开口时长」不是个整齐的假数字
        "endedAt": iso.string(from: started.addingTimeInterval(60 * Double(18 + ago % 7))),
        "goal": "",
        "transcript": [],
        "reportPath": "",
        "recordingPath": ""
    ])
}

/// 取第 n 场（0 = 最旧）。窗口划分：最近 5 场是 7...11，再往前 5 场是 2...6。
func session(_ index: Int) -> String { sessionIDs[index] }

// MARK: - 5 个问题，覆盖全部趋势分支

/// `occurrences` 恒等于 `sourceSessionIds.count`（见 `IssueRecord` 的注释：
/// 它数的是「在几场练习里犯过」，读盘时还会按这条恒等式算回来）。
/// 所以这里由场次列表推出来，不另给一个数——写一个对不上的数字，
/// 用户打开 state.json 看到 6、界面上看到 5，会以为界面算错了。
func issue(_ id: String, said: String, correction: String, why: String,
           indices: [Int]) -> [String: Any] {
    [
        "id": id,
        "learnerSaid": said,
        "correction": correction,
        "whyItMatters": why,
        "occurrences": indices.count,
        "sourceSessionIds": indices.map(session),
        "lastSeenAt": iso.string(from: daysAgo(11 - (indices.max() ?? 0)))
    ]
}

let issues: [[String: Any]] = [
    // 出现变少了：之前 5 场里犯 4 场，最近 5 场里只犯 1 场
    issue("issue-decreasing", said: "I very like this place.",
          correction: "I really like this place.",
          why: "very 不能直接修饰动词，考官会当成基础语法错误",
          indices: [2, 3, 4, 5, 11]),
    // 最近没再出现
    issue("issue-gone", said: "I am agree with that.",
          correction: "I agree with that.",
          why: "agree 本身就是动词，不需要 be 动词",
          indices: [2, 3]),
    // 出现变多了
    issue("issue-increasing", said: "Yeah... you know... like...",
          correction: "去掉口头禅，改成一个短停顿",
          why: "填充词密集会明显拉低流利度印象",
          indices: [2, 9, 10, 11]),
    // 还是老样子
    issue("issue-steady", said: "It's very good.",
          correction: "It's genuinely rewarding.",
          why: "good/very 这类词反复出现会拉低词汇多样性",
          indices: [3, 4, 8, 9]),
    // 新问题：只出现在最近两场
    issue("issue-fresh", said: "In my country have many parks.",
          correction: "In my country, there are many parks.",
          why: "缺主语的句子在 Part 3 长回答里会成片出现",
          indices: [10, 11])
]

// MARK: - 6 条词汇，含两条会被导出跳过的

let vocabulary: [[String: Any]] = [
    ["id": "vocab-1", "basicWord": "good", "betterExpression": "rewarding",
     "collocation": "a rewarding experience", "priority": "high",
     "sourceSessionIds": [session(2), session(7), session(11)]],
    ["id": "vocab-2", "basicWord": "important", "betterExpression": "crucial",
     "collocation": "a crucial factor", "priority": "high",
     "sourceSessionIds": [session(5)]],
    ["id": "vocab-3", "basicWord": "a lot of", "betterExpression": "a great deal of",
     "collocation": "a great deal of effort", "priority": "normal",
     "sourceSessionIds": [session(6), session(9)]],
    ["id": "vocab-4", "basicWord": "happy", "betterExpression": "upbeat",
     "collocation": "in an upbeat mood", "priority": "medium",   // 没见过的写法，应归到「有空再记」
     "sourceSessionIds": [session(8)]],
    // 这条背面是空的，导出时必须被跳过并给出说明
    ["id": "vocab-5", "basicWord": "nice", "betterExpression": "",
     "collocation": "", "priority": "low",
     "sourceSessionIds": [session(3)]],
    // 这条正文里含制表符与换行，用来验证清洗（导出后应仍是一行三列）
    ["id": "vocab-6", "basicWord": "busy", "betterExpression": "swamped\twith work",
     "collocation": "I was swamped\nall week", "priority": "normal",
     "sourceSessionIds": [session(10)]]
]

// MARK: - 组装并落盘

let state: [String: Any] = [
    "schemaVersion": 3,
    "learner": ["displayName": "演示数据", "createdAt": iso.string(from: daysAgo(30))],
    "currentSession": NSNull(),
    "sessions": sessions,
    "targets": [[
        "id": "logic-explain-example",
        "label": "回答后补一个原因和一个例子",
        "status": "new",
        "evidence": ["I just like it."],
        "sourceSessionId": session(11),
        "createdAt": iso.string(from: daysAgo(0))
    ]],
    "issues": issues,
    "vocabulary": vocabulary,
    "plan": NSNull(),
    "questions": [],
    "questionSources": [],
    "settings": ["recordingEnabled": false, "recordingConsentAt": "", "weeklyGoal": 5],
    "questionCursor": ["part1": 0, "part2": 0, "part3": 0]
]

do {
    // 只建目标目录本身。计划里原本还顺手建了 reports/ pending-reviews/ recordings/，
    // 但 App 每次读写 state.json 都会先 `DataDirectory.createIfNeeded()` 把这三个建出来，
    // 其余读取处（RecordingStore、PendingReviewStore、coach reimport）也都先 fileExists 再读，
    // 没有任何一处需要脚本代劳——建了也没有任何测试守得住，删掉。
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: state,
                                          options: [.prettyPrinted, .sortedKeys])
    try data.write(to: target.appending(path: "state.json"), options: .atomic)
} catch {
    FileHandle.standardError.write(Data("""
    ❌ 写入失败：\(error.localizedDescription)
       下一步：确认 \(target.path) 这个位置可写，或换一个目录再试。

    """.utf8))
    exit(1)
}

print("""
✅ 演示数据已写入 \(target.path)
   12 场练习（最近 12 天，每天一场）、5 个覆盖全部趋势的问题、6 条词汇。

   下一步：带着这个数据目录打开 App——

     IELTS_SPEAKING_DATA_DIR="\(target.path)" \\
       ".build/IELTS Speaking Coach.app/Contents/MacOS/IELTSCoachApp"

   （直接跑 .app 里的二进制，签名与辅助功能授权都不受影响。
     不要用 open 命令，那样传不进环境变量。）
""")
