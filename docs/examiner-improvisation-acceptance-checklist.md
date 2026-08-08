# 考官临场发挥 · 验收清单（只能人工验的那一部分）

日期：2026-08-08
改动文件：`Sources/IELTSCoachCore/Prompt/ExaminerPrompt.swift`
测试：`Tests/IELTSCoachCoreTests/ExaminerPromptTests.swift`（本次 36 条，全套 `swift test` 1902 条全绿）

---

## 0. 为什么这件事必须人工验

**提示词是在 ChatGPT 那边执行的，我们这一侧只能把话写清楚，验不了它照没照做。**

自动化测试能钉住、也只能钉住一件事：**这些指令确实写进了发给 ChatGPT 的那段文字**。
「考官真的只问了 3 个就换话题」「考官真的把我已经答到的那句跳过了」——
这两句话的主语是 ChatGPT，不是本项目的代码，任何 `swift test` 都证明不了。

所以下面第 2 节这五条**没有对应的自动化测试，也不可能有**。
它们要你戴上耳机、真的练一场，用耳朵判断。

**第 1 节相反：那些是已经被测试钉死的，你不用验**，列在这里只是让你知道界线在哪。

---

## 1. 已经被测试钉住的（不用你验）

每一条后面括号里是钉它的测试名。这些指令被从提示词里删掉，对应测试立刻变红——
2026-08-08 逐条做过突变证明，21 个突变 21 个如期变红。

| 提示词里写了什么 | 钉它的测试 |
|---|---|
| Part 1：约 4–5 分钟、2–3 个话题、每话题只问 3–4 个、共约 9–12 问、不许把一张单子问穿 | `testPart1PacingFollowsTheRealExam` / `testPart1UsesShortQuestionRule` |
| Part 3：共 4–8 问、从 Part 2 的话题往抽象层面走 | `testPart3PacingFollowsTheRealExam` |
| Part 1 与 Part 3：参考问句是素材不是清单 | `testPart1AndPart3TreatReferenceQuestionsAsRawMaterial` |
| Part 1 与 Part 3：下一句问什么取决于考生上一句说了什么；已经答到的就跳过 | `testPart1AndPart3PickTheNextQuestionFromTheLastAnswer` |
| Part 1 与 Part 3：可以自己编追问，但不许跑出当前话题 | `testPart1AndPart3AllowImprovisedFollowUpsInsideTheTopic` |
| Part 3：有一部分问题必须现编，不能全从单子上拿 | `testPart3RequiresSomeQuestionsToBeImprovisedFromScratch` |
| **Part 2 一个字都不许沾以上几条**（cue card 的提示点仍是「要覆盖的要点」） | `testPart2DoesNotGetTheImprovisationRules` / `testPart2CueCardBulletsAreStillPointsToCover` |
| 全真模考把三个 Part 的规则正文都带上（原先只写了一句「apply each part's own rules」，正文压根没进去） | `testFullMockCarriesTheRealPacingRulesForEveryPart` |
| 红线：一次只问一个问题 | `testEveryModeStillAsksOneQuestionAtATime` |
| 红线：**绝不给雅思分数、分数段或等级**，学员开口要也不给 | `testNoModeEverAllowsABandScore` |
| 红线：本次复训目标不许提前告诉考生 | `testGoalIsKeptFromTheLearnerDuringTheExam` |
| 红线：deferred 模式全程不给反馈 / immediate 模式每答一句给一条中文短评 | `testDeferredTimingForbidsMidSessionFeedback` / `testImmediateTimingAsksForOneShortChineseCorrection` |

---

## 2. 只能你本人验的五条

**做法**：

1. 按 `⌘,` 打开设置窗口，确认「反馈时机」这一栏选的是**全程零反馈**（默认就是它）
2. 回主窗口，左边选「今日训练」，挑一道 **Part 1** 的题
   （题库重建模之后，一道题就是一个话题，比如「8 Borrowing/lending」）
3. 开始练习，练完之后照下面五条对照你刚刚听到的

> 每一条都填「符合 / 不符合」，不符合的把**考官实际说的那句英文原话**抄下来——
> 抄下来的原话是下一轮改提示词唯一能用的证据，凭印象说「感觉还是很死板」改不动任何东西。

### 2.1 Part 1 一个话题只问 3–4 个就换话题

- 数一下：第一个话题下考官一共问了几个问题？
- **符合**：3 或 4 个，然后他换到了另一个日常话题（工作、住处、天气……）
- **不符合**：他把这个话题下你在题库里看到的那五六个问句**一句不落地问完了**——
  那就是照单念题，改动没生效

### 2.2 一整场 Part 1 覆盖了 2–3 个话题

- **符合**：换过 1–2 次话题，全场大约 9–12 问
- **不符合**：从头到尾只在一个话题里打转

### 2.3 你已经答到的那个问题，考官跳过了

**这是这次改动最核心的一条**，也是你自己举的那个例子：

> 他问「Do you like to lend things to others?」，你回答的时候顺带聊到了钱，
> 那「Have you ever borrowed money from others?」这句他就不该再问。

- 练的时候**故意**在第一个回答里多说一句，把这个话题下的另一个问句的内容先说掉
- **符合**：他没有再问那句，直接问了别的
- **不符合**：他照样把那句原样念了出来

### 2.4 有些问题是他现编的，不在题库里

- 练完之后到左边的「训练题库」页，找到刚才那道题，看它底下列的参考问句
- **符合**：考官问的问题里，**有至少一个不在这张单子上**，而且明显是接着你上一句话来的
- **不符合**：他问的每一句都能在单子上找到

（Part 3 这一条要求更高：真实考试里 Part 3 有相当一部分问题就是考官现编的。
如果你练的是 Part 3，看看 4–8 个问题里有几个不在单子上。）

### 2.5 红线一条都没破

- 他**没有**给你任何分数、分数段或等级（哪怕你直接问「我大概几分」，他也该拒绝并继续考）
- 他**没有**在考试中途纠正你（前提是设置里的「反馈时机」是**全程零反馈**；
  若你选了**当场点出**，则每答一句给一条中文短评是对的，不算破线）
- 他**没有**一口气抛两个问题
- 他**没有**提起你这次的复训目标（走「复训」路线时才有目标）

> **任何一条破了，都比 2.1–2.4 更严重。** 尤其是分数那一条：
> 本项目从头到尾不做雅思分数预测，考官当场说一句「这段大概 6.5」就等于破了这条底线。
> 记下他的原话，直接开新会话报这一条。

---

## 3. 结果写到哪

写进 `docs/examiner-improvisation-acceptance.md`（清单是清单，结果是结果，两份分开）。
骨架：

```markdown
# 考官临场发挥 · 验收结果
日期：
练的是哪道题：
反馈时机（全程零反馈 / 当场点出）：

2.1 一个话题问了几个：__ → 符合 / 不符合
2.2 覆盖了几个话题：__，全场共 __ 问 → 符合 / 不符合
2.3 已答到的问句跳过了吗 → 符合 / 不符合（不符合就抄他的原话：）
2.4 有几个问题不在单子上：__ → 符合 / 不符合
2.5 红线：分数 / 中途纠正 / 一次多问 / 提目标 → 各填 没破 / 破了（破了就抄原话：）
```

## 4. 这次不会碰你的真实数据

本次改动只动了发给 ChatGPT 的那段文字（`ExaminerPrompt`），
没有动题库、没有动 id、没有动 `~/Library/Application Support/IELTS Speaking Coach/` 里的任何文件。
你第 2 节这场练习本身会正常写入一条新的练习记录——那是你主动练的，跟改动无关。
