#!/bin/bash
set -euo pipefail

# 编译 ielts-speaking-mcp、装到 ~/.local/bin，并给出 Codex 配置。
#
# 默认只打印配置，不动你的 ~/.codex/config.toml。
# 想让脚本直接写进去，加 --write（会先备份，且发现同名段落会拒绝覆盖）。
#
# 本脚本一行都不碰 ChatGPT（MCP 不依赖 ChatGPTBridge），跑它不会产生任何真实对话。
#
# 环境变量 IELTS_MCP_SOURCE_BIN：跳过编译，直接安装指定的可执行文件。
# 它有两个正经用途：把一份已经编译好的二进制装到另一台机器上不必再等一次 release 编译；
# 以及让 Tests/IELTSCoachMCPTests/InstallCodexPluginScriptTests.swift 能验证
# 「默认不写配置」「--write 的备份与拒绝覆盖」这几条——那几条与编译无关，
# 而让每条测试都跑一次 release 编译，只会让人再也不敢跑测试。
# 编译产物本身跑不跑得起来，由 scripts/mcp-smoke.sh 负责。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/ielts-speaking-mcp"
CONFIG="$HOME/.codex/config.toml"
SECTION="[mcp_servers.ielts_speaking]"
# 认「行首（可缩进）的段落头」，不认注释里顺嘴提到的同名段落。
# 认宽了的代价是用户被永远拒绝、而且拒绝理由是假的；
# 认窄了的代价是往配置里追加出一个重复的 TOML 表，Codex 直接读不下去——
# 所以只放过 # 开头的行，别的形状（带引号的键名之类）一律当成「已经有了」。
SECTION_PATTERN='^[[:space:]]*\[[[:space:]]*mcp_servers\.ielts_speaking[[:space:]]*\]'
WRITE=0

usage_error() {
    echo "❌ $1" >&2
    echo "   本脚本只接受一个可选参数：--write。" >&2
    echo "   下一步：不带参数运行，它只把配置打印出来给你自己粘贴（不会动 $CONFIG）；" >&2
    echo "   确实想让脚本代劳，运行：$0 --write" >&2
    exit 2
}

# 参数在动手之前就要校验完。把 --wirte 这种手误当成「没加 --write」默默走打印路径，
# 用户会以为已经写进配置了——那正是禁止的静默失败。
[ "$#" -le 1 ] || usage_error "参数太多了：$*"
case "${1:-}" in
    "") ;;
    --write) WRITE=1 ;;
    *) usage_error "不认识的参数：$1" ;;
esac

SOURCE="${IELTS_MCP_SOURCE_BIN:-}"
if [ -n "$SOURCE" ]; then
    echo "▶︎ 跳过编译，直接安装 IELTS_MCP_SOURCE_BIN 指定的文件：$SOURCE"
else
    echo "▶︎ 编译 release 版…"
    # 带 --package-path：不写的话，从别的目录调用本脚本会去编译当前目录那个包。
    swift build --package-path "$ROOT" -c release --product ielts-speaking-mcp
    SOURCE="$ROOT/.build/release/ielts-speaking-mcp"
fi

if [ ! -f "$SOURCE" ]; then
    echo "❌ 找不到要安装的可执行文件：$SOURCE" >&2
    echo "   下一步：先单独跑一次 swift build --package-path \"$ROOT\" -c release --product ielts-speaking-mcp，" >&2
    echo "   看编译是不是真的过了；若你设了 IELTS_MCP_SOURCE_BIN，请核对它指向的路径存不存在。" >&2
    exit 1
fi

echo "▶︎ 安装到 $BIN …"
mkdir -p "$BIN_DIR"
cp "$SOURCE" "$BIN"
chmod +x "$BIN"

SNIPPET="$SECTION
command = \"$BIN\"
args = []"

if [ "$WRITE" -eq 0 ]; then
    cat <<EOF

✅ 已安装：$BIN

下一步：把下面这段追加到 $CONFIG

$SNIPPET

追加完之后，用 codex mcp list（若你的 Codex 版本有这个子命令）确认它出现在列表里；
或者直接在 Codex 里问一句「列出可用的工具」。
键名与本机的 Codex 对不上时，先跑 codex mcp --help 看它认什么形状，
再照着改 codex/ielts-speaking-mcp.toml 与本脚本里的模板。
想让本脚本代劳，重新运行：$0 --write
EOF
    exit 0
fi

mkdir -p "$(dirname "$CONFIG")"
touch "$CONFIG"

if grep -qE "$SECTION_PATTERN" "$CONFIG"; then
    echo "ℹ️  $CONFIG 里已经有 $SECTION 段落了，本脚本不会去改它。"
    echo "   下一步：手动确认那一段的 command 指向 $BIN；若不是，自己改过来。"
    echo "   （不自动覆盖是刻意的：那是你的配置文件，里面可能还有别的服务器。）"
    exit 0
fi

BACKUP="$CONFIG.bak-$(date +%Y%m%d%H%M%S)"
cp "$CONFIG" "$BACKUP"
printf '\n%s\n' "$SNIPPET" >> "$CONFIG"

echo "✅ 已把配置追加到 $CONFIG"
echo "   原文件已备份为 $BACKUP"
echo "   下一步：重启 Codex，然后问它「列出可用的工具」，应当能看到 7 个 ielts 开头的工具。"
echo "   看不到的话，先跑 codex mcp --help 核实配置键名是不是这个形状（本脚本的模板未经本机验证）。"
