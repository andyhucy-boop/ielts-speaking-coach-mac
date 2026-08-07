#!/bin/bash
set -euo pipefail

# MCP stdio 冒烟测试：把几条真实消息喂给真实的可执行文件。
#
# 单元测试测的是 MCPServer.handle(line:)；这里测的是单元测试碰不到的那几段——
# 进程真的起得来、真的从 stdin 读、真的往 stdout 写、坏消息之后还活着、
# 读到 EOF 会自己退出、stdout 里没有混进日志。对译上游 mcp/test-client.mjs（spec 第 8 节）。
#
# 数据目录指向临时目录：**绝不动用户真实的训练记录。**
# 本脚本一行都不碰 ChatGPT（MCP 不依赖 ChatGPTBridge），跑它不会产生任何真实对话。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.build/debug/ielts-speaking-mcp"
# 进程读完 stdin 之后必须自己退出。留一个上限是因为「一直等下去」本身就是缺陷形态之一
# （禁止无限等待）：超时了要报出来，而不是让人对着不动的终端猜。
TIMEOUT_SECONDS=30

echo "▶︎ 编译…"
swift build --package-path "$ROOT" --product ielts-speaking-mcp

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export IELTS_SPEAKING_DATA_DIR="$WORK/data"

cat > "$WORK/in.jsonl" <<'JSONL'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"initialize_ielts_workspace","arguments":{}}}
{"jsonrpc":"2.0","id":5,"method":"resources/list"}
JSONL

# fail 定义在真正跑之前：跑的过程里就可能要用它，定义在后面等于那一段没有报错手段。
fail() {
    echo "❌ $1"
    echo "--- stdout ---"; cat "$WORK/out.jsonl" 2>/dev/null || true
    echo "--- stderr ---"; cat "$WORK/err.log" 2>/dev/null || true
    exit 1
}

echo "▶︎ 喂给 $BIN …"
: > "$WORK/out.jsonl"
: > "$WORK/err.log"
"$BIN" < "$WORK/in.jsonl" > "$WORK/out.jsonl" 2> "$WORK/err.log" &
pid=$!

waited=0
while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$TIMEOUT_SECONDS" ]; then
        kill -9 "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        fail "stdin 已经喂完 ${TIMEOUT_SECONDS} 秒了，进程还没退出，已强制结束它。下一步：检查 Sources/ielts-speaking-mcp/main.swift 的读取循环——readLine 返回 nil（stdin 关闭）时必须跳出循环让进程结束，否则 Codex 关掉连接之后进程会一直赖着不走。"
    fi
    sleep 1
    waited=$((waited + 1))
done

status=0
wait "$pid" || status=$?
[ "$status" -eq 0 ] || fail "可执行文件以退出码 $status 结束（读完 stdin 之后应当正常退出，退出码 0）。下一步：先看下面 stderr 里的报错，修掉启动阶段的问题再重跑本脚本。"

# 6 条输入里有 1 条是通知（不该有响应），所以应当正好 5 行。
lines=$(wc -l < "$WORK/out.jsonl" | tr -d ' ')
[ "$lines" = "5" ] || fail "期望 5 行响应（通知不回），实际 $lines 行。下一步：确认 main.swift 只往 stdout 写协议响应——日志、进度、提示一律走 stderr。"

for tool in initialize_ielts_workspace open_dashboard set_training_selection \
            get_training_context save_session_review list_practice_history get_dashboard_data; do
    grep -q "\"$tool\"" "$WORK/out.jsonl" || fail "tools/list 的结果里没有 $tool。下一步：检查 Sources/IELTSCoachMCP/ToolCatalog.swift 里 7 个工具是否都装配上了。"
done

grep -q -- '-32700' "$WORK/out.jsonl" || fail "半截 JSON 没有换来 -32700 解析错误。下一步：检查 MCPServer.handle(line:) 对解析失败的分支，坏消息必须回一条错误而不是被丢掉。"
grep -q -- '-32601' "$WORK/out.jsonl" || fail "未知方法 resources/list 没有换来 -32601。下一步：检查 MCPServer 的方法分发，未实现的方法要明确报 -32601，不能假装支持。"
[ -f "$WORK/data/state.json" ] || fail "initialize_ielts_workspace 没有把 state.json 建出来。下一步：确认可执行文件用的是 DataDirectory.resolve()（它会读环境变量 IELTS_SPEAKING_DATA_DIR）。"

# stdout 里不许混进任何不是 JSON 的行——混进一行日志，客户端就废了。
if command -v python3 >/dev/null 2>&1; then
    while IFS= read -r line; do
        printf '%s' "$line" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' \
            >/dev/null 2>&1 || fail "stdout 里有不是 JSON 的行：$line。下一步：把这行内容改写到 stderr——stdout 只许出现协议消息。"
    done < "$WORK/out.jsonl"
else
    echo "ℹ️  本机没有 python3，跳过「每行都是合法 JSON」这一项逐行校验。"
    echo "   下一步：想补上这项检查，装好 Xcode 命令行工具后重跑本脚本。"
fi

# 日志必须走 stderr，而且必须真的有——一句都没有说明启动信息也被吞了。
grep -q "ielts-speaking-mcp" "$WORK/err.log" || fail "stderr 里没有启动日志。下一步：在 main.swift 启动时往 stderr 写一行含版本与数据目录的日志，出问题时它是唯一的线索。"

echo "✅ MCP stdio 冒烟测试通过：5 条响应、7 个工具齐全、坏消息之后仍存活、读到 EOF 自行退出、stdout 干净。"
