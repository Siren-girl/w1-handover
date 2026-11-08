#!/usr/bin/env bash
# scripts/demo_long_task.sh —— 演示"必须在 tmux 里跑的长任务"
#
# 用法：
#   tmux new -s ingest
#   ./scripts/demo_long_task.sh data/raw data/out/report.txt
#   （然后按 Ctrl+b d 脱离，任务继续跑）
#
# 设计要点：
#   1. 不在 tmux 里就直接拒绝执行 —— 强制养成习惯，避免"跑了两小时才发现断了"
#   2. 输出同时上屏和落盘 —— tmux 的 scrollback 有上限，几小时的日志会被冲掉
#   3. 每处理一批就打一行带时间戳的进度 —— attach 回来能立刻知道跑到哪了
set -euo pipefail
#  -e 任何命令失败就退出（不要让错误静默传下去）
#  -u 用了未定义的变量就报错（拼错变量名是最常见的 shell bug）
#  -o pipefail 管道里任何一环失败，整个管道算失败（默认只看最后一环）

IN_DIR="${1:?用法: demo_long_task.sh <输入目录> <输出文件>}"
OUT_FILE="${2:?缺少第二个参数：输出文件路径}"
LOG_DIR="logs"
LOG_FILE="$LOG_DIR/$(date +%Y%m%d_%H%M%S)_long_task.log"

# ★ 检查 1：必须在 tmux 里
# tmux 会给它启动的 shell 设置 TMUX 环境变量，这是最可靠的判断依据
if [[ -z "${TMUX:-}" ]]; then
  echo "错误：当前不在 tmux 会话里。" >&2
  echo "SSH 一断（网络波动 / 合上笔记本 / 电脑休眠），这个任务就会被 SIGHUP 杀掉。" >&2
  echo "" >&2
  echo "正确用法：" >&2
  echo "  tmux new -s ingest" >&2
  echo "  $0 $IN_DIR $OUT_FILE" >&2
  echo "  # 按 Ctrl+b 然后 d 脱离，之后 tmux attach -t ingest 回来" >&2
  exit 1
fi

# ★ 检查 2：输入目录必须存在，且不为空
if [[ ! -d "$IN_DIR" ]]; then
  echo "错误：输入目录不存在: $IN_DIR" >&2
  exit 1
fi

mkdir -p "$LOG_DIR" "$(dirname "$OUT_FILE")"

# ★ 输出同时上屏 + 落盘
# 用 exec 重定向整个脚本的 stdout/stderr，比在每条命令后面加 2>&1 | tee 干净
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date -Is)] $*"; }

log "=== 任务开始 ==="
log "PID=$$  TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo unknown)"
log "输入目录=$IN_DIR  输出=$OUT_FILE  日志=$LOG_FILE"

# 收集要处理的文件（用 \0 分隔，防止文件名里有空格）
# ★ 不用 mapfile —— 它是 bash 4.0 的内置命令，macOS 自带 /bin/bash 停在 3.2.57。
#   while read -d '' 在 bash 3.2 就能跑，Ubuntu 上也没问题。
FILES=()
while IFS= read -r -d '' f; do
  FILES+=("$f")
done < <(find "$IN_DIR" -type f \( -name '*.csv' -o -name '*.parquet' \) -print0 | sort -z)
TOTAL=${#FILES[@]}
log "待处理文件数: $TOTAL"

if [[ "$TOTAL" -eq 0 ]]; then
  log "警告：没有找到任何 .csv / .parquet 文件，任务无意义，退出"
  exit 1
fi

# 真正干活
i=0
: > "$OUT_FILE"                       # 清空输出文件
for f in "${FILES[@]}"; do
  i=$((i + 1))
  size=$(wc -c < "$f")                # 字节数。★ 不用 stat -c（GNU）/ stat -f %z（BSD）
                                      #   两家的参数完全不同，wc -c 两边一样
  lines=$(wc -l < "$f" 2>/dev/null || echo 0)
  printf '%s\t%s\t%s\n' "$f" "$size" "$lines" >> "$OUT_FILE"

  # 每 10 个文件打一次进度，不要每个都打（几万个文件会把日志刷爆）
  # ★ 百分比用纯 bash 整数算（先乘 1000 再拆成一位小数）。不要用
  #   $(awk "BEGIN{printf ...}") —— bash 3.2 解析 "$()" 里的花括号有 bug，大括号被吃掉，
  #   awk 收到 `BEGIN 10*100/31` 报语法错误，百分比静默变成空括号：进度 10/31 (%)
  if (( i % 10 == 0 )) || (( i == TOTAL )); then
    p=$(( i * 1000 / TOTAL ))
    log "进度 $i/$TOTAL ($((p / 10)).$((p % 10))%)"
  fi

  sleep 0.2                           # 演示用：模拟真实处理耗时。实际项目删掉
done

log "=== 任务完成，报告写入 $OUT_FILE ==="
log "总行数: $(wc -l < "$OUT_FILE")  日志: $LOG_FILE"
