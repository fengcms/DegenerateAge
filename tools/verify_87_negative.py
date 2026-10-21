#!/usr/bin/env python3
"""工程 87 负向验证：逐条注入典型 bug，确认 `PurpleSacrificeTest` 对应断言变红后自动还原。

用法：python3 tools/verify_87_negative.py [案例名]
⚠ 本脚本会临时改写源码，必须与全量隔离集**串行**执行（工程 77 并发事故教训）。

注入原则（工程 08 §11.3）：注入形态必须与**真实 bug 同形**，且结果必须是断言失败；
凡是靠「写死常量 / 删一整段」让编译器先炸掉的，都是假红（脚本会识别 Compile/Parse Error）。

工程 87 的三个靶子分别在规则层与事务层，缺一层就有覆盖空洞：
- **规则层**（N-1 按玩家等级计价 / N-2 星级无加成 / N-3 收藏可献祭 / N-4 上限失效）
  → `Sacrifice` 的纯函数断言
- **事务层**（N-5 穿戴件放行 / N-6 遇错跳过而非整批拒绝）→ `GameState.sacrifice_purple`

两条最容易假绿的记在这里：
- **N-2**：组 2 的期望值本身就是 `boss_xp × (1 + 12 × Sacrifice.STAR_BONUS)` ⇒ 常数改成 0 时期望值
  跟着变成 0 加成、等式仍然成立。真正有牙的是那条**绝对判据**「12★ / 0★ 比值 ∈ 1.95—1.97」。
- **N-5**：穿戴件在 `find_owned_item` 里的 `index` 是 **-1**，放行后会在扣件处越界 —— 红是红了，
  但报错文案指不到「穿戴件被献祭」这个真因，所以脚本额外打印 ERROR 原文。
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SACRIFICE = ROOT / "scripts/systems/sacrifice.gd"
GAME_STATE = ROOT / "autoload/game_state.gd"
TEST = "PurpleSacrificeTest"

CASES = [
    {
        # 真实 bug 形态 = 「图省事，直接拿玩家的等级去查曲线」：单独看每件都算得出数，
        # 只有对着 `requiredLevel` 才看得出「回低档图秒杀刷紫装」能白赚一档经验。
        "name": "N-1 xp_of 按玩家等级计价（回低档图刷紫装变最优解）",
        "file": SACRIFICE,
        "old": '\tvar raw := float(Balance.boss_xp(Equipment.level_req(item))) * RATIO \\\n'
               '\t\t* (1.0 + float(star) * STAR_BONUS)',
        "new": '\tvar raw := float(Balance.boss_xp(int(GameState.player.get("level", 1)))) * RATIO \\\n'
               '\t\t* (1.0 + float(star) * STAR_BONUS)  # 负向注入：按玩家等级计价',
    },
    {
        # ⚠ 这条只能靠组 2 的**比值**判据抓（期望值自己用了同一个常数）。
        "name": "N-2 星级加成丢失（12★ 与 0★ 同价）",
        "file": SACRIFICE,
        "old": "const STAR_BONUS := 0.08",
        "new": "const STAR_BONUS := 0.0  # 负向注入：星级不加成",
    },
    {
        # 真实 bug 形态 = 「加白名单时漏了收藏件」：整段守卫被顺手删掉。
        "name": "N-3 收藏件可献祭（守卫整段漏写）",
        "file": SACRIFICE,
        "old": '\tif bool(item.get("favorite", false)):\n\t\treturn false\n',
        "new": "",
    },
    {
        # 真实 bug 形态 = 「界面上限画了 20 件，规则层没接」。
        "name": "N-4 单次上限失效（一次喂整包，连升刷屏）",
        "file": SACRIFICE,
        "old": "\tvar take := mini(normal.size(), MAX_BATCH)",
        "new": "\tvar take := normal.size()  # 负向注入：上限没接上",
    },
    {
        # 真实 bug 形态 = 「只判断找没找到，忘了看在哪」。
        "name": "N-5 穿戴中的件可献祭（把身上战力喂掉）",
        "file": GAME_STATE,
        "old": '\t\tif found.is_empty() or String(found.get("loc", "")) != "bag":',
        "new": '\t\tif found.is_empty():  # 负向注入：放过穿戴件',
    },
    {
        # 真实 bug 形态 = 「循环里遇错就 continue」：合法件照扣、经验照给，事务不再原子。
        "name": "N-6 遇错跳过而非整批拒绝（原子性丢失）",
        "file": GAME_STATE,
        "old": '\t\tif found.is_empty() or String(found.get("loc", "")) != "bag":\n'
               '\t\t\treturn {"ok": false, "reason": Localization.tr_key("ui.sacrifice.stale")}',
        "new": '\t\tif found.is_empty() or String(found.get("loc", "")) != "bag":\n'
               '\t\t\tcontinue  # 负向注入：遇到不合规的件就跳过',
    },
]


def run_case(case: dict) -> tuple[bool, str]:
    path: Path = case["file"]
    original = path.read_text(encoding="utf-8")
    if case["old"] not in original:
        return False, "注入点未找到（代码已变更，需更新脚本）：%s" % path.name
    path.write_text(original.replace(case["old"], case["new"], 1), encoding="utf-8")
    try:
        result = subprocess.run(
            ["python3", "tools/run_isolated_tests.py", TEST],
            capture_output=True, text=True, timeout=300, cwd=ROOT,
        )
        output = result.stdout + result.stderr
        if "Compile Error" in output or "Parse Error" in output:
            return False, "编译失败（无效红，掩盖真实 bug 形态）"
        is_red = "FAIL" in output or "失败" in output
        # 逐条列出**所有**失败断言：只看第一条会误判「红的不是我想要的那条」。
        details = list(dict.fromkeys(
            ln.strip().replace("ERROR: ", "")
            for ln in output.splitlines() if "ERROR:" in ln))
        return is_red, " / ".join(details[:4]) or "（无 ERROR 明细）"
    finally:
        path.write_text(original, encoding="utf-8")


def main() -> int:
    filter_name = sys.argv[1] if len(sys.argv) > 1 else None
    bad: list[str] = []
    total = 0
    for case in CASES:
        if filter_name and filter_name not in case["name"]:
            continue
        total += 1
        red, summary = run_case(case)
        print(f"[{'RED ' if red else 'GREEN!'}] {case['name']}  ->  {summary}", flush=True)
        if not red:
            bad.append(case["name"])
    print()
    if bad:
        print(f"❌ 有 {len(bad)} 条负向没能变红：{bad}")
        return 1
    print(f"✅ 全部 {total} 条负向都变红（已还原源码）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
