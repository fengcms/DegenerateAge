#!/usr/bin/env python3
"""工程 101 负向验证：面板打开不阻断挂机的守门。

每条把修复**逐条回滚 / 改坏**，确认 `PanelAutoBattleTest` 真的变红后自动还原。
不仅要求「红」，还要求**红在预期的那条断言上** —— 否则可能是被别的原因带红的
（属于假绿）。任一案例不红或红错地方 = 该断言没有牙。

用法：python3 tools/verify_101_negative.py [案例名片段]
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUTO_BATTLE = ROOT / "scripts/systems/auto_battle.gd"
GROUND_ITEM = ROOT / "scripts/entities/ground_item.gd"
INVENTORY = ROOT / "scripts/ui/inventory_panel.gd"
TEST = "PanelAutoBattleTest"

CASES = [
    {
        "name": "N-1 挂机侧恢复「有面板就停战」（原 bug 形态）",
        "file": AUTO_BATTLE,
        "test": TEST,
        "old": "\tif get_tree().paused:",
        "new": (
            "\tif not GameState._open_panels.is_empty():\n"
            "\t\t_player.set_auto_move(Vector2.ZERO)\n"
            "\t\t_set_state(State.RECOVER, Localization.tr_key(\"ui.auto.npc_dialog\"))\n"
            "\t\treturn\n"
            "\tif get_tree().paused:"
        ),
        "expect": ["不切进「对话中暂停」"],
    },
    {
        "name": "N-2 拾取侧恢复「有面板就不捡」",
        "file": GROUND_ITEM,
        "test": TEST,
        "old": "\tif auto_claim and GameState.auto_pickup_on:",
        "new": "\tif auto_claim and GameState.auto_pickup_on and GameState._open_panels.is_empty():",
        "expect": ["面板打开时脚边掉落仍被自动拾取"],
    },
    {
        "name": "N-3 面板自己把挂机停掉（不是挂机侧的问题，行为层必须抓到）",
        "file": INVENTORY,
        "test": TEST,
        "old": "func set_open(open: bool) -> void:\n\tvisible = open",
        "new": "func set_open(open: bool) -> void:\n\tvisible = open\n\tif open:\n\t\tGameState.set_auto_battle(false)",
        "expect": ["挂机无任何推进"],
    },
    {
        "name": "N-4 删掉死亡分支（既有语义被波及）",
        "file": AUTO_BATTLE,
        "test": TEST,
        "old": "\tif _player.is_dead:",
        "new": "\tif false and _player.is_dead:",
        "expect": ["死亡仍会自动关闭挂机"],
    },
]


def run_case(case: dict) -> tuple[bool, str]:
    """返回 (是否红在预期断言上, 摘要)。"""
    path: Path = case["file"]
    original = path.read_text(encoding="utf-8")
    if case["old"] not in original:
        return False, "注入点未找到（源码已变更，需更新脚本）"
    path.write_text(original.replace(case["old"], case["new"], 1), encoding="utf-8")
    try:
        result = subprocess.run(
            [sys.executable, "tools/run_isolated_tests.py", case["test"]],
            capture_output=True, text=True, timeout=600, cwd=ROOT,
        )
        output = result.stdout + result.stderr
        if "Compile Error" in output or "Parse Error" in output:
            return False, "编译失败（无效红，掩盖真实 bug 形态）"
        is_red = "FAIL" in output or "SCRIPT ERROR" in output
        if not is_red:
            return False, "仍然全绿（这颗牙不存在）"
        missing = [kw for kw in case["expect"] if kw not in output]
        if missing:
            head = next(
                (ln.strip() for ln in output.splitlines() if "FAIL:" in ln), "<无失败行>")
            return False, f"红错地方（缺预期文案 {missing}）：{head[:120]}"
        return True, "红在预期断言：" + " / ".join(case["expect"])
    finally:
        path.write_text(original, encoding="utf-8")


def main() -> int:
    filter_name = sys.argv[1] if len(sys.argv) > 1 else None
    results = []
    for case in CASES:
        if filter_name and filter_name not in case["name"]:
            continue
        red, summary = run_case(case)
        results.append((case["name"], red, summary))
        print(f"[{'RED ' if red else 'BAD!'}] {case['name']}  ->  {summary}", flush=True)
    bad = [name for name, red, _ in results if not red]
    print()
    if bad:
        print(f"❌ 有 {len(bad)} 条负向没能红在对的断言上：{bad}")
        return 1
    print(f"✅ 全部 {len(results)} 条负向都红在预期断言上（已还原源码）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
