#!/usr/bin/env python3
"""工程 82 负向验证：逐条注入典型 bug，确认对应断言变红后自动还原。

用法：python3 tools/verify_82_negative.py [案例名]
⚠ 本脚本会临时改写源码 / 数据，必须与全量隔离集**串行**执行（工程 77 并发事故教训）。

注入原则（工程 08 §11.3）：注入形态必须与**真实 bug 同形**，且结果必须是断言失败；
凡是靠「写死常量 / 删一整段」让编译器先炸掉的，都是假红（脚本会识别 Compile/Parse Error）。

工程 82 的三类靶子分别落在三层，缺一层就有覆盖空洞：
- **数据层**（N-1 布局出圈 / N-6 守卫金币没跟上 / N-7 守卫倍率丢失）→ `EndgameCycleMapTest`
- **存档层**（N-2 迁移无门 → 每次读档都缩一次）→ `GoldFieldCapTest` 组 9
- **运行时层**（N-3 扣血不截 / N-4 cap 泄漏到 Boss / N-5 cap 0 未关闭）→ `GoldFieldCapTest` 组 1/2/6
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPAWNER = ROOT / "scripts/world/spawner.gd"
MONSTER = ROOT / "scripts/entities/monster.gd"
SAVE_MANAGER = ROOT / "autoload/save_manager.gd"
GOLD_MAP = ROOT / "data/maps/ch07/c7_gold_field/map.json"
DROP_TABLES = ROOT / "data/dropTables.json"
CAP_TEST = "GoldFieldCapTest"
MAP_TEST = "EndgameCycleMapTest"


def shift_all_cells(data: dict) -> None:
    """把所有席位整体平移 (6,6) 格：6 营结构完整保留，只有「到战场中心距离」变远。

    真实 bug 形态 = 布局挪位后忘了重新核对站桩覆盖（不是「少了一堆」这种一眼可见的错）。
    """
    for group in data["spawnPoints"]:
        group["cells"] = [[int(cell[0]) + 6, int(cell[1]) + 6] for cell in group["cells"]]


def cut_guard_gold(data: list) -> None:
    """守卫金币没跟上血量（只改血不改金）⇒ 单位时间收益反向暴涨。"""
    for table in data:
        if table.get("id") != "DT_C7_Gold_Guard":
            continue
        for entry in table["entries"]:
            if entry.get("kind") == "coin":
                entry["goldRange"] = [680, 800]


def drop_guard_multiplier(data: dict) -> None:
    """守卫的 hpMultiplier 丢了 ⇒ 24 席守卫退化成普通怪（掉落表还是四倍金币）。"""
    for group in data["spawnPoints"]:
        group.pop("hpMultiplier", None)


CASES = [
    {
        "name": "N-1 布局整体挪位后仍通过（玩家还是得跑图）",
        "json": GOLD_MAP,
        "mutate": shift_all_cells,
        "test": MAP_TEST,
    },
    {
        "name": "N-2 缩图迁移没有一次性门（每次读档再缩一次）",
        "file": SAVE_MANAGER,
        "test": CAP_TEST,
        "old": '\tif String(data.get("c7GoldLayoutVersion", "")) != CURRENT_C7_GOLD_LAYOUT_VERSION:\n\t\t_migrate_c7_gold_positions(data)',
        "new": '\t_migrate_c7_gold_positions(data)  # 负向注入：每次都缩',
    },
    {
        "name": "N-3 take_hit 不截断（封顶只写在别处，技能全绕过）",
        "file": MONSTER,
        "test": CAP_TEST,
        "old": '\thp = maxi(0, hp - capped_damage(int(result.get("damage", 0)), max_hp, damage_cap_pct))',
        "new": '\thp = maxi(0, hp - int(result.get("damage", 0)))  # 负向注入：扣血不封顶',
    },
    {
        # 🔴 真实 bug 形态 = 「写死 0.5」：把两道条件里的 kind 过滤换成常量后，Boss 也带 cap。
        # 只拆 `_load_caps` 那一道是**假绿** —— 另一道 kind 判断还在，Boss 仍得 0（首轮实测如此）。
        "name": "N-4 封顶不按地图隔离（Boss 档一起被削）",
        "file": SPAWNER,
        "test": CAP_TEST,
        "old": '\t\t\t\t"damage_cap_pct": _damage_cap_pct if String(spec.get("kind", "normal")) == "normal" else 0.0,',
        "new": '\t\t\t\t"damage_cap_pct": 0.5,  # 负向注入：不分档写死',
    },
    {
        "name": "N-5 cap 0 没有完全关闭（缺省地图被削成 1 点）",
        "file": MONSTER,
        "test": CAP_TEST,
        "old": '\tif cap_pct <= 0.0 or max_hp_value <= 0 or raw <= 0:',
        "new": '\tif max_hp_value <= 0 or raw <= 0:  # 负向注入：漏掉 cap<=0 的关闭分支',
    },
    {
        "name": "N-6 守卫金币没跟上血量（收益结构反向）",
        "json": DROP_TABLES,
        "mutate": cut_guard_gold,
        "test": MAP_TEST,
    },
    {
        "name": "N-7 守卫倍率丢失（24 席退化成普通怪）",
        "json": GOLD_MAP,
        "mutate": drop_guard_multiplier,
        "test": MAP_TEST,
    },
]


def run_case(case: dict) -> tuple[bool, str]:
    saved: list[tuple[Path, str]] = []
    if "json" in case:
        path: Path = case["json"]
        original = path.read_text(encoding="utf-8")
        payload = json.loads(original)
        case["mutate"](payload)
        saved.append((path, original))
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    else:
        path = case["file"]
        original = path.read_text(encoding="utf-8")
        if case["old"] not in original:
            return False, "注入点未找到（代码已变更，需更新脚本）：%s" % path.name
        saved.append((path, original))
        path.write_text(original.replace(case["old"], case["new"], 1), encoding="utf-8")
    try:
        result = subprocess.run(
            ["python3", "tools/run_isolated_tests.py", case["test"]],
            capture_output=True, text=True, timeout=300, cwd=ROOT,
        )
        output = result.stdout + result.stderr
        if "Compile Error" in output or "Parse Error" in output:
            return False, "编译失败（无效红，掩盖真实 bug 形态）"
        is_red = "FAIL" in output or "失败" in output
        summary = next((ln.strip() for ln in output.splitlines() if "PASS" in ln or "FAIL" in ln), "")
        return is_red, summary
    finally:
        for back_path, back_text in saved:
            back_path.write_text(back_text, encoding="utf-8")


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
    print(f"✅ 全部 {len(results)} 条负向都变红（已还原源码与数据）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
