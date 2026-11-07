"""滚动统计工具。

这里只放 bisect 演示需要的一个函数。W2 会把它扩展成完整的模块并加上类型校验。
"""

from __future__ import annotations


def rolling_median(values: list[float], window: int) -> list[float]:
    """滚动中位数，用于去趋势（详见模块 A 教程 §4.3）。

    边界处用可用窗口（等价于 pandas 的 min_periods=1），不返回 NaN。

    参数:
        values: 输入序列
        window: 窗口大小，必须是正奇数，这样才有唯一的中心点

    返回:
        与 values 等长的中位数序列
    """
    if window <= 0 or window % 2 == 0:
        # fail fast：窗口必须是正奇数。偶数窗口没有唯一中心，
        # 而且这个错误不会在数值上表现得很明显，只会让结果悄悄地偏 —— 最难查的那类 bug
        raise ValueError(f"window 必须是正奇数，收到 {window}")

    n = len(values)
    half = window // 2
    out: list[float] = []

    for i in range(n):
        lo = max(0, i - half)
        hi = min(n, i + half + 1)  # ★ 正确版本：右边界是开区间，所以要 +1
        seg = sorted(values[lo:hi])
        out.append(seg[len(seg) // 2])

    return out
