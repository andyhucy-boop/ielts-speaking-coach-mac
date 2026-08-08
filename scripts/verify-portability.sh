#!/bin/bash
set -euo pipefail

# 验证「把数据目录拷到另一台电脑就能接着用」（成品标准第 10 条）。
#
# 关键设计有三处，缺任何一处这个验证都是假的：
#   1. 拷完之后把「原来那台机器」的目录整个删掉。不删的话，就算代码里存的是
#      绝对路径也能读到原目录，验证照样通过——而真换机器时那些路径根本不存在。
#   2. 必须带一个负例（故意存绝对路径的数据目录），断言检查一定要报错。
#      没有负例的话，一个永远返回「没问题」的实现也能让这个脚本全绿。
#   3. 负例必须有两个，而且第二个的文件要真的在。原因是实测出来的：
#      `DataPortabilityAudit` 有两组规则——「路径写法」（绝对 / ~ / file:// / ..）
#      和「文件在不在」。负例 1 那个指到目录外的绝对路径，两组规则**都**会揪出来，
#      所以它只能证明「至少有一组还活着」。把整个 `audit(state:)`（写法那一组）
#      挖成 `return []`，负例 1 照样被「文件找不到」拦下，脚本还是全绿——
#      写法规则等于一条都没被守住。负例 2 用 `reports/../reports/s1.json`：
#      写法明明是坏的，但 POSIX 会把 `..` 解开，文件确实存在，
#      于是**只有写法那一组规则能揪出它**。这一条是这个脚本里唯一守住写法规则的断言。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COACH="$ROOT/.build/debug/coach"

if [[ ! -x "$COACH" ]]; then
    echo "❌ 找不到 $COACH"
    echo "   下一步：先跑 swift build，再跑这个脚本。"
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# $1 = 目录，$2 = 写进 reportPath 的内容
make_fixture() {
    local dir="$1" report_path="$2"
    mkdir -p "$dir/reports" "$dir/recordings"
    printf '{"must_correct":[]}' > "$dir/reports/s1.json"
    printf 'fake-audio'          > "$dir/recordings/s1.m4a"
    cat > "$dir/state.json" <<STATE
{
  "schemaVersion": 3,
  "learner": { "displayName": "", "createdAt": "2026-08-06T00:00:00Z" },
  "currentSession": null,
  "sessions": [
    {
      "id": "s1",
      "questionId": "q1",
      "focusPart": "Part 1",
      "startedAt": "2026-08-06T00:00:00Z",
      "endedAt": "2026-08-06T00:10:00Z",
      "goal": "",
      "transcript": [],
      "reportPath": "$report_path",
      "recordingPath": "recordings/s1.m4a"
    }
  ],
  "targets": [],
  "issues": [],
  "vocabulary": [],
  "plan": null,
  "questions": [
    { "id": "q1", "part": 1, "topic": "Home", "prompt": "Do you live in a house or a flat?" }
  ],
  "questionSources": [],
  "settings": { "recordingEnabled": false, "recordingConsentAt": "" },
  "questionCursor": { "part1": 0, "part2": 0, "part3": 0 }
}
STATE
}

echo "▶︎ 正例：造一份全用相对路径的数据目录…"
ORIGINAL="$WORK/machine-a"
COPY="$WORK/machine-b"
make_fixture "$ORIGINAL" "reports/s1.json"

echo "▶︎ 拷到「另一台电脑」，然后把原来那台整个删掉…"
cp -R "$ORIGINAL" "$COPY"
rm -rf "$ORIGINAL"

echo "▶︎ 在「另一台电脑」上检查…"
if ! IELTS_SPEAKING_DATA_DIR="$COPY" "$COACH" portability; then
    echo "❌ 拷过去之后检查没通过。"
    echo "   发生了什么：数据目录里有依赖原机器的东西，换电脑就断。"
    echo "   下一步：看上面每一条给出的位置与提示，逐条修写入这些字段的代码。"
    exit 1
fi

echo "▶︎ 确认题库真的读得到…"
if ! IELTS_SPEAKING_DATA_DIR="$COPY" "$COACH" questions list | grep -qF "[q1]"; then
    echo "❌ 拷过去之后读不到题库。"
    echo "   下一步：确认 state.json 跟着拷过来了，且 DataDirectory.resolve() 认 IELTS_SPEAKING_DATA_DIR。"
    exit 1
fi

echo "▶︎ 确认复盘文件真的跟过来了…"
if [[ ! -f "$COPY/reports/s1.json" ]]; then
    echo "❌ reports/ 没跟着过来。下一步：检查这个脚本的 cp -R 是不是漏了子目录。"
    exit 1
fi

echo
echo "▶︎ 负例 1：造一份故意存绝对路径的数据目录，检查必须把它揪出来…"
BAD="$WORK/machine-bad"
make_fixture "$BAD" "$WORK/somewhere-else/reports/s1.json"
if IELTS_SPEAKING_DATA_DIR="$BAD" "$COACH" portability > "$WORK/bad.log" 2>&1; then
    echo "❌ 负例 1 没有被检出。"
    echo "   发生了什么：数据目录里存着绝对路径，检查却说「没问题」——"
    echo "   这说明上面那个正例的绿灯毫无意义，它对任何实现都会亮。"
    echo "   下一步：检查 DataPortabilityAudit.audit 是不是被改成了永远返回空。"
    cat "$WORK/bad.log"
    exit 1
fi
if ! grep -q "下一步" "$WORK/bad.log"; then
    echo "❌ 负例 1 报出来了，但没告诉用户下一步做什么。"
    cat "$WORK/bad.log"
    exit 1
fi

echo "▶︎ 负例 2：路径写法是坏的，但文件真的在——只有「看写法」那组规则能揪出它…"
# reports/../reports/s1.json 指到的就是 reports/s1.json 本身，文件确实存在，
# 所以「文件在不在」那组规则对它一声不吭。见文件开头第 3 条。
BAD2="$WORK/machine-bad-2"
make_fixture "$BAD2" "reports/../reports/s1.json"
if IELTS_SPEAKING_DATA_DIR="$BAD2" "$COACH" portability > "$WORK/bad2.log" 2>&1; then
    echo "❌ 负例 2 没有被检出。"
    echo "   发生了什么：路径里有 .. ，指到了数据目录外面再绕回来，"
    echo "   拷贝数据目录时这种路径不保证还成立，而检查却说「没问题」。"
    echo "   这条是唯一守住「路径写法」那组规则的断言——它一绿，"
    echo "   绝对路径 / ~ / file:// / .. 四条规则就等于全没人守（负例 1 会被"
    echo "   「文件找不到」那组规则顶掉，看不出写法规则已经死了）。"
    echo "   下一步：检查 DataPortabilityAudit.audit(state:) 是不是被改成了永远返回空，"
    echo "   或者 checkRelativePath 里那四条判断被删掉了。"
    cat "$WORK/bad2.log"
    exit 1
fi
if ! grep -q "下一步" "$WORK/bad2.log"; then
    echo "❌ 负例 2 报出来了，但没告诉用户下一步做什么。"
    cat "$WORK/bad2.log"
    exit 1
fi

echo
echo "✅ 数据目录可以整个拷到另一台电脑接着用（成品标准第 10 条）。"
echo "   正例：删掉原目录后仍然读得到题库与复盘。"
echo "   负例 1：存了绝对路径的目录被正确揪出，并给出了下一步。"
echo "   负例 2：写法坏但文件在的路径也被揪出——「看写法」那组规则确实还活着。"
