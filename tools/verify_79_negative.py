#!/usr/bin/env python3
"""工程 79 负向验证：逐条注入典型 bug，确认 ToolReclaimTest 对应断言变红后自动还原。

用法：python3 tools/verify_79_negative.py [案例名]
⚠ 本脚本会临时改写源码，必须与全量隔离集**串行**执行（工程 77 并发事故教训）。

注入原则（工程 08 §11.3）：注入形态必须与**真实 bug 同形**，且结果必须是断言失败；
凡是靠「写死常量 / 删一整段」让编译器先炸掉的，都是假红。
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL_RECLAIM = ROOT / "scripts/systems/tool_reclaim.gd"
SAVE_MANAGER = ROOT / "autoload/save_manager.gd"

CASES = [
    {
        "name": "N-1 丢掉 unlocks 条件（新档白送三件工具）",
        "file": TOOL_RECLAIM,
        "test": "ToolReclaimTest",
        "old": "\t\tif not bool(unlocks.get(item_id, false)):",
        "new": "\t\tif not bool(unlocks.get(item_id, true)):",
    },
    {
        "name": "N-2 删掉「已拥有不补」（重复刷闸门失效）",
        "file": TOOL_RECLAIM,
        "test": "ToolReclaimTest",
        "old": "\t\tif holds(inventory, item_id) or holds(warehouse, item_id):\n\t\t\tcontinue\n",
        "new": "",
    },
    {
        "name": "N-3 仓库兜底被复制成背包（Q2 回退，背包满就丢）",
        "file": TOOL_RECLAIM,
        "test": "ToolReclaimTest",
        "old": "\t\telif Inventory.add(warehouse, item):",
        "new": "\t\telif Inventory.add(inventory, item):",
    },
    {
        "name": "N-4 两处都满时静默丢弃（failed 不记）",
        "file": TOOL_RECLAIM,
        "test": "ToolReclaimTest",
        "old": "\t\telse:\n\t\t\tfailed.append(item_id)",
        "new": "\t\telse:\n\t\t\tpass  # 负向注入：静默丢弃",
    },
    {
        "name": "N-5 读档不调补领（自愈接线断开）",
        "file": SAVE_MANAGER,
        "test": "ToolReclaimTest",
        "old": "\t_set_reclaim_notice(ToolReclaim.reclaim_into_game())",
        "new": "\tpass  # 负向注入：读档不补领",
    },
    {
        "name": "N-6 提示不判空（三件齐全也弹补领提示）",
        "file": SAVE_MANAGER,
        "test": "ToolReclaimTest",
        "old": "\t_last_reclaim_notice = \"\"\n\t_last_reclaim_danger = false",
        "new": "\t_last_reclaim_notice = \"（负向注入）\"\n\t_last_reclaim_danger = false",
    },
    {
        "name": "N-7 判据漏掉一条工具（只补两件）",
        "file": TOOL_RECLAIM,
        "test": "ToolReclaimTest",
        "old": "\t\tvar item_id := String(entry.get(\"id\", \"\"))\n\t\tif not item_id.is_empty() and not out.has(item_id):",
        "new": "\t\tvar item_id := String(entry.get(\"id\", \"\"))\n\t\tif item_id == \"tool_boss_token\":\n\t\t\tcontinue\n\t\tif not item_id.is_empty() and not out.has(item_id):",
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
