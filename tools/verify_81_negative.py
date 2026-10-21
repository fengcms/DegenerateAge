#!/usr/bin/env python3
"""工程 81 负向验证：逐条注入典型 bug，确认 ReforgeLockTest 对应断言变红后自动还原。

用法：python3 tools/verify_81_negative.py [案例名]
⚠ 本脚本会临时改写源码，必须与全量隔离集**串行**执行（工程 77 并发事故教训）。

注入原则（工程 08 §11.3）：注入形态必须与**真实 bug 同形**，且结果必须是断言失败；
凡是靠「写死常量 / 删一整段」让编译器先炸掉的，都是假红。
⚠ N-8 打的是 `ReforgeTest`（不是本工程的测试）—— 随机流快照是**绝对**判据，
   `ReforgeLockTest` 用例 1 只做「空锁定 vs 不传锁定」的**相对**比较，
   两边一起多掷一次它照样绿，只有那 20 行固定种子快照能发现。
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ITEM_FACTORY = ROOT / "scripts/systems/item_factory.gd"
REFORGE = ROOT / "scripts/systems/reforge.gd"
GAME_STATE = ROOT / "autoload/game_state.gd"
TEST = "ReforgeLockTest"
SNAPSHOT_TEST = "ReforgeTest"

CASES = [
    {
        "name": "N-1 锁定被忽略（仍走全量重掷）",
        "file": ITEM_FACTORY,
        "test": TEST,
        "old": '\tif (locked_stats as Array).is_empty():\n\t\treturn _roll_affixes(item_id, quality, affix_scale, rng)',
        "new": '\tif true:  # 负向注入：忽略锁定\n\t\treturn _roll_affixes(item_id, quality, affix_scale, rng)',
    },
    {
        "name": "N-2 候选池不剔除锁定 stat（掷出两条同属性）",
        "file": ITEM_FACTORY,
        "test": TEST,
        "old": '\t\tif fixed_cfg.has(String(stat)) and not locked_stats.has(String(stat)):',
        "new": '\t\tif fixed_cfg.has(String(stat)):  # 负向注入：不剔除锁定',
    },
    {
        "name": "N-3 百分比锁定仍走 randf 判定（间歇性丢失）",
        "file": ITEM_FACTORY,
        "test": TEST,
        "old": '\tif (locked_pct as Array).is_empty():',
        "new": '\tif true:  # 负向注入：锁了也照掷百分比判定',
    },
    {
        "name": "N-4 全锁放行（花 13 万买一个「没变化」）",
        "file": REFORGE,
        "test": TEST,
        "old": '\tif stats.size() > limit:\n\t\treturn {"ok": false, "reason": Localization.tr_key("msg.reforge.p006")}',
        "new": '\tif false:  # 负向注入：不做锁定上限校验\n\t\treturn {"ok": false, "reason": Localization.tr_key("msg.reforge.p006")}',
    },
    {
        "name": "N-5 费用不随锁定数上涨（锁定零成本）",
        "file": REFORGE,
        "test": TEST,
        "old": '\tvar multiplier := 1.0 + lock_factor * float(maxi(0, locked_count))',
        "new": '\tvar multiplier := 1.0  # 负向注入：锁定不加价',
    },
    {
        "name": "N-6 门面按原价扣费（只改了显示价，金币实扣没跟上）",
        "file": GAME_STATE,
        "test": TEST,
        "old": '\tvar price := Reforge.cost(Equipment.level_req(item), lock_count)',
        "new": '\tvar price := Reforge.cost(Equipment.level_req(item))  # 负向注入：按原价扣',
    },
    {
        # 🔴 必须**两层一起**注入：`Reforge.validate_locks` 之外还有第二道防线
        # （`ItemFactory._split_locked_entries` 取不到就失败）。只删一层会被另一层接住 ⇒ 假绿。
        # 真实 bug 形态正是「两处都静默丢弃」：校验放行、掷点也放行，玩家以为锁住了。
        "name": "N-7 非法 stat 静默丢弃（校验层 + 掷点层都不再拒绝）",
        "test": TEST,
        "edits": [
            (REFORGE,
             '\t\tif not present.has(stat):\n\t\t\treturn {"ok": false, "reason": Localization.tr_key("msg.reforge.p007")}',
             '\t\tif not present.has(stat):\n\t\t\tcontinue  # 负向注入：静默丢弃'),
            (ITEM_FACTORY,
             '\t\tif not found:\n\t\t\treturn {"ok": false, "reason": "missing"}',
             '\t\tif not found:\n\t\t\tcontinue  # 负向注入：静默丢弃'),
        ],
    },
    {
        "name": "N-8 空锁定多掷一次随机数（1—60 全部掉落漂移，零报错）",
        "file": ITEM_FACTORY,
        "test": SNAPSHOT_TEST,
        "old": '\tvar r := rng if rng != null else _default_rng()\n\tvar affix_count := int(q.get("affixCount", 0))',
        "new": '\tvar r := rng if rng != null else _default_rng()\n\tr.randf()  # 负向注入：多掷一次\n\tvar affix_count := int(q.get("affixCount", 0))',
    },
]


def edits_of(case: dict) -> list[tuple[Path, str, str]]:
    """注入点列表：支持单处（file/old/new）与多处（edits —— 双保险必须一起拆）。"""
    if "edits" in case:
        return case["edits"]
    return [(case["file"], case["old"], case["new"])]


def run_case(case: dict) -> tuple[bool, str]:
    edits = edits_of(case)
    saved: list[tuple[Path, str]] = []
    for path, old, new in edits:
        original = path.read_text(encoding="utf-8")
        if old not in original:
            for back_path, back_text in saved:
                back_path.write_text(back_text, encoding="utf-8")
            return False, "注入点未找到（代码已变更，需更新脚本）：%s" % path.name
        saved.append((path, original))
        path.write_text(original.replace(old, new, 1), encoding="utf-8")
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
    print(f"✅ 全部 {len(results)} 条负向都变红（已还原源码）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
