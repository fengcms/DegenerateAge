"""工程 75 的负向验证：逐条注入真实 bug 形态，确认对应断言变红，然后还原。

每条用例只改一处、只跑一个测试，跑完立刻从内存备份还原原文件。
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FUSION = ROOT / "scripts/systems/equipment_fusion.gd"
STATE = ROOT / "autoload/game_state.gd"
PANEL = ROOT / "scripts/ui/equipment_fusion_panel.gd"

CASES = [
    {
        "name": "N-1 材料数量改回恒 4 件",
        "file": FUSION,
        "test": "EquipmentFusionRuleTest",
        "old": "\tvar limits := material_range(mode)\n\tif items.size() < limits.x or items.size() > limits.y:",
        "new": "\tvar limits := material_range(mode)\n\tif items.size() != 4:",
    },
    {
        "name": "N-2 随机放入改回等概率抽档",
        "file": FUSION,
        "test": "EquipmentFusionRuleTest",
        "old": "\ttiers.sort()\n\tvar pool: Array = (groups[tiers[0]] as Array).duplicate()",
        "new": ("\ttiers.sort()\n"
                "\tvar tier_index := rng.randi_range(0, tiers.size() - 1) if rng != null else randi_range(0, tiers.size() - 1)\n"
                "\tvar pool: Array = (groups[tiers[tier_index]] as Array).duplicate()"),
    },
    {
        "name": "N-3 档位门槛改回「至少四件」",
        "file": FUSION,
        "test": "EquipmentFusionRuleTest",
        "old": "\t\tif (groups[tier] as Array).size() >= limits.x:",
        "new": "\t\tif (groups[tier] as Array).size() >= 4:",
    },
    {
        "name": "N-4 删除掷骰（恒成功）",
        "file": STATE,
        "test": "EquipmentFusionTransactionTest",
        "old": "\tif rate < 1.0:\n\t\tvar roll := rng.randf() if rng != null else randf()",
        "new": "\tif rate < 0.0:\n\t\tvar roll := rng.randf() if rng != null else randf()",
    },
    {
        "name": "N-5 掷骰失败但不扣材料",
        "file": STATE,
        "test": "EquipmentFusionTransactionTest",
        "old": ("\t\tif roll >= rate:\n"
                "\t\t\tfor index in bag_indices:\n"
                "\t\t\t\tinventory[index] = null\n"
                "\t\t\tfor slot_id in worn_slots:\n"
                "\t\t\t\tequipment[slot_id] = null\n"
                "\t\t\tif worn_slots.is_empty():"),
        "new": "\t\tif roll >= rate:\n\t\t\tif worn_slots.is_empty():",
    },
    {
        "name": "N-6 掷骰前多消耗一次 rng（模拟掷骰不在首位）",
        "file": STATE,
        "test": "EquipmentFusionTransactionTest",
        "old": "\tif rate < 1.0:\n\t\tvar roll := rng.randf() if rng != null else randf()",
        "new": ("\tif rate < 1.0:\n"
                "\t\tif rng != null:\n"
                "\t\t\trng.randf()\n"
                "\t\tvar roll := rng.randf() if rng != null else randf()"),
    },
    {
        "name": "N-7 材料快照恢复「有空格就返回空」",
        "file": PANEL,
        "test": "EquipmentFusionUiTest",
        "old": ("\tfor i in range(2 if _mode == EquipmentFusion.STAR_TRANSFER else _slots.size()):\n"
                "\t\tif _selected[i].is_empty():\n"
                "\t\t\tcontinue\n"
                "\t\tresult.append(_selected[i])"),
        "new": ("\tfor i in range(2 if _mode == EquipmentFusion.STAR_TRANSFER else _slots.size()):\n"
                "\t\tif _selected[i].is_empty():\n"
                "\t\t\treturn []\n"
                "\t\tresult.append(_selected[i])"),
    },
    {
        "name": "N-8 预览去掉成功率行",
        "file": PANEL,
        "test": "EquipmentFusionUiTest",
        # 只掐掉两条输出语句、保留 rate 的声明与使用，避免「编译失败」这种无效红。
        "old": ('\t\t_summary.text += "\\n" + Localization.tr_key("ui.fusion.rate", [int(round(rate * 100.0))])\n'
                "\t\tif rate < 1.0:\n"
                '\t\t\t_summary.text += "\\n" + Localization.tr_key("ui.fusion.rate_risk")\n'),
        "new": ('\t\tif rate < -1.0:\n'
                '\t\t\t_summary.text += "x"\n'),
    },
    {
        "name": "N-9 少于四件时不强制二次确认",
        "file": PANEL,
        "test": "EquipmentFusionUiTest",
        "old": "\tif rate < 1.0:\n\t\trisk = true\n",
        "new": "\tif rate < -1.0:\n\t\trisk = true\n",
    },
    {
        "name": "N-10 失败分支不返回 lost 字段",
        "file": STATE,
        "test": "EquipmentFusionTransactionTest",
        "old": ('\t\t\treturn {"ok": false, "lost": true, "consumed": selected.size(),\n'
                '\t\t\t\t"reason": "合成失败，%d 件材料已消耗" % selected.size()}'),
        "new": ('\t\t\treturn {"ok": false, "consumed": selected.size(),\n'
                '\t\t\t\t"reason": "合成失败，%d 件材料已消耗" % selected.size()}'),
    },
]


def run_case(case: dict) -> tuple[bool, str]:
    """返回 (断言是否变红, 输出摘要)。"""
    path: Path = case["file"]
    original = path.read_text(encoding="utf-8")
    if case["old"] not in original:
        return False, "注入点未找到（夹具已过期）"
    mutated = original.replace(case["old"], case["new"], 1)
    path.write_text(mutated, encoding="utf-8")
    try:
        proc = subprocess.run(
            [sys.executable, str(ROOT / "tools/run_isolated_tests.py"), case["test"]],
            cwd=ROOT, capture_output=True, text=True, timeout=300,
        )
        text = (proc.stdout or "") + (proc.stderr or "")
        failed = proc.returncode != 0 or ": FAIL" in text or "SCRIPT ERROR" in text
        labels = [line.strip() for line in text.splitlines()
                  if "FAIL:" in line or ": FAIL" in line or "SCRIPT ERROR" in line]
        return failed, " | ".join(labels[:3]) or ("编译失败" if failed else "仍然全绿")
    finally:
        path.write_text(original, encoding="utf-8")


def main() -> int:
    backups = {p: p.read_text(encoding="utf-8") for p in (FUSION, STATE, PANEL)}
    only = " ".join(sys.argv[1:])
    cases = [c for c in CASES if not only or only in c["name"]]
    if not cases:
        print(f"❌ 没有匹配「{only}」的用例")
        return 1
    results = []
    try:
        for case in cases:
            red, summary = run_case(case)
            results.append((case["name"], red, summary))
            print(f"[{'RED ' if red else 'GREEN!'}] {case['name']}  ->  {summary}", flush=True)
    finally:
        for path, text in backups.items():
            path.write_text(text, encoding="utf-8")
    bad = [name for name, red, _ in results if not red]
    print()
    if bad:
        print(f"❌ 有 {len(bad)} 条负向没能变红：{bad}")
        return 1
    print(f"✅ 全部 {len(results)} 条负向都变红（已还原源码）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
