#!/usr/bin/env python3
"""工程 99 负向验证：破损件（耐久 0）快速出售修复的守门。

每条把修复**逐条回滚**，确认对应断言变红后自动还原。任一案例没红 = 该断言没有牙。

用法：python3 tools/verify_99_negative.py [案例名]
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "scripts/systems/sell_gear_policy.gd"
PREVIEW = ROOT / "scripts/ui/equipment_sale_preview.gd"
LOCALIZATION = ROOT / "data/localization.json"

CASES = [
    {
        "name": "N-1 破损件退回「一律不勾」（原 bug 形态）",
        "file": POLICY,
        "test": "SellGearPolicyTest",
        "old": "\tvar automatic := blocking_reasons(reasons).is_empty() and bool(preview.get(\"ok\", false))",
        "new": "\tvar automatic := reasons.is_empty() and bool(preview.get(\"ok\", false))",
    },
    {
        "name": "N-2 破损件不再写标注（界面看不出已损坏）",
        "file": POLICY,
        "test": "SellGearPolicyTest",
        "old": "\tif Durability.is_broken(item):\n\t\treasons.append(\"damaged\")",
        "new": "\tif false:\n\t\treasons.append(\"damaged\")",
    },
    {
        "name": "N-3 把 starred 也当仅提示项（保护被误删）",
        "file": POLICY,
        "test": "SellGearPolicyTest",
        "old": "const NOTES_ONLY := [\"damaged\"]",
        "new": "const NOTES_ONLY := [\"damaged\", \"starred\"]",
    },
    {
        "name": "N-4 拾取自动出售也放行破损件（口径差异被抹平）",
        "file": POLICY,
        "test": "SellGearPolicyTest",
        "old": "\tif not reasons.is_empty():\n\t\treturn {\"sell\": false, \"reason\": reasons[0], \"price\": 0}",
        "new": "\tif not blocking_reasons(reasons).is_empty():\n\t\treturn {\"sell\": false, \"reason\": reasons[0], \"price\": 0}",
    },
    {
        "name": "N-5 原因行退回旧实现（已损坏标注在勾选时不显示）",
        "file": PREVIEW,
        "test": "SellGearPreviewTest",
        "old": "\tvar selected := bool(row.default_selected)\n\tvar labels: Array[String] = []\n\tif selected:\n\t\tlabels.append(Localization.tr_key(\"ui.sale_preview.default_reason\"))\n\tfor reason in row.reasons:\n\t\tvar text_key := \"ui.sale_preview.reason_\" + String(reason)\n\t\tif SellGearPolicy.NOTES_ONLY.has(String(reason)) or not selected:\n\t\t\tlabels.append(Localization.tr_key(text_key))",
        "new": "\tvar selected := bool(row.default_selected)\n\tif selected:\n\t\treturn Localization.tr_key(\"ui.sale_preview.default_reason\")\n\tvar labels: Array[String] = []\n\tfor reason in row.reasons:\n\t\tlabels.append(Localization.tr_key(\"ui.sale_preview.reason_\" + String(reason)))",
    },
    {
        "name": "N-6 本地化键被摘掉（界面露出裸 key）",
        "file": LOCALIZATION,
        "test": "SellGearPreviewTest",
        "old": '  "ui.sale_preview.reason_damaged": "已损坏（耐久为 0，修好仍可用）",',
        "new": '  "ui.sale_preview.reason_damaged_removed": "已损坏（耐久为 0，修好仍可用）",',
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
