#!/usr/bin/env bash
# scripts/gen_history.sh —— 在【一个全新的临时仓库】里造一段用于 bisect 演示的历史。
# ★ 这个脚本会创建 ~/work/bisect-demo 目录。它不是 w1-handover 仓库的一部分，
#   只是用来生成 README 里那段 bisect 记录的素材。跑完可以把目录留着当练习场。
set -euo pipefail

DEMO_DIR="${1:-$HOME/work/bisect-demo}"

if [[ -e "$DEMO_DIR" ]]; then
  echo "错误：$DEMO_DIR 已存在。换个路径或先删掉它。" >&2
  exit 1
fi

mkdir -p "$DEMO_DIR/src/episode_tools" "$DEMO_DIR/scripts"
cd "$DEMO_DIR"
git init -b main -q
git config user.name  "Zhang San"
git config user.email "zhangsan@example.com"

write_stats() {           # 用函数复用写文件的逻辑
  cat > src/episode_tools/stats.py
  touch src/episode_tools/__init__.py
}

# ---- ★ 判据脚本必须【第一个】提交 ----
# git bisect run 会把工作区切到区间内的每一个提交上再执行判据脚本。
# 如果脚本是在 bug 之后才提交的，那么在更早的提交里它根本不存在，
# ./scripts/check_window_bug.sh 会以 127 退出（命令找不到），被 bisect 当成 bad —— 整个二分就废了。
# 所以判据脚本要在 v1.0.0 之前就进仓库，保证区间内每个提交都有它。
cat > scripts/check_window_bug.sh <<'SH'
#!/usr/bin/env bash
# git bisect run 的判据：退出码 0=good, 1=bad, 125=skip
set -uo pipefail        # 故意不加 -e，我们要自己控制退出码

python3 -c "import sys; sys.path.insert(0, 'src'); import episode_tools.stats" 2>/dev/null || {
  echo "SKIP: 模块尚不存在"; exit 125; }

PYTHONPATH=src python3 - <<'PY'
import sys
from episode_tools.stats import rolling_median

v = [1.0, 2.0, 3.0, 100.0, 5.0, 6.0, 7.0]
got = rolling_median(v, window=3)[3]
if abs(got - 5.0) < 1e-9:
    print(f"GOOD: median={got}")
    sys.exit(0)
print(f"BAD: median={got}, expected 5.0")
sys.exit(1)
PY
SH
chmod +x scripts/check_window_bug.sh
git add -A && git commit -qm "test(stats): 增加 bisect 判据脚本"

# ---- v1.0.0：正确版本 ----
write_stats <<'PY'
from __future__ import annotations


def rolling_median(values: list[float], window: int) -> list[float]:
    n = len(values)
    half = window // 2
    out: list[float] = []
    for i in range(n):
        lo = max(0, i - half)
        hi = min(n, i + half + 1)
        seg = sorted(values[lo:hi])
        out.append(seg[len(seg) // 2])
    return out
PY
git add -A && git commit -qm "feat(stats): 实现滚动中位数用于去趋势"
git tag v1.0.0

# ---- 中间填充若干次无关提交，让二分有意义（不然两步就找到了）----
for i in $(seq 1 12); do
  echo "# note $i" >> README.md
  git add -A && git commit -qm "docs(readme): 补充说明 $i"
done

# ---- ★ 引入 bug 的那次提交（伪装成一个性能优化）----
write_stats <<'PY'
from __future__ import annotations


def rolling_median(values: list[float], window: int) -> list[float]:
    n = len(values)
    half = window // 2
    out: list[float] = []
    for i in range(n):
        lo = max(0, i - half)
        hi = min(n, i + half)          # BUG: 少了 +1，窗口不对称
        seg = sorted(values[lo:hi])
        out.append(seg[len(seg) // 2] if seg else values[i])
    return out
PY
git add -A && git commit -qm "perf(stats): 用切片边界替代额外的长度计算"

# ---- 之后又叠了若干提交，bug 被埋得更深 ----
for i in $(seq 13 31); do
  echo "# note $i" >> README.md
  git add -A && git commit -qm "docs(readme): 补充说明 $i"
done

echo ""
echo "✓ 演示仓库已生成: $DEMO_DIR"
echo "  共 $(git rev-list --count HEAD) 个提交，tag v1.0.0 是已知良好版本"
echo ""
echo "现在跑 bisect："
echo "  cd $DEMO_DIR"
echo "  git bisect start HEAD v1.0.0"
echo "  git bisect run ./scripts/check_window_bug.sh"
echo "  git bisect log > /tmp/bisect.log    # ★ 保存过程，写进 README"
echo "  git bisect reset"
