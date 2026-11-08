"""rolling_median 的测试。

关键设计：尖峰必须放在序列【中间】。
放在末尾时右边界会被 min(n, ...) 截断，正确版和错误版给出相同结果 —— 测试形同虚设。
（这正是模块 A 教程 §3.4「死规则」那个坑的翻版）
"""

from __future__ import annotations

import pytest

from episode_tools.stats import rolling_median


def test_symmetric_window_median():
    """窗口=3，尖峰在中间：[3, 100, 5] 的中位数应该是 5。"""
    v = [1.0, 2.0, 3.0, 100.0, 5.0, 6.0, 7.0]
    got = rolling_median(v, window=3)
    assert got[3] == pytest.approx(5.0)


def test_window_covers_whole_series():
    """window=5、序列长度=5：只有正中间那个点用到了完整窗口。

    边界点用的是被截断的部分窗口，所以结果不等于全序列中位数 —— 这正是要断言的行为。
    """
    v = [5.0, 1.0, 9.0, 3.0, 7.0]
    got = rolling_median(v, window=5)
    assert got[2] == pytest.approx(5.0)  # 中间点：完整窗口 [1,3,5,7,9] 的中位数
    assert got == pytest.approx([5.0, 5.0, 5.0, 7.0, 7.0])


def test_boundary_uses_partial_window():
    """边界处不返回 NaN，用可用窗口（偶数长度时取上中位数）。"""
    v = [10.0, 20.0, 30.0]
    got = rolling_median(v, window=3)
    assert got[0] == pytest.approx(20.0)  # [10, 20] -> 上中位 20（右侧窗口延伸，不是只有 [10]）
    assert got[1] == pytest.approx(20.0)  # [10, 20, 30] -> 20
    assert got[2] == pytest.approx(30.0)  # [20, 30] -> 上中位 30


def test_even_window_rejected():
    with pytest.raises(ValueError, match="正奇数"):
        rolling_median([1.0, 2.0], window=4)
