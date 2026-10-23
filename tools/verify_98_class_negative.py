"""负向验证：确认职业体系（工程 98）的六条判据真的有牙。

背景：法师这一整套机制错起来**全是静默的** —— 系数配错、射程没接上、蓝耗变成免费、
盾只减伤不扣蓝、减速没生效、读档留着别人的技能格，游戏都照常跑、零报错。
玩家只会在某天发现「法师站着不死」或「点了技能格没反应」。所以每条破坏都必须让
对应断言变红，而且必须红在**那一条**上。

N-1 `classes.json` 武士 `hpMult` 1.0 → 1.1 —— `ClassFrameTest`「默认职业系数全 1.0」变红。
N-2 `classes.json` 法师 `attackRange` 4.0 → 1.0 —— `MageRangedTest`「3.9 格能打」变红。
N-3 删掉 `lightning` 的 `manaCostPct` —— `MageManaTest`「按 max_mp 算」变红。
    （改 0.0 不行：`data_loader` 会判 `(0,1)` 越界，红的就不是这条了。）
N-4 `magic_shield` 的 `damageToManaPct` 0.35 → 0.0 —— `MagicShieldTest`「扣血 650」变红。
N-5 `frost_roar` 的 debuff 强度 0.35 → 0.0 —— `MageSlowTest`「移速 ×0.65」变红。
N-6 删掉读档时的 `prune_hotbar_for_class()` —— `ClassFrameTest`「快捷栏无非本职业技能」变红。

🔴 每个用例前还原**所有**被改文件：只还原当次那个的话，上一轮补丁会留在盘上，
   第二次「变红」证明的就不是想验的那一条（工程 89 已踩）。

跑法：python3 tools/verify_98_class_negative.py
"""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLASSES = ROOT / "data/classes.json"
SKILLS = ROOT / "data/skills.json"
SAVE_MANAGER = ROOT / "autoload/save_manager.gd"

# ---- 锚点（原文必须逐字命中，命中失败要报出来，不能静默跳过）----
WARRIOR_HP = '    "hpMult": 1.0,'
MAGE_RANGE = '    "attackRange": 4.0,'
LIGHTNING_PCT = '    "manaCostPct": 0.03,\n'
SHIELD_PCT = '    "effects": { "damageToManaPct": 0.35 },'
FROST_DEBUFF = '    "debuff": { "type": "slow", "value": 0.35, "duration": 3.0 },'
PRUNE_CALL = "\tGameState.prune_hotbar_for_class()\n"

CASES = [
    ("N-1 武士 hpMult 1.0 → 1.1（默认职业不再是基准）", "ClassFrameTest", CLASSES, WARRIOR_HP, '    "hpMult": 1.1,'),
    ("N-2 法师射程 4.0 → 1.0（远程变近战）", "MageRangedTest", CLASSES, MAGE_RANGE, '    "attackRange": 1.0,'),
    ("N-3 删掉闪电术的百分比蓝耗（法术变免费）", "MageManaTest", SKILLS, LIGHTNING_PCT, ""),
    ("N-4 魔法盾转嫁 0.35 → 0.0（只减伤不扣蓝）", "MagicShieldTest", SKILLS, SHIELD_PCT,
     '    "effects": { "damageToManaPct": 0.0 },'),
    ("N-5 冰咆哮减速 0.35 → 0.0（冻缓失效）", "MageSlowTest", SKILLS, FROST_DEBUFF,
     '    "debuff": { "type": "slow", "value": 0.0, "duration": 3.0 },'),
    ("N-6 读档不清理非法技能格（法师档留着武士技能）", "ClassFrameTest", SAVE_MANAGER,
     PRUNE_CALL, "\tpass\n"),
]


def run_test(name: str) -> tuple[bool, str]:
    proc = subprocess.run(["python3", "tools/run_isolated_tests.py", name],
                          cwd=ROOT, capture_output=True, text=True)
    return proc.returncode == 0, proc.stdout + proc.stderr


def first_failure(out: str) -> str:
    lines = [line.strip() for line in out.splitlines() if line.strip()]
    errors = [line for line in lines
              if line.startswith("ERROR:") and "未输出成功完成标记" not in line
              and "caller thread" not in line]
    if errors:
        return " / ".join(list(dict.fromkeys(errors))[:2])[:400]
    for line in lines:
        if "FAIL" in line:
            return line[:200]
    # 🔴 兜底必须打印原始尾巴：只报「未捕获到失败行」时无从判断是「测试挂了」
    #    还是「根本没跑起来」（引擎崩溃 / 场景加载失败都不会打 ERROR:）。
    return "原始输出尾部：" + " | ".join(lines[-6:])[:400]


def patch(path: Path, source: str, old: str, new: str) -> None:
    """替换并断言锚点确实命中 —— 锚点漂移会让负向「什么都不改」然后照常绿。"""
    if old not in source:
        raise SystemExit(f"⚠ 锚点未命中，负向无效：{path.name} ← {old[:60]!r}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def main() -> int:
    sources = {path: path.read_text(encoding="utf-8") for path in (CLASSES, SKILLS, SAVE_MANAGER)}

    # 前置：不改任何东西时六个场景都必须全绿，否则后面的「变红」不说明任何问题。
    for name in sorted({case[1] for case in CASES}):
        ok, out = run_test(name)
        if not ok:
            print(f"⚠ 基线不是绿的（{name}），先修基线再验负向：")
            print("    " + first_failure(out))
            return 1
        print(f"前置：未改动时 {name} 全绿 ✅")

    failures = 0
    try:
        for label, test_name, path, old, new in CASES:
            # 🔴 每个用例前还原**所有**被改文件（不只是当次要改的那个）。
            for p, text in sources.items():
                p.write_text(text, encoding="utf-8")
            patch(path, sources[path], old, new)

            ok, out = run_test(test_name)
            print(f"{label}\n    → {test_name}：{'❌ 仍绿（断言无效）' if ok else '✅ 变红'}")
            if ok:
                failures += 1
            else:
                print("      " + first_failure(out))
    finally:
        for p, text in sources.items():
            p.write_text(text, encoding="utf-8")

    tail_ok = True
    for name in sorted({case[1] for case in CASES}):
        ok, out = run_test(name)
        print(f"还原后复跑 {name}：" + ("全绿 ✅" if ok else "⚠ 仍红 —— " + first_failure(out)))
        tail_ok = tail_ok and ok
    print("负向全部有牙 ✅" if failures == 0 and tail_ok else "存在假绿 ⚠")
    return 1 if failures or not tail_ok else 0


if __name__ == "__main__":
    raise SystemExit(main())
