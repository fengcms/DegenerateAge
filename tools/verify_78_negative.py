#!/usr/bin/env python3
"""工程 78 负向验证：逐条注入典型 bug，确认 TooltipStyleTest 对应断言变红后自动还原。

用法：python3 tools/verify_78_negative.py [案例名]
⚠ 本脚本会临时改写源码，必须与全量隔离集**串行**执行（工程 77 并发事故教训）。
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ITEM_SLOT = ROOT / "scripts/ui/item_slot.gd"
SETTINGS = ROOT / "scripts/systems/settings_runtime.gd"

CASES = [
    {
        "name": "N-1 门卫收窄：人物装备槽退回原生",
        "file": ITEM_SLOT,
        "test": "TooltipStyleTest",
        "old": "\tif item.is_empty():\n\t\treturn null",
        "new": "\tif item.is_empty() or role == ROLE_EQUIP:\n\t\treturn null",
    },
    {
        "name": "N-2 外壳回潮半透明",
        "file": SETTINGS,
        "test": "TooltipStyleTest",
        "old": "\tstyle.bg_color = Color(\"111820\")",
        "new": "\tstyle.bg_color = Color(0, 0, 0, 0.4)",
    },
    {
        "name": "N-3 评分行不进单卡（Q3 回退）",
        "file": ITEM_SLOT,
        "test": "TooltipStyleTest",
        "old": "\t\tlines.append(Localization.tr_key(\"ui.equip_tip.score\", [Equipment.score(shown)]))",
        "new": "\t\tpass  # 负向注入：评分被删",
    },
    {
        "name": "N-4 空槽也弹结构化大卡（空槽短路被删）",
        "file": ITEM_SLOT,
        "test": "TooltipStyleTest",
        "old": "\tif item.is_empty():\n\t\treturn null\n",
        "new": "",
    },
    {
        "name": "N-5 文案卡改写面板文案",
        "file": ITEM_SLOT,
        "test": "TooltipStyleTest",
        "old": "\tdetail.text = text\n\tcolumn.add_child(detail)\n\treturn panel",
        "new": "\tdetail.text = \"（负向注入）\"\n\tcolumn.add_child(detail)\n\treturn panel",
    },
    {
        "name": "N-6 托盘装备丢掉售价行（tooltip_as_text 失效）",
        "file": ITEM_SLOT,
        "test": "TooltipStyleTest",
        "old": "\tif kind == \"equip\" and not tooltip_as_text:",
        "new": "\tif kind == \"equip\":",
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
