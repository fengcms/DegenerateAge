#!/usr/bin/env python3
"""工程 100 负向验证：任务目标精英「刷新期必须有墓碑」的守门。

每条把修复**逐条回滚 / 改坏**，确认 `QuestTargetRespawnHintTest` 真的变红后自动还原。
任一案例没红 = 该断言没有牙（或被别的校验挡死，属于假绿）。

用法：python3 tools/verify_100_negative.py [案例名片段]
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPAWNER = ROOT / "scripts/world/spawner.gd"
LOCALIZATION = ROOT / "data/localization.json"
LOWER_WORKS = ROOT / "data/maps/ch02/c2_lower_works/map.json"
OLD_WELL = ROOT / "data/maps/ch02/c2_old_well/map.json"
TEST = "QuestTargetRespawnHintTest"

CASES = [
    {
        "name": "N-1 任务目标精英刷点的 tombstone 被摘掉（原 bug 形态）",
        "file": LOWER_WORKS,
        "test": TEST,
        "old": '      "dropTableId": "DT_C2_Industrial_Elite",\n      "tombstone": true',
        "new": '      "dropTableId": "DT_C2_Industrial_Elite"',
    },
    {
        "name": "N-2 文案改回写死「Boss 刷新」（精英显示成 Boss）",
        "file": LOCALIZATION,
        "test": TEST,
        "old": '  "ui.boss_tombstone.p001": "刷新 %02d:%02d",',
        "new": '  "ui.boss_tombstone.p001": "Boss 刷新 %02d:%02d",',
    },
    {
        "name": "N-3 占位符少一个（带参 tr_key 会 incomplete format）",
        "file": LOCALIZATION,
        "test": TEST,
        "old": '  "ui.boss_tombstone.p001": "刷新 %02d:%02d",',
        "new": '  "ui.boss_tombstone.p001": "刷新 %02d",',
    },
    {
        "name": "N-4 Boss 侧的 tombstone 被波及（只加了精英、改坏了 Boss）",
        "file": OLD_WELL,
        "test": TEST,
        "old": '    "kind": "boss",\n    "tombstone": true',
        "new": '    "kind": "boss",\n    "tombstone": false',
    },
    {
        "name": "N-5 Spawner 不再透传 tombstone（数据对但世界没提示）",
        "file": SPAWNER,
        "test": TEST,
        "old": '\t\t\t\t"tombstone": bool(spec.get("tombstone", false)),',
        "new": '\t\t\t\t"tombstone": false,',
    },
]


def run_case(case: dict) -> tuple[bool, str]:
    path: Path = case["file"]
    original = path.read_text(encoding="utf-8")
    if case["old"] not in original:
        return False, "注入点未找到（源码已变更，需更新脚本）"
    path.write_text(original.replace(case["old"], case["new"], 1), encoding="utf-8")
    try:
        result = subprocess.run(
            [sys.executable, "tools/run_isolated_tests.py", case["test"]],
            capture_output=True, text=True, timeout=300, cwd=ROOT,
        )
        output = result.stdout + result.stderr
        if "Compile Error" in output or "Parse Error" in output:
            return False, "编译失败（无效红，掩盖真实 bug 形态）"
        is_red = "FAIL" in output or "SCRIPT ERROR" in output
        summary = next(
            (ln.strip() for ln in output.splitlines() if "PASS" in ln or "FAIL" in ln), "")
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
