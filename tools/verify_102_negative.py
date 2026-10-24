#!/usr/bin/env python3
"""工程 102 负向验证：同部位升级候选「按槽位数限额」的守门。

每条把实现**逐条回滚 / 改坏**，确认 `SellGearQuotaTest` 真的变红、且红在**预期的那条断言**上
（`expect` 子串），跑完自动还原源码。任一案例没红、或红在别处 = 该断言没有牙。

用法：python3 tools/verify_102_negative.py [案例名片段]
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "scripts/systems/sell_gear_policy.gd"
TEST = "SellGearQuotaTest"

CASES = [
    {
        "name": "N-1 额度写死 1（双槽部位也只留 1 件）",
        "file": POLICY,
        "test": TEST,
        "old": "\treturn maxi(1, Equipment.slots_for_kind(kind).size())",
        "new": "\treturn 1",
        "expect": "第 2 名留在额度内",
    },
    {
        "name": "N-2 恢复「升级候选无条件保护」（额度不生效，原 bug 形态）",
        "file": POLICY,
        "test": TEST,
        "old": '\t\treasons.append("upgrade" if protected_upgrade else "duplicate")',
        "new": '\t\treasons.append("upgrade")',
        "expect": "第 2 名默认勾选出售",
    },
    {
        "name": "N-3 build_preview 不透传额度上下文（静默退回旧口径）",
        "file": POLICY,
        "test": TEST,
        "old": "\t\t\tvar row := entry(inventory[i], i, player_level, equipment, preset, quota)",
        "new": "\t\t\tvar row := entry(inventory[i], i, player_level, equipment, preset)",
        "expect": "清单里只留 1 件",
    },
    {
        "name": "N-4 改成口径 A（金紫不占额度）",
        "file": POLICY,
        "test": TEST,
        "old": "\t\tif not groups.has(kind):\n\t\t\tgroups[kind] = []",
        "new": ("\t\tif Shop.QUALITY_ORDER.find(Shop.item_quality(item)) > Shop.QUALITY_ORDER.find(\"rare\"):\n"
                "\t\t\tcontinue\n"
                "\t\tif not groups.has(kind):\n\t\t\tgroups[kind] = []"),
        "expect": "金紫占额度",
    },
    {
        "name": "N-5 拾取时不驱逐（新件入包、旧的留着，背包回涨）",
        "file": POLICY,
        "test": TEST,
        "old": "\tfor r in range(merged.size() - 1, quota - 1, -1):",
        "new": "\tfor r in range(0):",
        "expect": "背包件数应保持额度 1",
    },
    {
        "name": "N-6 同分排序 tiebreak 写反（谁留下变得不可预期）",
        "file": POLICY,
        "test": TEST,
        "old": "\t\treturn int(a.get(\"index\", 0)) < int(b.get(\"index\", 0))",
        "new": "\t\treturn int(a.get(\"index\", 0)) > int(b.get(\"index\", 0))",
        "expect": "同分时保留背包格序靠前的那件",
    },
    {
        "name": "N-7 duplicate 也进自动出售否决集（超额度件永远清不掉）",
        "file": POLICY,
        "test": TEST,
        "old": '\t\tif reason == "upgrade" or SELL_THROUGH.has(reason):\n\t\t\tcontinue\n\t\tout.append(reason)',
        "new": '\t\tif reason == "upgrade":\n\t\t\tcontinue\n\t\tout.append(reason)',
        "expect": "额度已满且新件更差",
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
            capture_output=True, text=True, timeout=600, cwd=ROOT,
        )
        output = result.stdout + result.stderr
        if "Compile Error" in output or "Parse Error" in output:
            return False, "编译失败（无效红，掩盖真实 bug 形态）"
        is_red = "FAIL" in output or "SCRIPT ERROR" in output
        if not is_red:
            return False, "没有变红"
        # 红必须红在**预期那条断言**上，否则可能是别的原因带红的（假牙）。
        expected = case.get("expect", "")
        if expected and expected not in output:
            return False, f"红了但没红在预期断言上（缺少「{expected}」）"
        summary = next(
            (ln.strip() for ln in output.splitlines() if "FAIL" in ln), "")
        return True, summary[:160]
    finally:
        path.write_text(original, encoding="utf-8")


def main() -> int:
    filter_name = sys.argv[1] if len(sys.argv) > 1 else None
    results = []
    for case in CASES:
        if filter_name and filter_name not in case["name"]:
            continue
        ok, summary = run_case(case)
        results.append((case["name"], ok, summary))
        print(f"[{'RED ' if ok else 'MISS'}] {case['name']}  ->  {summary}", flush=True)
    bad = [name for name, ok, _ in results if not ok]
    print()
    if bad:
        print(f"❌ 有 {len(bad)} 条负向不成立：{bad}")
        return 1
    print(f"✅ 全部 {len(results)} 条负向都红在预期断言上（已还原源码）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
