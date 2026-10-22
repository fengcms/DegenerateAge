"""临时负向验证：确认工程 90「重铸面板显示评分」的断言真的有牙。

N-1 基准失效（`_refresh_details` 每次先把 owner 清掉）—— 同形 bug：基准写进了被反复调用的
    刷新函数里 ⇒ 界面永远显示「与上次持平」。期望用例 3/4 变红。
N-2 评分口径分裂（`Equipment.score` 乘 1.5）—— 同形 bug：面板自己算一遍，与背包浮层对不上。
    期望用例 1（以及 2/3）变红。
N-3 评分只在选择时刷新（`_refresh_details` 不再调 `_refresh_score`）—— 同形 bug：重铸后数字不动。
    期望用例 1/2/3 变红。
N-4 撤掉内容滚动注入（`set_content_scroll`）—— 同形 bug：面板恢复成「内容多高就多高」，
    底部按钮出屏。期望用例 8 变红（**这条专门守 F-P2-3 的接线**）。

跑法：python3 tools/verify_90_score_negative.py
"""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PANEL = ROOT / "scripts/ui/reforge_panel.gd"
TEST = "ReforgeScoreTest"

BASE_BREAK = (
    "func _refresh_details() -> void:\n\tvar item := _selected_item()\n",
    "func _refresh_details() -> void:\n\t_score_base_owner = \"\"\n\tvar item := _selected_item()\n",
)
SCORE_BREAK = (
    "\tvar current := _rounded_score(Equipment.score(item))\n",
    "\tvar current := _rounded_score(Equipment.score(item) * 1.5)\n",
)
REFRESH_BREAK = (
    "\t_build_affix_rows(item)\n\t_refresh_score(item)\n",
    "\t_build_affix_rows(item)\n",
)
SCROLL_BREAK = (
    "\t_center.set_content_scroll(_scroll)\n",
    "",
)


def run() -> tuple[bool, str]:
    proc = subprocess.run(["python3", "tools/run_isolated_tests.py", TEST],
                          cwd=ROOT, capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    return proc.returncode == 0, out


def first_failure(out: str) -> str:
    """取测试自己 `push_error` 的断言正文 —— runner 的「未输出标记」是同一条根因的通用外壳，
    拿它当证据等于没验证「红的是哪条断言」。同一轮可能红多条，全部列出（去重）。"""
    lines = [line.strip() for line in out.splitlines()]
    errors = [line for line in lines
              if line.startswith("ERROR:") and "未输出成功完成标记" not in line
              and "caller thread" not in line]
    if errors:
        return " / ".join(list(dict.fromkeys(errors))[:4])[:400]
    for line in lines:
        if "FAIL" in line:
            return line[:160]
    return "(未捕获到失败行)"


def main() -> int:
    source = PANEL.read_text(encoding="utf-8")
    cases = [
        ("N-1 基准每次刷新被清空（永远「持平」）", BASE_BREAK),
        ("N-2 评分口径分裂（×1.5）", SCORE_BREAK),
        ("N-3 评分不在详情刷新（重铸后数字不动）", REFRESH_BREAK),
        ("N-4 撤掉内容滚动（面板顶穿）", SCROLL_BREAK),
    ]
    for label, (old, _new) in cases:
        assert old in source, f"注入点缺失：{label}"
    failures = 0
    try:
        for label, (old, new) in cases:
            # 🔴 每个用例前先还原：否则上一个补丁留在盘上，两个 bug 同时存在，
            # 第二次「变红」证明的不是想验的那条（工程 89 第一轮就踩过）。
            PANEL.write_text(source, encoding="utf-8")
            PANEL.write_text(source.replace(old, new, 1), encoding="utf-8")
            ok, out = run()
            print(f"{label}：{'❌ 仍绿（断言无效）' if ok else '✅ 变红'}")
            if ok:
                failures += 1
                continue
            print("    " + first_failure(out))
    finally:
        PANEL.write_text(source, encoding="utf-8")
    print("还原完成；负向全部有牙 ✅" if failures == 0 else "存在假绿 ⚠")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
