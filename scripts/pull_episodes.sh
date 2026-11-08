#!/usr/bin/env bash
# scripts/pull_episodes.sh —— 从采集机同步指定日期的 episode 数据
#
# 用法：
#   ./scripts/pull_episodes.sh                    # 同步今天，演练模式（不真传）
#   ./scripts/pull_episodes.sh 20261107           # 同步指定日期，演练
#   APPLY=1 ./scripts/pull_episodes.sh 20261107   # ★ 真的执行
#
# ★ 日期参数要和远端目录名【逐字符一致】。默认格式是 %Y%m%d（20261107，无横线），
#   写成 2026-11-07 也能跑，但那边目录就得叫这个名字，否则表现为「同步成功但 0 个文件」
#
# 设计要点：
#   1. 默认 dry-run。rsync --delete 配错路径会毁数据，必须先看一遍要干什么（§2.8）
#   2. 全部参数走环境变量，不硬编码（§1 的分析脚本 vs 生产代码）
#   3. 限速，不占满采集基地的共享上行带宽
#   4. 建议在 tmux 里跑（几百 GB 要几小时）
#   5. 跑之前 ssh 探测源目录存在，否则 rsync 会「成功」创建一个空目录
#   6. --max-delete 给删除量设上限，--partial-dir 把半成品挪出正式目录
set -euo pipefail

# ---- 配置：全部可被环境变量覆盖，代码里只有默认值 ----
REMOTE_HOST="${REMOTE_HOST:-collect-01}"       # ~/.ssh/config 里的别名
REMOTE_ROOT="${REMOTE_ROOT:-/data/episodes}"
LOCAL_ROOT="${LOCAL_ROOT:-$HOME/data/episodes}"
BW_LIMIT="${BW_LIMIT:-80M}"                    # 限速 80 MB/s；设 0 表示不限速
MAX_DELETE="${MAX_DELETE:-500}"                # ★ 镜像同步最多允许删多少个，见下面实验 C
REMOTE_RSYNC="${REMOTE_RSYNC:-rsync}"          # ★ 远端用哪个 rsync 二进制，见 §8.6.1 ③.6
APPLY="${APPLY:-0}"                            # 0=演练, 1=执行
DATE_TAG="${1:-$(date +%Y%m%d)}"               # ★ 默认是 20261107 这种无横线格式，
                                               #   目录名要按这个来建，别混用两种写法

SRC="$REMOTE_HOST:$REMOTE_ROOT/$DATE_TAG/"     # ★ 结尾的 / 表示"目录里的内容"（§2.8）
DST="$LOCAL_ROOT/$DATE_TAG/"

# ---- 前置检查 ----
command -v rsync >/dev/null || { echo "错误：没装 rsync（macOS: brew install rsync / Ubuntu: apt install rsync）" >&2; exit 1; }

# 探测分两步：先确认「连得上」，再确认「目录在」。
# ★ 不要合成一步：合成一步的话报错同时指向两个原因，排查时会白跑一圈（§8.6.1 ③）
if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_HOST" true; then
  echo "错误：连不上 $REMOTE_HOST —— 是 ssh 的问题，跟数据目录无关" >&2
  echo "      检查：~/.ssh/config 里有这个 Host 吗？免密配了吗？（ssh -v $REMOTE_HOST true 看细节）" >&2
  exit 1
fi

# 连得上，再看源目录 —— 否则 rsync 会创建一个空目录，看起来像"同步成功但没数据"
if ! ssh -o BatchMode=yes "$REMOTE_HOST" "test -d '$REMOTE_ROOT/$DATE_TAG'"; then
  echo "错误：能连上 $REMOTE_HOST，但源目录不存在：$REMOTE_ROOT/$DATE_TAG" >&2
  echo "      当前 REMOTE_ROOT=$REMOTE_ROOT  DATE_TAG=$DATE_TAG" >&2
  # ★ 这里用 find 而不是 ls '$REMOTE_ROOT'/*：远端登录 shell 可能是 zsh，
  #   通配符匹配不到时 zsh 会直接报 "no matches found" 并中止整条命令，2>/dev/null 都拦不住
  #   （bash 是把 * 原样交给 ls，由 ls 报错）。跨机器执行的命令不要依赖对端 shell 的方言
  ssh -o BatchMode=yes "$REMOTE_HOST" \
    "test -d '$REMOTE_ROOT' && find '$REMOTE_ROOT' -mindepth 1 -maxdepth 1 | head -5 || echo '（远端连 $REMOTE_ROOT 这一层都不存在，多半是 \$HOME 没展开）'" >&2
  exit 1
fi

mkdir -p "$DST"

# ---- 组装 rsync 参数 ----
RSYNC_OPTS=(
  -a                                  # 保留权限/时间戳/软链接
  -h                                  # 人类可读的数字
  --rsync-path="$REMOTE_RSYNC"        # ★ 指定【远端】跑哪个 rsync，见 §8.6.1 ③.6
  --partial --partial-dir=.rsync-partial   # 断点续传，半成品放隐藏目录
  "--info=progress2,stats2"         # ★ 带英文逗号的参数必须加引号，否则 shellcheck 报 SC2054，见 §8.6.1 ③.5
  --exclude='*.tmp'
  --exclude='.DS_Store'
  --exclude='__pycache__/'
  --exclude='.rsync-partial/'
)

if [[ "$BW_LIMIT" != "0" ]]; then
  RSYNC_OPTS+=(--bwlimit="$BW_LIMIT")
fi

if [[ "$APPLY" != "1" ]]; then
  RSYNC_OPTS+=(--dry-run --itemize-changes)   # -i 显示每个文件要做什么
  echo "=============================================="
  echo "  演练模式（不会真的传输任何数据）"
  echo "  确认无误后执行: APPLY=1 $0 $DATE_TAG"
  echo "=============================================="
else
  RSYNC_OPTS+=(--delete --max-delete="$MAX_DELETE")   # ★ 只在真执行时开镜像同步，并限制删除数量
  if [[ -z "${TMUX:-}" ]]; then
    echo "提示：当前不在 tmux 里。大数据量同步建议先 tmux new -s sync" >&2
  fi
fi

echo "源:   $SRC"
echo "目标: $DST"
echo "限速: $BW_LIMIT"
echo "删除上限: $MAX_DELETE"
echo ""

mkdir -p logs
LOG="logs/rsync_${DATE_TAG}_$(date +%H%M%S).log"

# 2>&1 | tee 让输出同时上屏和落盘（§2.8）
rsync "${RSYNC_OPTS[@]}" "$SRC" "$DST" 2>&1 | tee "$LOG"

echo ""
echo "日志: $LOG"
