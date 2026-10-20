#!/usr/bin/env python3
"""工程 77 负向验证：逐条注入典型 bug，确认对应断言变红后自动还原。

用法：python3 tools/verify_77_negative.py [案例名]
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
DURABILITY = ROOT / "scripts/systems/durability.gd"
EQUIPMENT = ROOT / "scripts/systems/equipment.gd"
GAME_STATE = ROOT / "autoload/game_state.gd"
SAVE_MANAGER = ROOT / "autoload/save_manager.gd"
PANEL = ROOT / "scripts/ui/item_slot.gd"

CASES = [
    {
        "name": "N-1 损耗不分档（全部 -1）",
        "file": DURABILITY,
        "test": "DurabilityTest",
        "old": "return maxi(0, int((table as Dictionary).get(monster_kind, (table as Dictionary).get(\"normal\", 1))))",
        "new": "return 1",
    },
    {
        "name": "N-2 归零不掐 bonus()",
        "file": EQUIPMENT,
        "test": "DurabilityTest",
        "old": "\t\tif Durability.is_broken(it):\n\t\t\tcontinue",
        "new": "",
    },
    {
        "name": "N-3 归零时误掐套装",
        "file": ROOT / "scripts/systems/set_bonus.gd",
        "test": "DurabilityTest",
        "old": "\t\tif not (item is Dictionary):\n\t\t\tcontinue\n\t\tworn += 1",
        "new": "\t\tif not (item is Dictionary):\n\t\t\tcontinue\n\t\tif Durability.is_broken(item):\n\t\t\tcontinue\n\t\tworn += 1",
    },
    {
        "name": "N-4 _valid_item 把 durability 改必填",
        "file": SAVE_MANAGER,
        "test": "DurabilityTest",
        "old": "\t\tif item.has(\"durability\") and not _whole(item.get(\"durability\"), 0, 10000):\n\t\t\treturn false",
        "new": "\t\tif not item.has(\"durability\") or not _whole(item.get(\"durability\"), 0, 10000):\n\t\t\treturn false",
    },
    {
        "name": "N-5 修理不扣金币",
        "file": GAME_STATE,
        "test": "DurabilityTest",
        "old": "\tgold -= total",
        "new": "\tpass  # 负向注入：不扣金币",
    },
    {
        "name": "N-6 修理费比例算反（全价不按缺失比例）",
        "file": DURABILITY,
        "test": "DurabilityTest",
        "old": "return maxi(1, int(ceil(float(full) * float(missing) / float(max_durability()))))",
        "new": "return maxi(1, full)",
    },
    {
        "name": "N-7 删预警阈值",
        "file": GAME_STATE,
        "test": "DurabilityTest",
        "old": "\telif before > max_dur * 0.2 and after <= max_dur * 0.2 and after > 0 and not bool(warned.get(\"low\", false)):",
        "new": "\telif false and not bool(warned.get(\"low\", false)):",
    },
    {
        "name": "N-8 槽位细条不随耐久刷新",
        "file": PANEL,
        "test": "DurabilityTest",
        "old": "\t_durability_bar.visible = has_durability and Durability.current(item) < Durability.max_durability()",
        "new": "\t_durability_bar.visible = false",
    },
]


def run_case(case: dict) -> tuple[bool, str]:
    path: Path = case["file"]
    original = path.read_text(encoding="utf-8")
    if case["old"] not in original:
        return False, "注入点未找到（代码已变更，需更新脚本）"
    path.write_text(original.replace(case["old"], case["new"], 1), encoding="utf-8")
    try:
        result = subprocess.run(
            ["python3", "tools/run_isolated_tests.py", case["test"]],
            capture_output=True, text=True, timeout=240, cwd=ROOT,
        )
        output = result.stdout + result.stderr
        if "Compile Error" in output or "Parse Error" in output:
            return False, "编译失败（无效红，掩盖真实 bug 形态）"
        is_red = "FAIL" in output or "失败" in output
        summary = next((ln.strip() for ln in output.splitlines() if "PASS" in ln or "FAIL" in ln), "")
        return is_red, summary
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
        print(f"[{'RED ' if red else 'GREEN!'}] {case['name']}  ->  {summary}", flush=True)
    bad = [name for name, red, _ in results if not red]
    print()
    if bad:
        print(f"❌ 有 {len(bad)} 条负向没能变红：{bad}")
        return 1
    print(f"✅ 全部 {len(results)} 条负向都变红（已还原源码）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
