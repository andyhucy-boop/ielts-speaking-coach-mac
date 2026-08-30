# 待修问题清单

每一条都是**真去改了代码、真跑了测试、真看到结果**才报出来的——
不是「看起来可能有问题」，是「已经证明这个缺陷现在就能溜过去」。

修完一条就从这里删掉。**但只有自己做过突变、亲眼看到红，才允许删。**

**最后一次整体复核：2026-08-08 晚（题库重建模 + 考官临场发挥，见第负二节）。
基线 `swift test` = 1941 条 / 0 失败 / 19.9–20.6 秒（工作区含未提交的题库重建模改动）。**

> 同一天早些时候的成品终审（第负一节）当时写的是 1857。
> **今天晚上的基线是 1941**，别再拿 1857 去对。
> 另外记一个容易搞混的数：`HEAD`（`fc9e68d`）单独 checkout 出来跑是 **1879 条**——
> 差出来的 62 条住在**尚未提交**的题库重建模改动里。报数时必须写清是哪一份工作区。

> 上一次是 2026-08-07（Phase 5 录音，见第十节），当时的基线是 846 条 / 7.4–7.7 秒，
> 工作区与 `phase2-bridge` HEAD（`664808f`）一致。
> **但今天的基线是 1857**，别再拿 846 去对。

> 上一次是 2026-08-06 第二轮（第九节），当时的基线是 706 条 / 6.0–6.2 秒，
> 工作区与 `8ba702c` 一致。各节里的旧条数按当时实测原样保留，
> **但今天的基线是 846**，别再拿 706 去对。

> 下面第零到第八节写于**同一天的第一轮**复核，那时的基线是 522 条 / 5.2–5.6 秒
> （那一轮的工作区有 6 个文件的改动，见「零、本轮复核」）。
> 各节里的「522 条 0 失败」按当时的数字原样保留——那是它们实测时看到的，
> 但**别再拿 522 当今天的基线**。
>
> 再往前一版这里写的是 484 条。484 是更早一次复核的数字，中间几批补测试之后
> 实测就是 521 条；第一轮又加了 1 条，共 522。别再拿 484 当基线。

---

## 负二、题库重建模 + 考官临场发挥（2026-08-08 晚）：独立复核

复核方式与前几节一致：**不看实现者自己的测试变没变绿**，而是
（1）拿真实 PDF 在临时数据目录里重跑一遍导入、逐条比对原文；
（2）把新逻辑逐个改成空实现，看有没有测试变红；
（3）拿备份逐字段对账用户的真实数据；
（4）把生成出来的考官提示词全文读一遍，用人的判断说它像不像真考试。
探针跑完即删（`promptdump` 临时包在 scratchpad 里，没有进仓库）。

**基线：`swift test` = 1941 条 / 0 失败 / 19.9–20.6 秒**，工作区含未提交的题库重建模改动。

### 一、复核通过的（有证据，不是读代码觉得对）

**1. 真实 PDF 重跑：59 / 99 / 99 = 257，与实现者报的一致。**
用 `IELTS_SPEAKING_DATA_DIR` 指到临时目录跑 `coach questions import`，
**用户的真实数据全程只读**。抽查逐条比对了 PDF 原文（PDFKit 抽出 2514 行）：

- Part 1「Borrowing/lending」——用户自己举的那个例子：`topic` = `prompt` = 话题名，
  `followups` 是原文那 6 句，一字不差；
- Part 1「Advertisement」：折行的「…when you were a」+「child?」被正确接回一句；
- Part 2 第一张卡：题干含折行的「(not a teacher)」，4 条提示点全在，`topic` 是类别标签「人物」；
- Part 3 第一道：`topic` 挂的是它所属 cue card 的完整题干，8 条追问全在、折行全接回；
- 另写 python 脚本独立重扫原文：Part 1 独立数出来也是 59 个话题、名字与导入结果完全相同，
  290 行正文全部能在某条参考问句里找到（差出来的 10 行是被合并的折行）；
  Part 2/3 区里除 99 行「You should say」（结构行）外，没有一行内容没进题库。
  **零内容丢失。**

**2. 用户的真实数据没坏，且不只是「看起来没坏」。**
拿实现者动手前存的备份 `~/Desktop/ielts-coach-backup-20260808-185032` 逐字段对账：

- `sessions` / `currentSession` / `plan` / `issues` / `vocabulary` / `targets` / `learner` /
  `settings` / `questionSources` / `questionCursor` / `schemaVersion` —— **逐字段解析后相等**；
- 数据目录里除 `state.json` 之外的 12 个文件（8 个录音 + 1 份复盘 + 2 份待归档 + 锁文件）
  **SHA-256 全部相同**，一个没少、一个没多、一个没改；
- 那场真实练习（`2026-08-08-001`，164 条逐字稿）的 `questionId = p1-home-001`
  **仍然解析得到**「What do you like most about your home?」，`status` 仍是 `practiced`；
  录音 `recordings/2026-08-08T08-03-09Z.m4a`（1.6 MB）与复盘 `reports/2026-08-08-001.json` 都在；
- 1265 → 258 道，**旧题干消失 0 条**（把旧库每条 `prompt` 拿去新库的题干+参考问句里找，全部命中）。

**3.「导入」与「原地重建模」两条路真的收敛到同一批题号。**
把临时目录里那份**全新导入**的 257 道题与用户真实数据里那份**原地重建模**出来的 258 道题
按 id 取交集：257 个 id 完全相同，且**每一道的 `followups` 逐条相同**；
真实数据多出来的那一道正是他自己用 CSV 加的 `p1-home-001`（话题 Home 下唯一一道，判据刻意做窄）。

**4. 重跑安全。** 在真实数据上跑 `coach questions remodel`（**不带 `--apply`，只读**）：
「题库已经是新结构了，这次迁移一个字都没有改（共 258 道题）」。

**5. 突变证明：8 个突变，8 个如期变红。**
每次改完跑全量 1941 条，跑完还原并用 `diff` 逐文件核对还原成功，最后再跑一遍确认 0 失败。

| 突变 | 改成什么 | 结果 | 咬住它的测试（节选） |
|---|---|---|---|
| M1 | `ExaminerPrompt.improvisationRules` → 空串 | 11 处断言红 / 4 条测试 | `testPart1AndPart3TreatReferenceQuestionsAsRawMaterial`、`testPart1AndPart3PickTheNextQuestionFromTheLastAnswer`、`testPart1AndPart3AllowImprovisedFollowUpsInsideTheTopic`、`testFullMockCarriesTheRealPacingRulesForEveryPart` |
| M2 | `ExaminerPrompt.noScoreRule` → 空串 | 32 处断言红 / 1 条测试 | `testNoModeEverAllowsABandScore` |
| M3 | `followupHeading` 一律返回 Part 2 那句 | 6 处断言红 / 2 条测试 | `testPart1ReferenceQuestionsAreOfferedAsAPoolNotAChecklist`、`testPart3ReferenceQuestionsAreAPoolAndImprovisationIsRequired` |
| M4 | `TopicQuestions.supersedes` → 恒 `false` | 25 处断言红 / 10 条测试 | `AppStateTests.testImportingTheRemodelledBankMovesThePracticeHistoryOntoTheNewQuestion`、`QuestionBankRemodelTests.testPracticedStatusRidesAlongWhenAFragmentIsAbsorbed` 等 |
| M5 | `QuestionBankMigration.remapQuestionIDs` → 恒 `0`（不搬家） | 17 处断言红 / 7 条测试 | `testAPracticeSessionFollowsItsQuestionToTheNewID`、`testTheRetrainingLinkOriginalQuestionAlsoMoves`、`testTheSessionInFlightAlsoMoves`、`testThePlanMovesAndCollapsesDuplicatesWithinADay` |
| M6 | `PracticePicker.questions(inPart:)` 忽略 part | 8 处断言红 / 4 条测试 | `testEachPartListsOnlyItsOwnQuestions` 等 |
| M7 | `QuestionBankRemodel.topicQuestions` → 恒 `[]` | 17 处断言红 / 7 条测试 | `testRemodellingInPlaceLandsOnExactlyTheSameQuestionsAsReimportingTheBank`、`testItInventsNothing` 等 |
| M8 | `TopicQuestions.make` 把 `followups` 丢掉 | 43 处断言红 / 21 条测试 | 三条路（PDF / JSON / 原地重建模）同时红 |

M5 单独说一句：它咬住的 7 条恰好是「练习记录 / 复训链接 / 进行中的那一场 / 学习计划」四处
各自独立的守卫，**四处都活着**，不是搭一条测试的便车。

**6. 命令行那三处真实行为差异确实修好了。** 实测
`coach questions import 讲义.docx` → 现在给的是「扩展名是「.docx」，本工具只认 .csv、.json、.pdf 这 3 种」
＋一条能照做的下一步，不再是那句指向不存在问题的「题库表头缺少必需列「id」」。
`coach questions list 1` 会把每个话题下的参考问句逐条列出来。

### 二、读提示词全文之后的判断（**这一节不是测试结论**）

把 Part 1 / Part 2 / Part 3 / 全真模考四份提示词**用真实题目生成出来通读了一遍**。
**必须说清楚界线：提示词是在 ChatGPT 那边执行的，「考官照没照做」任何 `swift test` 都证明不了，
也没有人跑过真实练习（铁律 3 禁止碰真实 ChatGPT）。下面是读文本的判断，不是实测结果。**

**读下来，一个真考官照着做会像真考试**，三条最要紧的都写死了：

- **不会照单念题**：Part 1 抬头直接写「pick only 3–4 of them … Do NOT ask them all」，
  section rules 再补一句「Never work through a whole list of questions」；
  Part 3 写的是「treat them as a pool, not a script」＋「Some of your questions **must** be
  improvised on the spot」。用户自己举的那个例子（答第一问时聊到了钱，第二问就不该再问）
  有一句专门对应的规则：「When an answer already covers the ground of a later reference
  question, **drop that question** rather than asking it anyway」。
- **不会给分数**：四份提示词的开头都有那段红线，且明确写了「not if the learner asks for one」。
  这一条此前只守在复盘那一侧，考试当场是空的——补得对，而且 immediate 模式每答一句就要
  ChatGPT 开口，那里最容易漏出一个数字。
- **一次只问一个**：`Ask one question at a time` 在 contract 段，四种模式都带着。

**Part 2 干干净净**：没有沾一个字的临场发挥规则，提示点仍是「Follow-up points to cover」——
cue card 的四条提示点本来就该逐条覆盖，这个分流是对的。

读出来的三处**隐忧**（都记在下面第三节，因为它们是判断不是实测）：Part 3 单练时
把 cue card 原文当成「Today's question」交出去、Part 1 只供一个话题的问句池而规则要求覆盖 2–3 个、
以及「Target session length」和各 Part 自己的时长各说各的。

### 三、本轮新记的问题（按后果从重到轻）

**N-1（会让用户看到一条永远消不掉的提示）：跨季导入留下的旧碎片吸收不掉，
而界面那句「下一步」清不掉它自己。**

复现（探针实测，不是推理）：旧结构库里话题 `Shopping` 有 3 道碎片，
新一季的题库里这个话题**少了其中一句**（雅思题库每季度换题，这是常态）。
导入之后：

```
合并后题数：2
  [legacy-3] topic=Shopping prompt=Do you prefer shopping online or in shops? status=practiced followups=0
  [p1-…]     topic=Shopping prompt=Shopping                                    status=new       followups=3
replacements：["legacy-1": "p1-…", "legacy-2": "p1-…"]
legacyShapedCount：2
```

那道**练过的**旧碎片留了下来（留着本身是对的，不能悄悄删掉用户练过的题），
但 `legacyShapedCount` 因此恒为 2，题库页那张「你的题库里有 2 道题还是旧结构 …
下一步：点这一页最下面的「导入题库…」，把同一份题库文件再选一次」
**永远显示、而且照着做也消不掉**——再导一次同一份文件，结果一模一样。
这违反铁律 4 的后半句（下一步必须真的能解决问题）。
`coach questions remodel` 能修好它（它按 `(part, topic)` 重新分组，会把这道碎片并进去），
但那是命令行，界面上没有任何入口。
**修法建议**：要么让 `legacyShapeNotice` 在「本次导入已经吸收过一轮」之后改口，
要么把原地重建模做一颗按钮放到题库页（见 N-2）。

**N-2：原地重建模只有命令行有，界面上没有入口。**
`QuestionBankRemodel` 自己的文档注释把理由写得很清楚——用户手上那份 PDF 可能早就删了，
「再导一次」这条路走不通。但补出来的那条路（`coach questions remodel --apply`）
只有终端能走，而这个工具的用户是个考生，不是开发者。
题库页那句「下一步」也从没提过它。**不是缺陷，是缺口**：眼下用户的数据已经迁完了，
所以现在不咬人；换季或者换台电脑之后会咬。

**N-3：`.fullMock` 的考官提示词在 App 里走不到。**
这一轮把 part1Rules / part2Rules / part3Rules 三段正文原样嵌进了全真模考——改得对，
但全仓库**每一个** `SessionSetup` 构造点都是
`FocusPart(rawValue: "Part \(question.part)") ?? .fullMock`
（`TodayViewModel:221`、`PracticeRouteResolver:24`、`RetrainingSetupBuilder:33`、
`PracticeCommand.swift:61`、MCP 两处），题目的 part 只要落在 1–3 就永远拿不到 `.fullMock`。
学习计划页那个「全真模考」只影响**排计划时挑哪些题**（`PlanScope`），不影响提示词。
所以「全真模考现在带上三套规则了」这句话**代码属实、用户拿不到**。
`testFullMockCarriesTheRealPacingRulesForEveryPart` 钉的是文本，不是可达性。
**修法建议**：要么给「按计划练今天」这条路线加一个「连着考三个 Part」的入口，
要么把这段规则和它的测试一起标成「暂无入口」，别让下一个人以为它已经在用了。

**N-4（读文本判断）：Part 3 单练时，cue card 原文被当成「Today's question」交给考官。**
生成出来长这样：

```
Today's question (Part 3, topic: Describe one of your friends who learned a skill from someone (not a teacher)):
Describe one of your friends who learned a skill from someone (not a teacher)
```

section rules 里写的是「Start from the Part 2 theme」，但提示词里**没有一句**
告诉考官「考生刚讲完这张卡，不要再让他做两分钟独白」。
一个照字面办事的考官有可能先把这张卡念一遍、要求 describe。
**没法用测试证明会不会发生**（主语是 ChatGPT），所以放在这里而不是当成 bug 报。
**修法建议**：Part 3 的题目块抬头改成「The learner has just finished this Part 2 task
（不要再要求长回答）」之类的一句话。

**N-5（读文本判断，轻）：Part 1 规则要覆盖 2–3 个话题，但提示词只供一个话题的问句池。**
另外那 1–2 个话题的问题全靠考官自己编。这与「考官本来就该临场发挥」是一致的，
不算错；记一笔只是为了说明：一场 Part 1 里大约只有 3–4 问是有题库依据的，
其余 6–8 问在题库之外，「已练」也只记那一个话题。

**N-6（轻）：`Target session length` 与各 Part 自己的时长各说各的。**
Part 1 的实际取值是 6 分钟（`TodayViewModel:222`），而 section rules 写「about 4–5 minutes」。
两个数字并排出现在同一份提示词里，考官按哪个都说得通。差距不大，不急。

**N-7（文档，顺手记）：`docs/examiner-improvisation-acceptance-checklist.md` 里
写的「全套 swift test 1902 条」在当时属实，现在是 1941。** 已在本轮更新为 1941。

**N-8：Part 1 题库里学生 / 工作者两条分支的分隔符 `/` 被丢掉了，7 条问句混在一个池子里。**
`Study and work` 这个话题的参考问句现在是：
「Do you work or are you a student?」「What subject are you studying?」…「What work do you do?」「Do you like your job?」——
原文里学生那一支和工作者那一支是用一行 `/` 隔开的，抽取器按设计丢掉了这一行。
临场发挥规则（下一问由考生上一句决定）实际上能兜住它，但**分支信息确实没了**，
将来若要做「按考生身份挑问句」就得重新解析。记在案，眼下不改。

### 四、这一轮**没有**验的（别当成已验）

- **提示词的实际效果一个字都没验**：没有跑过任何真实练习（铁律 3）。
  「考官真的只问了 3 个就换话题」只能靠用户本人练一场，
  清单在 `docs/examiner-improvisation-acceptance-checklist.md` 第 2 节。
- **界面渲染没验**：第一节那条固有边界照旧——扫源码证明不了屏幕上真的画出来了。
  题库页那张 `legacyShapeCard`、挑题弹层那排 Part 分段控件，我只确认了代码里写着、
  用的是设计令牌、文案里的按钮真实存在，**没有人看见过它们**。
- **第一到第十节没有逐条复验**，按仍然存在处理。
- **没有审 1941 条测试里的其余部分**，只对本轮新逻辑做了 8 个突变。

---

## 负一、成品终审（2026-08-08）：13 条修完之后的独立复核

完整报告在 `docs/superpowers/FINAL-REVIEW.md`。这里只记**与本清单有关**的部分。

### 四条最狠的缺陷，逐条把修复拆掉看它复发

不是读代码判断「看起来修好了」，是把修好的那段逻辑改回缺陷前的形状、
用**自己写的探针**（不复用实现者的假件）跑一遍、看到原报告描述的确切后果，再改回去。
探针跑完即删，没有提交。

| 突变 | 拆掉的东西 | 看到了什么 | 咬住它的测试 |
|---|---|---|---|
| M-A | `PracticeRunner.ensureStillRunning` 掏空 | 取消之后录音器 `begin` 被调 1 次（麦克风真被重开）、`sendText` 照发、剪贴板从「用户刚复制的银行卡号」变 nil、`reports/` 真的多出一份复盘 | `PracticeCancelTests` 4 条 + 探针 2 条 |
| M-B | 两处 `guard !isWrappingUp` 掏空 | 连点两下 → `sendText` 被调 **2 次**，两条链路交错跑（`isVoiceActive, endVoice, sendText, isVoiceActive, endVoice, sendText, …`） | 探针 1 条（作者那组走的是别的判据） |
| M-C | `DataDirectory.safeURL` 掏空成「直接拼」 | **真实文件系统上**：`state.json` 真被删、录音目录真被递归删光、数据目录**外面**的文件真被删、那条记录也一起没了 | `SessionDeleterTests` 新补的 6 条 + 探针 1 条 |
| M-D | 分区表拿掉 habits/logic_feedback + `summary(from:)` 恒空 | 只含这三块的复盘 → 分区列表 `[]`，「回答前有较长停顿」「没有先直接回应问题」两句都到不了任何一行 | `ReviewReportViewModelTests` 7 条 + 探针 1 条 |

### 本轮修掉的一条守卫缺口（初审 3.2 点名、修第 3 条的人没关上）

**`LiveAXAccess` 的代次校验此前没有任何测试盯着。**
实测（突变 M-E）：把 `press`/`setValue` 里的 `element.epoch == currentEpoch` 整个删掉，
**1855 条测试没有一条会红**。

原因很具体：修第 3 条时新补的 `LiveAXAccessConcurrencyTests` 走的是「找不到目标 App」那道接缝
（`locateApp: { nil }`），那时 `elementMap` 恒为空，`press` 无论如何都返回 false——
它问的是「有没有丢 +1」「会不会当场炸」，恰恰问不到「旧引用还认不认」。
连它最后那句 `XCTAssertFalse(access.press(stale))` 也是恒成立的。

真删掉之后的后果：rawID 每次快照都从 0 重编，旧引用会**静默命中新树里编号相同的另一个元素**，
本工具在 ChatGPT 里按到别的控件上。

**修法**：把「验代次 + 取元素」抽成 `internal func resolve(_:)`（两件事仍在同一把锁里，
`press`/`setValue` 行为一个字没变），新增 `Tests/ChatGPTBridgeTests/LiveAXAccessEpochGuardTests.swift`
直接问它。接缝给的是**本测试进程自己**的 `AXUIElement`（没有 GUI，树里只有根节点一个——
而这里要的恰恰只是「映射表里有一条」），全程只问 `resolve`，`press`/`setValue` 一次都不调用，
**不碰真实 ChatGPT、不发出任何按键**（铁律 3）。
突变证明：把那一行改回没有代次校验的样子，`testAReferenceFromThepreviousSnapshotIsRefused…` 当场红。

### 从本清单里划掉的一条

- ~~`SessionDeleterTests` 的假件把数据目录外的路径一律当成「文件不存在」，路径穿越永远测不出来~~
  → **已修**：新补的 6 条走真实文件系统（`SystemFileRemover`），断言的是磁盘上
  `state.json` / 录音目录 / 数据目录外的文件还在不在。突变 M-C 验过它们真的会红。

### 仍然留在清单上的（终审逐条复核，都还在）

- **词汇导出的最后一跳（文本 → 文件字节）零测试**，界面那句「已经把 N 张卡片存到 xxx.txt」
  是拿内存里的数算的，跟磁盘上落了什么字节无关。
- **诊断的十个档位里有三个（录音、题库导入、生成计划）没有任何地方会写进去。**
  终审实测：`LastErrorLog.shared.record` 全仓库只有 4 个调用点（读盘、写盘、解析复盘、练习失败）。
- **逐字稿采样仍然在主线程上遍历整棵界面树**（`PracticeRunner.beginCollectingTranscript` 里那个
  `Task` 继承主 actor）。练习进行中界面每 2.5 秒顿一下，不丢任何数据。
- **文案指着不存在的东西还有 5 处**（`PlanRegenerator` 的「点『按计划练今天』」其实是卡片标题、
  `RetrainingCoordinator` 的「带着这个目标重练」全应用没有这颗按钮、
  「在访达中显示原文」不做存在性判断也不给反馈、命令行导入 PDF 时把原因说反了、
  `ChatGPTBridgeError` 是全项目唯一没有中文描述的错误类型）。逐条见 FINAL-REVIEW 第 3.3 节。
- **`AXDriver` 每场练习取复盘时都会清空并改写系统剪贴板，全程没有一句话告诉用户**
  （取消之后不会再发生了，但顺利路径上仍然如此）。
- **`scripts/seed-demo-data.swift` 的安全闸只认默认目录，不认自定义数据目录的环境变量。**
- 第一到第十节里没被上面点到名的，终审没有逐条复验，**按仍然存在处理**。

### 终审新记的一条观察（不是缺陷，但别当成保证）

**`ReviewParser.looksLikeReview` 只认四个键**（`must_correct` / `natural_upgrades` /
`logic_feedback` / `priority_target`），所以一份**只有** summary（或只有 habits / vocabulary /
answer_upgrades）的复盘会被整份拒收。属实，但失败是**响亮**的（中文错误 + 完整文件路径 + 下一步），
不是静默失败；改动解析器的判别力有误伤风险（它要在 ChatGPT 的闲聊里认出哪块 JSON 是复盘）。
已挂成后台任务，没有顺手改。

---

## 零、2026-08-06 第一轮复核：做了什么、看到了什么

（下文里的「本轮」指的是那一轮，不是终审。）

### 四个「曾经全绿」的最狠突变，现在全部变红

| 突变 | 结果 | 咬住它的测试 |
| --- | --- | --- |
| `QuestionBankView.runImport` 的 `catch` 块清空 | **4 条断言红** | `QuestionBankViewTests.testAFailedImportAlwaysPutsSomethingOnScreenInsteadOfSwallowingTheError` |
| `ReviewReportView` 的 `ForEach(document.sections)` → `ForEach([ReviewSection]())` | **2 条测试红** | `ReviewReportViewTests` 的分区断言 + 顺序断言 |
| `PracticeSheet.actions` 的 `default:` → `EmptyView()` | **8 条断言红**（8 个 stage 各报一次） | `PracticeSheetTests.testEveryPracticeStageHasAWayOut` |
| `QuestionBankViewModel` 的 `PDFDocument(url:)?.string` → `.page(at: 0)?.string` | **3 条测试红** | `QuestionBankPDFImportTests` 三条真 PDF 守卫 |

每次突变后都 `git checkout --` 还原并确认 `git status` 干净。

### 顺带复验的六个突变，也都咬住了

`panel.canChooseDirectories = false` 删掉、`panel.allowedContentTypes = …` 删掉、
`try app.applyImport(result)` 换成就地伪造的 `QuestionBankImportOutcome(…)`、
`.sheet(item:)` 闭包架空成 `EmptyView()`、PDF 抽取器的 part2 自己另写一套 id、
part3 丢掉 `topic` —— 六个全部变红。第一节（原「题库页导入全线无人看守」）
与第三节前两条据此删除。

### 本轮修掉的两件（都不是上面点名的四条）

1. **警告行的守卫其实一直没有咬合**——见下面第五节「已修，记一笔」。
2. **三个 shell 脚本在 UTF-8 locale 下直接崩**——见下面第六节「已修，记一笔」。

---

## 一、扫源码证明不了渲染（结构性边界 → 归 Task 11 人工验收）

**这一条不是待办，是这个手段的固有边界。写在这里是为了不让下一个人重新发现一遍。**

`SourceGuard` 那一整套做的是「源码里有没有这段文本」，不是「屏幕上有没有这个东西」。
因此下面这类突变，**扫源码永远拦不住**：

- **干净删除**：把渲染成员的声明和调用**一起**删掉，不留孤儿。
  `RenderReachabilitySweepTests` 只报「走不到的」，不报「不见了的」——
  它自己的失败文案就写着「确实不要了就连声明一起删掉」。
- **代码还在但跑不到**：`if let target = document.priorityTarget, false { … }`
  这类恒假条件，文本全在，断言全绿，界面上什么都没有。
- **叶子函数被掏空**：没有下级视图成员的渲染函数（例如 `statusBadge(for:)`）
  整个换成 `EmptyView()`，可达性扫描看不出来——守卫只钉得住上层那句调用。

**已经定了：不往这里投人，也不引第三方依赖（零依赖是硬约束）。**
真要堵死得引入渲染层测试框架（`ViewInspector` 之类），成本与约束都不允许。

**兜底方式：Task 11 的人工验收。** 那一关要真的把应用跑起来、逐页看一遍，
特别是复盘报告页（分区、NEXT SINGLE TARGET、原文页脚）、今日训练页的四条路线、
练习流程等待期间的出口按钮。**清单上任何一条「已修」都不等于「屏幕上真的画出来了」。**

作为补偿，各页现在都有一条「本页声明的渲染成员必须全部可达」的存在性清单
（例如 `ReviewReportViewTests.testEverySectionThisPageDeclaresIsReachableFromItsBody`
列出 13 个成员）。它挡得住「悄悄少画一块」，挡不住「连清单带实现一起删」。

---

## 二、渲染数据源被换空，仍有两处无人看守（本轮实测复现）

第二节原来列了三处，其中复盘报告页那两处已被 `ReviewReportViewTests` 钉住（见第零节）。
**剩下这两处，本轮 2026-08-06 重新实测，仍然全绿：**

1. **今日训练页的次级路线卡片**
   `Sources/IELTSCoachUI/Today/TodayView.swift:177`
   `ForEach(Array(available.dropFirst()))` → `ForEach(Array(available.dropFirst().prefix(0)))`
   → **522 条 0 失败**。四条路线只剩第一条，其余三条静默消失，用户不知道自己少了三个选择。
   **修法：** 比照 `ReviewReportViewTests` 的做法，在 `TodayViewTests` 里用
   `memberBody` 切出那一段，钉住 `available.dropFirst()` 整串并禁掉 `.prefix(` / `.dropLast(`。

2. **练习流程的进度清单数据源**
   `Sources/IELTSCoachUI/Session/PracticeSheet.swift:214`
   `ForEach(steps, id: \.stepName)` → `ForEach([PracticeStage](), id: \.stepName)`
   → **522 条 0 失败**。调用还在、可达性还在，但那九秒里进度清单一格都不画，
   用户看不出程序是在跑还是卡死了。
   **修法：** 切出 `checklist` 成员体，钉住 `ForEach(steps` 这个字面串。

> 注意这两条与第一节不是同一回事：数据源被换空时**调用还在**，
> 所以扫源码是拦得住的（钉住数据源那个字面串即可），只是现在没人钉。
> 第一节那种「干净删除」才是真的拦不住。

---

## 三、Core：`|` 分隔符碰撞（已知并已写进断言，保留观察）

第 10、11 条与本节原来的前两条都已修并复验（见第零节）。剩这一条：

`questionID` 用 `"\(topic)|\(prompt)"` 拼串，所以
`topic="A|B"/prompt="C"` 与 `topic="A"/prompt="B|C"` 算出同一个 id。

**这不是待修缺陷，是一个记录在案、当前故意接受的取舍**——
`QuestionIDTests.testTheSeparatorCollisionIsAKnownAndDeliberatelyAcceptedTradeoff`
已经把现状、原因、什么时候该改、改了要同步哪些断言全部写进去了。

保留在清单上只为一件事：**将来出现带竖线的题库来源，或本来就要做 id 迁移时，
顺手换成带长度前缀/转义的编码并加版本前缀。** 单独为它改一次 id 外形不划算——
全体用户每道题的 id 会变一遍，练习记录与训练计划会全部指错题。

---

## 四、设计系统：扫描器本身的六个口子（上一轮实测，本轮未复验）

第 5、6、7 条已修。以下六条是上一轮复核实测能溜过去的写法，**本轮没有重新实测**，
按原样保留——写下这句是因为「未复验」和「已确认仍在」不是一回事。

- **N1（最严重）：`.opacity()` 写成独立的视图修饰符就完全不受管。**
  `Text(hint).foregroundStyle(Palette.textSecondary).opacity(0.35)` 与被堵住的
  `Palette.textSecondary.opacity(0.35)` 视觉结果一样（对比度掉到 2:1 上下），
  但 `colorViolations` 的正则要求两者连在一起。同族的 `.brightness(` / `.grayscale(` /
  `.saturation(` 同理。
- **N2（最严重）：把令牌写成 `var` 或计算属性，三条完整性守卫全部失明。**
  根因是 `SourceGuard.declaredTokenNames` 的正则 `public\s+static\s+let\s+(…)` 只认 `let`。
  漏掉 `public` 写成 `static let` 也一样溜。
- **N3：颜色和字体的 enum 名单是写死的，只有 `Metrics` 是从源码读的。**
  往 `Palette.swift` 里加 `public enum Ink { … }` 并在视图里用它 → 全绿。
- **N4：钉住了取值，却没人管这个令牌有没有被用上。**
  删掉 `.tracking(Tracking.label)`（模块里唯一的使用处）→ 全绿；
  删掉 `CoachCard` 那整段发丝边框 `.overlay(RoundedRectangle(…).strokeBorder(…))` → 全绿，
  而规范第 4 节写的是「靠边框和留白分层，不靠阴影」。
- **N5：扫描根只有 `Sources/IELTSCoachUI`，模块外还有一个 SwiftUI 文件。**
  `Sources/IELTSCoachApp/main.swift` 里挂在根视图上的样式作用于整个应用。
  `SourceGuard.swiftFiles(in:describedAs:)` 已经被 `TodayViewModelTests` 用来扫整个
  `Sources/`，扩范围的工具是现成的。
- **N6（轻）：「被钉住」的判据只是一段文本存在。**
  `pinning.contains("XCTAssertEqual(Radius.sheet,")` —— 写
  `XCTAssertEqual(Radius.sheet, Radius.sheet)` 就满足了。右边得强制是字面量才有牙齿。

另记两笔（不是缺陷）：

- `RootView.swift` / `PermissionGateView.swift` 仍未收编进设计系统（共 33 处字面样式），
  靠 `testTheUnmigratedPagesCannotGetAnyWorse` 的上限 17 / 16 做棘轮。
  **棘轮只在四类扫描认得出的违规内成立**，`.frame(width:)` 那类不计数。
- `testSpacingScaleIsMultiplesOfFour`（`DesignSystemTests.swift:200`）是条弱测试，仍在。
  留一条弱测试在强测试旁边本身无害；记一笔是因为更早的报告里说它「已经一并改掉了」——不实。

---

## 五、练习流程：出口按钮已钉住，同类仍能溜

`default:` 那条（等待期间一颗按钮都没有）已修，见第零节。以下未修：

- **`case .done` 那颗「完成」没人钉。本轮 2026-08-06 实测：整块删掉 → 522 条 0 失败。**
  删掉之后 `.done` 掉进 `default`，按钮变成「取消」且接的是 `abandon()` → `runner.cancel()`。
  **练完、复盘已存档之后，收尾按钮写着「取消」，按下去走的是取消语义**——
  这比没有按钮更糟：用户以为自己刚把成绩取消了。
  注意 `testEveryPracticeStageHasAWayOut` 拦不住它，因为它只问「有没有出路」，
  `default` 那颗「取消」满足了这个问题。
  **修法：** 单独钉 `.done` 分支：必须有 `Button("完成"` 且动作是 `onClose`，不许是 `abandon`。
- **`SourceGuard.clickTargets` 的正则 `点(?:一下)?「([^」]+)」` 只认「点」和「点一下」。**
  `点击「X」`、`按「X」`、`按一下「X」`、`选「X」`、用『』写的，全都直接穿过去。
  仓库里本来就在用这些变体（`PracticeRunner.swift:191`、`TodayView.swift:371`、
  `AppState.swift:144`），不是假想写法。
- **文案扫描的范围只有 `Sources/IELTSCoachUI/`。**
  第 14 条那个 bug 本来就是从 `Sources/IELTSCoachCore/Review/ReviewParser.swift` 漏进来的。
  `Sources/ChatGPTBridge/HostEnvironment.swift` 今天也有两句直接指名图形界面按钮的文案，
  它们对得上靠的是 `HostEnvironmentTests:88` 一条手写断言，不是结构性检查。
  `SourceGuard` 已有 `swiftFiles(atRepositoryPath:)`，扩范围成本很低。
- **`SourceGuard.viewTypes(in:)` 把 `extension` 当独立类型切段**，又跳过不含 `body` 的段。
  结果任何写在 `extension SomeView { … }` 里的 `some View` 成员，可达性扫描完全看不见。
  「把成员按职责拆进 extension」是 SwiftUI 里最常见的整理手法。
  顺手要修的：`func …(…) -> some View` 那条正则的 `\([^)]*\)` 吃不下嵌套括号，
  带闭包参数的渲染方法会静默漏认；建议给「扫到的类型数」加一条硬对账
  （每个文件里 `: View` 的类型数必须与实际扫到的类型数相等）。

### 已修，但要记一笔：警告行的守卫此前一直没有咬合

`QuestionBankImportResultSheetTests.testEachWarningRowPrintsThatWarningInsteadOfAGenericSentence`
要求 `warning` 在 `ForEach` 闭包体里至少出现两次（闭包参数一次、真的画出来一次）。
**但它用的 `SourceGuard.occurrences` 是纯子串计数**，而那一行里同时有
闭包参数 `warning`、颜色令牌 `Palette.warning`、真正画出来的 `Label(warning, …)`——
**前两样就把「至少两次」凑满了。**

本轮实测：把 `Label(warning, …)` 换成一句泛泛之词 → **全绿**；
再把 `Palette.warning` 一并换掉才变红，证明它数到的是那个颜色令牌。

**已修**：新增 `SourceGuard.standaloneOccurrences(of:in:)`（前面挂点号的成员名、
以及只是撞了前缀的更长的名字都不算），该测试改用它，并补了 `SourceGuardTests` 自测。
修完复验：同一个突变现在 **1 条测试红**。

**教训（对后来者更重要）：凡是「参数收下了有没有真的用上」这类断言，
不要用 `occurrences`，用 `standaloneOccurrences`。** 纯子串计数很容易被
同名的令牌、同前缀的属性名悄悄凑满，测试看着有牙齿，其实一直是空转的。
清单里其他用次数做判据的地方值得照这个思路再扫一遍——本轮没有全面排查。

---

## 六、Bridge：两条同类未修

- **`PracticeRunner` 的三个注入超时全是空参数。本轮 2026-08-06 实测仍然全绿。**
  `Sources/IELTSCoachUI/Session/PracticeRunner.swift:77-79` 的
  `composerTimeout = 20` / `replyTimeout = 60` / `copyTimeout = 10`
  三行一起改成 `0.001` → **522 条 0 失败**。
  根因：`PracticeRunnerTests.swift:58/75/84` 的 `FakeBridge` 三个方法把 `timeout` 形参
  整个忽略，既不记录也不等待。全仓库没有第二个地方传这三个参数，所以它们今天纯粹是装饰。
  **注意这条不违反铁律 7**——要加的是守卫，不是改超时值本身。
  **修法：** `FakeBridge` 加 `recordedTimeouts`，断言拿到的是构造时传进去的那三个值
  （与 `FakeAXAccess` 的 `wakeTimeouts` 完全同构）。
- **`waitForAssistantReply` 自己的 `timeout` 形参是第 13 个等待点，扫描表漏了它。**
  （上一轮实测，本轮未复验。）`AXDriver.swift:181` 的 `addingTimeInterval(timeout)`
  改成 `addingTimeInterval(3.0)` → 全绿，唯一变化是耗时 1.80 → 4.68 秒。
  探针表里这条是全表唯一走成功路径的（`expectsFailure: false`），量到的只有采样间隔。
  生产上 CLI 传 60、`PracticeRunner` 传 `replyTimeout=60`；写死小了 → 3 秒就抛错，
  而错误文案是「等了 60 秒」（铁律 4 的假话）。
  **修法：** 加一条 `PacingProbe(step: "waitForAssistantReply 用调用方传进来的超时",
  atLeast: callerGiven * 0.8, expectsFailure: true)`，空树永远够不到 `minimumLength`。

### 已修，但要记一笔：三个 shell 脚本在 UTF-8 locale 下直接崩

本轮先是发现 `IconPipelineTests` 会**间歇性**失败（5 次里 5 次红，另外几次全绿），
追下去不是偶发，是**环境相关的必现**：

```
scripts/verify-iconset.sh: line 45: name?: unbound variable
```

根因：macOS 自带的是 **bash 3.2**。脚本里写了 `"…缺少 $name（$ICONSET）。"`——
`$name` 后面紧跟一个**全角括号**。当 `LC_CTYPE` 是 UTF-8 时，
bash 3.2 会把全角字符的第一个字节吞进变量名，变成 `name\xef`，
`set -u` 当场以「unbound variable」中止脚本。`LC_CTYPE` 没设时反而正常。

**为什么之前没人发现**：这台机器上 `LANG` / `LC_ALL` 都是空的，直接跑 `swift test` 一路全绿；
只有当调用方（例如 Python，PEP 538 会把 `LC_CTYPE` 强制成 `C.UTF-8` 并传给子进程）
带进一个 UTF-8 locale 时才炸。**而正常开发机和绝大多数 CI 镜像的 locale 就是 UTF-8。**

后果（铁律 4 + 5）：用户看到的不是「缺了哪个文件、下一步做什么」那句中文，
而是一句 bash 报错；`make-icon.sh` 整个非零退出。
`scripts/build-app.sh:69` 那句签名失败提示同样中招——**恰恰是最需要看懂错误的时刻。**

**已修**：把 5 处 `$变量` + 全角字符全部改成 `${变量}`（`verify-iconset.sh` 3 处、
`make-icon.sh` 1 处、`build-app.sh` 1 处）。
复验：`LC_CTYPE=UTF-8 swift test` → 522 条 0 失败；去掉大括号还原成原写法 → 当场 2 条红。

**仍未修（记录在案）：整个测试基线是随 locale 变的。**
没有任何地方把 `LC_CTYPE` 钉死，所以「本机全绿」不代表「CI 全绿」。
上面那个脚本 bug 在本机是**完全隐形**的——测试写对了、也确实会红，只是从来没在会红的环境里跑过。
**修法：** 在测试里显式给子进程设 `LC_CTYPE`（至少跑一遍 UTF-8），
或在 CI 里固定 `LANG=en_US.UTF-8`。**建议优先级高**：这类「基线本身不可信」的问题，
比清单上任何一条具体缺陷都更能让人误判交付状态。

---

## 七、两条已知局限，不是缺陷，但别让下一个人当成保证

- 等待点扫描测试的上界是全表统一的 0.5 秒。将来谁加一个 0.3 秒的「缓一拍」字面量，扫描照样绿。
- `testSendTextWaitsForTheSendButtonToAppearInsteadOfFallingBackImmediately`
  （`AXDriverTests.swift:175`）在机器忙的时候会偶发 unexpected failure（20 次里见到 1 次）。
  它用 `asyncAfter` 整树替换 `access.nodes`，而 `FakeAXAccess` 无锁、`onPress` 又对同一个
  数组做原地修改，后续 `waitUntil` 只有 0.05 秒窗口。
  建议改成用 `onSnapshot`（按采样次数造场景）而不是墙上时间的 `asyncAfter`。

---

## 八、报数口径

- 本轮基线：**522 条 / 0 失败 / 5.2–5.6 秒**（`LC_CTYPE` 空和 `LC_CTYPE=UTF-8` 两种都跑过）。
  > **已被第九节取代：2026-08-06 第二轮实测是 706 条 / 0 失败 / 6.0–6.2 秒。**
  > 本节的 522 与本文开头的 522 都是那一轮的数字，别再拿它当基线。
- 报数时请注明**工作区状态**与 **locale**。没有 locale 这一项的话，
  「全绿」这个说法本身是不完整的——见第六节。

---

## 九、Phase 4 两条真 bug 的独立复核（2026-08-06 第二轮）

复核方式：**不看修复方自己写的测试是否变绿**——那证明不了任何事。
而是（1）自己另写一份一次性探针复现两个 bug 的原始场景，
（2）把修好的产品代码逐条改坏，看探针和既有测试会不会红，
（3）跑完还原并确认 `git status` 干净。探针文件跑完即删，没有提交。

**基线：`swift test` = 706 条 / 0 失败 / 6.05 秒**（工作区干净，`phase2-bridge` HEAD = `8ba702c`）。
带上探针时是 710 条——下面每一条「全绿」都核对过 `Executed` 那一行的真实条数，
不是靠没看到红就当它跑过了。

### 结论：两条都是真 bug，两条都真的修好了

**1. 拼接顺序**（`Sources/IELTSCoachCore/Transcript/TranscriptAssembler.swift:144`）

探针：`ingest([Q1?, A1.])` 之后 `ingest([Q2?])`。
修复前的实现下顺序是 `["Q2?", "Q1?", "A1."]`——新问的那句跑到了整份逐字稿最前面。
连着三次每次只读到最新一条时更狠：`["three", "two", "one"]`，整份逐字稿被倒过来。
现在两条探针都是正序。

| 突变（对 `insertionIndex`） | 既有测试变红 | 我的探针变红 |
| --- | --- | --- |
| T1 退回修复前的 `return min(cursor, slots.count)` | 2 条 | 2 条 |
| T2 空实现 `return 0` | 10 条 | 2 条 |
| T3 只做一半：游标停在 0 就一律追加末尾，不往这一次采样后面看 | 1 条（`testScrollingBackRevealsAnEarlierMessageThatGoesBeforeWhatWeAlreadyHave`） | 1 条 |
| T4 一律追加末尾，连游标都不看 | 3 条 | 1 条 |

T1 只咬住 2 条、且正是复现这个 bug 的那 2 条——说明那两条测试盯的是 bug 本身，不是别的。
T3 与 T4 各自只咬住新逻辑的一支，两支都还活着，没有在修 bug 的过程中被顺手废掉。

**2. 复盘归档累加**（`Sources/IELTSCoachCore/Review/ReviewArchiver.swift:88`
与 `Sources/IELTSCoachCore/Model/Records.swift:72`）

探针：同一份复盘用同一个 `sessionID` 归档两次，断言整个 state 相等；
再换一个 `sessionID` 归档，断言这一次要计数。修复前 `occurrences` 2≠1、`lastSeenAt` 被补录时刻覆盖。

**可达性我自己查过，不是纸上谈兵：** `PendingReviewStore.markImported`（同文件 141 行）
只在归档**做完之后**才改名，改名撞名时抛错，文件就留在待处理列表里；
而 `Sources/coach/ReimportCommand.swift:114` 从文件名取 `sessionID`、
`Sources/IELTSCoachUI/Review/PendingReviewViewModel.swift:183` 用 `linkedSessionID`，
两条路都会拿**同一个** `sessionID` 再归档一次。这条路真的走得到。

| 突变 | 既有测试变红 | 我的探针变红 |
| --- | --- | --- |
| A1 退回 bug 现场（无条件 `+= 1` / 无条件覆盖 `lastSeenAt`） | 4 条 | 1 条 |
| A2 矫枉过正：命中已有记录就什么都不做 | 2 条 | 1 条 |
| A3 只守 `occurrences`，`lastSeenAt` 仍无条件覆盖 | 2 条 | 1 条 |
| M1 读盘迁移写成空实现（照抄盘上数字） | 1 条 | 1 条 |
| M2 读盘迁移过头（无条件 `= sourceSessionIds.count`，空数组也归零） | 1 条 | 1 条 |

A3 是修复方没跑过的一个突变，我补上的：`lastSeenAt` 那一行不是搭便车进守卫的，
它自己也被独立钉住了。

**顺带复验了「那条假测试」的说法，属实。** A1 突变下
`PendingReviewViewModelTests.testFollowingTheRetryInstructionDoesNotInflateOccurrences`
只有第 387 行（直接 `JSONSerialization` 读 `state.json` 原始数字）那句红，
第 380 行走 `store.load()` 的那句**照样绿**——因为 `IssueRecord.init(from:)` 的读时修复
在 load 那一步就把虚高的数字盖住了。两道防线必须各自被独立钉住，这句话是实测出来的。

### 交给最后 code-review 的守卫缺口：五条属实，两条不属实

下面每一条都真改了代码、跑了全量、看了 `Executed` 条数、跑完还原。

**属实（改坏之后 706 条全绿，无人看守）：**

1. **收尾重试复用会话编号**
   `Sources/IELTSCoachUI/Session/PracticeRunner.swift:205`
   `currentSessionID ?? SessionID.next(…)` → 无条件 `SessionID.next(…)` → **710 条 0 失败**。
   后果：收尾失败后重试，同一场练习会在「训练记录」里留下两条。
2. **逐字稿渲染的数据源**
   `Sources/IELTSCoachUI/History/HistoryView.swift:223`（复审写的 211 是 `transcriptPane` 的函数头，
   真正的 `ForEach` 在 223）
   `ForEach(Array(row.session.transcript.enumerated()), …)` → 换成空数组 → **710 条 0 失败**。
   后果：逐字稿一条都不画，而「这一场没有逐字稿」那段解释走的是 `isEmpty` 那一支，也不会出现——
   用户看到的是一片空白，没有任何解释。**这正是第二节那类「数据源被换空」，修法同第二节。**
3. **删除失败的中文说明被丢掉**
   `Sources/IELTSCoachUI/History/HistoryView.swift:295`
   `deletionFailure = app.deleteSession(row.session)` → `_ = app.deleteSession(…)` → **710 条 0 失败**。
   后果：`AppState.deleteSession` 老老实实返回了「哪几个文件没删掉、在哪儿」，
   界面把它扔了。孤儿文件永远躺在磁盘上，用户一无所知（铁律 5、7）。
   注意这条**不是** `AppState` 那一层的问题（见下面「不属实」第 1 条），
   是 `AppState` 与 `HistoryView` 之间那一步没人看。
4. **命令行的会话编号生成**
   `Sources/coach/PracticeCommand.swift:118-120`
   整段 `SessionID.next(…)` 换成写死的 `"2026-01-01-001"` → **710 条 0 失败**。
5. **命令行把练完的这一场记进 state**
   `Sources/coach/PracticeCommand.swift:183-192`
   构造 `PracticeSession` 并 upsert 进 `state.sessions` 那一整块删掉 → **710 条 0 失败**。
   后果：命令行练完一场，复盘落了盘，「训练记录」里却什么都没有。

**不属实（复审报的这两条是错的，别照着去改）：**

1. **`AppState.deleteSession` 不是无人看守。**
   把 `Sources/IELTSCoachUI/AppState.swift:180-184` 整个掏空成 `return nil`
   → **红 2 条**：`AppStateTests.testDeletingASessionTakesItOffThePageAndOffTheDisk`、
   `AppStateTests.testAReportThatCannotBeDeletedIsSaidOutLoudInsteadOfSwallowed`。
   这一层是有守卫的，缺的是它下游那一步（属实清单第 3 条）。
2. **`Sources/IELTSCoachUI/History/SessionDeleter.swift` 不是死代码。**
   复审说「grep 全 Sources 零命中」，实测有命中：`AppState.swift:180`
   就是 `SessionDeleter(directory:store:).delete(session)`，
   而 `AppState.deleteSession` 正是删除按钮唯一的生产路径。
   **千万别按复审说的把它删掉**——删了删除功能就没了，而且上面那 2 条测试会当场红给你看。

---

## 十、Phase 5 录音复核（2026-08-07，独立复核方写）

**基线：`swift test` = 846 条 / 0 失败 / 7.4–7.7 秒**，工作区干净，
与 `phase2-bridge` HEAD（`664808f`）一致。

这一节记的是 Phase 5 三条真 bug 修完之后**仍然没人看守**的地方。
体例同第九节：每一条都真改了代码、真跑了全量、真看了 `Executed` 条数、跑完还原。
**修完一条就删掉，但只有自己做过突变、亲眼看到红，才允许删。**

> 先说结论：三条真 bug 的修复本身**复核通过**。
> 设备切换竞态用一条从零重写的探针独立复现过（把修复还原成修前写法，探针 5 条断言红、
> 项目自己那条 `testRestartDoesNotClaimRecoveryWhenTheFileWasClosedDuringTheRestart` 3 条断言红）；
> `RecordingSettingsView` 的 `get:` 改 `{ true }`、`RecordingSettingsScene` 改 `EmptyView()`、
> 删 `Text(viewModel.consentText)`、删 `.onAppear { viewModel.refresh() }`
> ——四个突变逐个跑，每个都有对应的测试变红；
> `grep -rn "开启录音" Sources/` 现在只命中解释这次修复的注释，没有一句活着的文案。

### 属实的守卫缺口（改坏之后 846 条全绿，无人看守）

1. **`RecordingStore.delete(relativePath:)` 的路径穿越防护零测试**
   `Sources/IELTSCoachCore/Recording/RecordingStore.swift:121-122`
   把 `let url = try url(forRelativePath: relativePath)` 换成绕开校验的直接拼接
   （`directory.recordingsDirectory.appending(path: relativePath.replacingOccurrences(of: "recordings/", with: ""))`）
   → **846 条 0 失败**。
   现有两条穿越测试（`RecordingStoreTests.swift:78`、`:86`）**只调 `url(forRelativePath:)`**，
   没有一条调 `delete`；`delete` 那两条（`:110`、`:119`）走的都是老实路径。
   后果：`state.json` 里的 `recordingPath` 被改坏（或将来有别的写入方），
   删除按钮就能删到 `recordings/` 外面去，而这是**用户按一下就没了的东西**。
   修法：把 `:78`/`:86` 那张恶意路径表**同时**喂给 `delete`，断言抛 `unsafePath` 且目标文件还在。

2. **`RecordingUsage.summaryText` 的占用大小零约束**
   `Sources/IELTSCoachCore/Recording/RecordingStore.swift:29`
   `"录音 \(count) 个，共占用 \(Self.humanReadable(bytes: bytes))。"` → `"录音 \(count) 个。"`
   → **846 条 0 失败**。
   后果：「录音占了多少地方」整页只剩个数，用户没法判断该不该清理——
   而这一页存在的全部理由就是那个大小。`humanReadable` 自己那几条测试还绿着，
   但**没有一条测试问过 `summaryText` 里到底有没有把它印出来**。

3. **幽灵控件扫描只扫 `Sources/IELTSCoachUI/`，Audio 与 Core 的文案在圈外**
   `Tests/IELTSCoachUITests/Support/SourceGuard.swift:154`
   （`uiSourceRelativeRoot = "Sources/IELTSCoachUI"`，`swiftFiles()` 默认就走它）
   把 `Sources/IELTSCoachAudio/RecordingSession.swift:245` 那句
   `下一步：点「我练完了」…` 改成 `下一步：点「立刻停止录音」…`
   （一颗全 App 都不存在的控件）→ **846 条 0 失败**。
   对照实验：同样的幽灵名字塞进 `Sources/IELTSCoachUI/Session/PracticeStage.swift`
   会被 `RenderReachabilitySweepTests.testEveryButtonNamedInUICopyActuallyExists` 当场逮住。
   **这条最值得先修**：本轮新写的那段中文警告（写入端已死时那条）就落在圈外，
   它点名的「我练完了」眼下是靠人工 grep 验的；
   `AVAudioEngineCapture.swift:49` 同样在圈外。
   哪天有人把 `PracticeSheet.swift:328` 那颗按钮改个名，
   这两句话会**一声不响地**变成指着空气。
   修法：`literalClickTargets` 那一轮改扫整个 `Sources/`
   （`swiftFiles(in:describedAs:)` 已经支持任意目录，第 251 行的注释里就写着这个用法），
   控件清单仍从 `Sources/IELTSCoachUI/` 里取。
   顺带说明：`MicrophonePermissionState.swift`（Core）虽然也在圈外，
   但它有 `RecordingSettingsViewTests` 的定点守卫——把那两句 `「保存我的回答录音」`
   改成 `「打开麦克风录音」`，**红 3 条**。定点守卫有牙，缺的是那一圈普扫。

4. **`ReviewParser` 仍然点名一颗谁也没有的「补生成复盘报告」，命令行照单全收**
   `Sources/IELTSCoachCore/Review/ReviewParser.swift:50-51`
   图形界面那三条路（`PracticeRunner`、`ReviewReportLoader`、`PendingReviewViewModel`）
   都已经用 `diagnosisOnly(_:)` 把这句「下一步」砍掉了，砍得对。
   但 `Sources/coach/PracticeCommand.swift:133` 与
   `Sources/coach/ReimportCommand.swift:78` 是 `print(error.localizedDescription)` 原样打出来的，
   于是终端用户连着读到两句「下一步」，第一句是
   `下一步：点「补生成复盘报告」让 ChatGPT 重新输出一次。`
   **而这个东西根本不存在**：`coach` 只有 `doctor` / `questions` / `practice` / `reimport`
   四个子命令（`Sources/coach/main.swift:19-25`），
   `grep -rn "补生成" Sources/` 除了这两行文案自己只剩注释；
   终端里也没有任何东西可「点」。
   要紧的是：`PracticeRunner.swift:591`、`ReviewReportLoader.swift:81`、
   `PendingReviewViewModel.swift:158` 三处注释都白纸黑字写着
   「在命令行那边是对的」「命令行那边照它做是对的，改了反而把两边一起弄坏」——
   **这个前提是假的**，而正是这句假前提让三轮修复都绕着它走。
   这已经是本项目同一类缺陷的第三次（前两次：「补生成复盘报告」在界面、「开启录音」）。
   修法：改 Core 那两句文案本身（两个出口都错，不存在「退让哪一侧」的问题），
   顺手把三处注释里的假前提删掉。

### 顺带查出来、不属于守卫缺口的一条真缺陷

5. **第一条缓冲区就写盘失败时，警告自相矛盾：说文件保住了，又说文件删掉了**
   复现（探针跑过，已删）：`writer.secondsToReport = 0`（`AACSegmentWriter.finish()`
   在一帧都没落地时返回的就是 0，见 `AACSegmentWriter.swift:100`），
   `start()` → `failOnWrite = true` → `deliver(一个缓冲区)` → `finish()`。
   用户读到的是这一整段：

   > 录音在中途写不下去了：…
   > **已经录到的部分完整保存在 recordings/xxx.m4a**，练习本身不受影响。下一步：确认磁盘还有空间，然后重新练一次。
   > 这次一秒录音都没录到，**已经把空文件删掉了**。下一步：…

   第一句给了一个具体路径让用户去找，第二句说那个文件已经删了；
   `outcome.relativePath` 同时是空字符串，界面上一条录音都不会出现。
   用户照着第一句去数据目录里翻，翻不到。
   触发条件很实在：磁盘一开始就是满的。
   起点：`RecordingSession.swift:173-176`（`append` 的 catch 无条件说「完整保存在」，
   没问过到底有没有录到东西）与 `:145` 的 `disposeOfTheEmptyFile()` 撞在一起。
   `handleConfigurationChange` 的 catch 分支（`:258-262`）是同一句话，同一个坑。
   **本轮新加的那条文案没有掉进来**：写入端已死那条分支的上游守卫
   （`:194` 的 `guard !stopped, writer != nil`）会先拦掉，实测走不到。
   现有 `testWriteFailureStopsRecordingButKeepsWhatWasWritten` 用的是默认的 12 秒，
   所以从来没碰过 0 秒这一支。

---

## 2026-08-20：一次没能复现的测试抖动

`swift test` 有一次报了 **2 failures**，紧接着连跑六遍全绿（2143 / 0）。
那一次是在同一条命令里 `swift build && swift test` 连着跑的，机器刚编完还在忙。

**没有查到是哪两条**：那一轮的输出里 `grep "error:"`、`grep "' failed ("` 都是空的，
说明失败没走 XCTAssert 的常规报错路径（可能是超时类断言，或者输出被抢跑截断了）。

嫌疑最大的是几条**带轮询上限**的测试（`PracticeRunnerArchiveTests.waitUntil(seconds:)`
那一类、录音相关的几条）：它们的判据是「N 秒内条件成立」，机器负载高时会踩线。

**下一步**：再遇到时，用 `swift test 2>&1 | tee /tmp/t.log` 完整留档，
在 `/tmp/t.log` 里搜 `failed` 而不是 `error:`。在能复现之前不要动任何测试的超时数字——
把超时调大是掩盖，不是修复。

---

## 2026-08-30：上面那次抖动抓到了，是**两条不同的**测试

按上一节留下的做法（`tee` 全量日志，搜 `' failed ('` 而不是 `error:`），
连跑四遍 `./scripts/build-app.sh`，前两遍各红一次、后两遍全绿。**两次红的不是同一条。**

### 一、`AXDriverTests.testSendTextWaitsForTheSendButtonToAppearInsteadOfFallingBackImmediately`
**已修，机制清楚。**

它原来靠 `DispatchQueue.global().asyncAfter(deadline: .now() + 0.02)` 让 Send 按钮晚一点出现，
等待窗口给的是 1 秒。全量跑测试时几百条用例把全局队列的线程占满，
那个 0.02 秒的块可能一秒都排不上 —— 于是等待窗口先到期。
**失败与被测代码无关，只与机器有多忙有关。**

改成用 `FakeAXAccess.onSnapshot` 在「第 3 次读树」时补上按钮：不再依赖调度延迟，
而且守的东西更准了 —— 它现在证明的是「会一直读到按钮出现为止」这个行为本身，
不是「一秒之内能不能等到」。

> 改的过程里自己踩了一个坑，记下来：第一版是**整树替换**，
> 于是每次读树都把输入框的 value 写回「你好」，而 `onPress` 清空它正是
> 「文字确实发出去了」的判据 —— 结果那条测试从偶发红变成稳定红。
> 往树里补东西时只 `append`，别整树替换。

### 二、`NotarizeScriptTests.testExecuteRefusesToResignBeforeTheSignatureBaselineIsRotated`
**未修，机制未明。**

失败的是这两条断言：`result.output.contains(recordedBaseline())` 与
`result.output.contains(newRequirement)` —— 也就是 `scripts/notarize.sh --execute`
**在走到比对基线那一步之前就退出了**（输出里只有「❌ 前置条件没满足，不执行公证。」）。

已经排除的猜想：

- ~~`.build/IELTS Speaking Coach.app` 不存在导致前置条件不过~~ ——
  **实测否掉了**：手动删掉那个 .app 再跑，10 条全过（`ensureBuiltAppExists` 会造一个空壳）。
- 单独跑 `swift test --filter NotarizeScriptTests` 连跑六遍，一次都不红。

剩下的唯一共同点：**只在整套测试一起跑时出现**（`PackagingTests` 与其余目标并行，
而这条测试要 fork 一个 shell 脚本、脚本里再调好几个假工具）。
嫌疑是脚本里某一步在机器满负载时超时或被抢跑，但没有证据。

**下一步**：再遇到时，把 `result.output` 整段打进失败信息（现在只打了断言那一行的上下文），
那样一眼就能看出脚本停在哪个前置条件上。在拿到那段输出之前，
**不要动脚本里的任何超时数字，也不要给这条测试加重试** —— 那是掩盖，不是修复。
