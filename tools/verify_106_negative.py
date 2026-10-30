#!/usr/bin/env python3
"""工程 106 负向验证：施法特效分派表的八颗牙。

每条把改动**逐条回滚 / 改坏**，确认 `MageFxCastingTest` 真的变红后自动还原。
不仅要求「红」，还要求**红在预期的那条断言上** —— 否则可能是被别的原因带红的（属于假绿）。

⚠ 注入点必须选**不会产生未使用变量 / 不可达代码**的改法：本项目 `warnings_as_errors` 开着，
   `if false: ...` 这类写法会变成编译错误（「无效红」，会掩盖真实 bug 形态）。
   本脚本一律用「改判断词」「删表行」「改常量值」三种改法，它们都能正常编译。

用法：python3 tools/verify_106_negative.py [案例名片段]
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAYER = ROOT / "scripts/entities/player.gd"
METEOR = ROOT / "scripts/systems/meteor_fx.gd"
FLAME = ROOT / "scripts/systems/flame_burst_fx.gd"
FROST = ROOT / "scripts/systems/frost_roar_fx.gd"
SHIELD = ROOT / "scripts/entities/magic_shield_aura.gd"
TEST = "MageFxCastingTest"
SHIELD_TEST = "MagicShieldTest"

CASES = [
    {
        "name": "N-1 分派表缺 meteor（数据写了 fx、代码没接）",
        "file": PLAYER,
        "old": '\t"meteor": preload("res://scripts/systems/meteor_fx.gd"),\n',
        "new": "",
        "expect": ["但 CAST_FX 分派表里没有这个 key"],
    },
    {
        "name": "N-2 有 fx 时仍 spawn 通用范围提示（两份对不上的范围）",
        "file": PLAYER,
        "old": '\tif String(skill.get("fx", "")) == "":',
        "new": '\tif String(skill.get("fx", "")) != "__never__":',
        "expect": ["不得再 spawn 通用范围提示"],
    },
    {
        "name": "N-3 声明的锚点与实际位置不符（特效出现在 A、伤害打在 B）",
        "file": METEOR,
        "old": 'const ANCHOR := "target"',
        "new": 'const ANCHOR := "origin"',
        "expect": ["位置层"],
    },
    {
        "name": "N-4 真 AoE 的 fx 自称不画范围（R2：玩家静默失去范围提示）",
        "file": METEOR,
        "old": "const DRAWS_AREA := true",
        "new": "const DRAWS_AREA := false",
        "expect": ["DRAWS_AREA 应为 true"],
    },
    {
        "name": "N-5 特效寿命超过技能 CD（连按时节点堆积）",
        "file": METEOR,
        "old": "const LIFETIME := 0.95",
        "new": "const LIFETIME := 5.0",
        "expect": ["必须短于技能 CD"],
    },
    {
        "name": "N-6 无 fx 的技能也跳过范围提示（一刀切把武士改了）",
        "file": PLAYER,
        "old": '\tif String(skill.get("fx", "")) == "":',
        "new": '\tif String(skill.get("fx", "")) == "__never__":',
        "expect": ["必须照旧 spawn 通用范围提示"],
    },
    {
        "name": "N-7 视觉层引用 GameState（105 立的「不碰结算」契约被破）",
        "file": METEOR,
        "old": "\tvar fade := 1.0 - tail",
        "new": "\tvar fade := 1.0 - tail + float(GameState.player.hp) * 0.0",
        "expect": ["视觉层不得参与伤害结算"],
    },
    {
        "name": "N-8 未知 fx key 静默什么都不画（比回落投射物更糟）",
        "file": PLAYER,
        "old": '\tif key == "" or not CAST_FX.has(key):\n'
               "\t\t_spawn_projectile(skill_id, target.global_position)\n"
               "\t\treturn",
        "new": '\tif key != "" and not CAST_FX.has(key):\n'
               "\t\treturn\n"
               '\tif key == "":\n'
               "\t\t_spawn_projectile(skill_id, target.global_position)\n"
               "\t\treturn",
        "expect": ["未知 fx key 必须回落到投射物"],
    },
    # ---- 批 2（火焰喷发 / 冰咆哮 / 魔法盾）----
    {
        "name": "N-9 火焰喷发锚点标错 origin→target（火喷在怪身上、伤害打在脚下）",
        "file": FLAME,
        "old": 'const ANCHOR := "origin"',
        "new": 'const ANCHOR := "target"',
        "expect": ["位置层"],
    },
    {
        "name": "N-10 冰咆哮朝向写死 RIGHT（冰往右喷、左边的怪掉血）",
        "file": FROST,
        "old": "\t_facing = dir.normalized()",
        "new": "\t_facing = Vector2.RIGHT",
        "expect": ["朝向应等于"],
    },
    {
        "name": "N-11 冰咆哮张角与命中判据不一致（扫过的怪不掉血）",
        "file": FROST,
        "old": "const ARC := PI * 0.5",
        "new": "const ARC := PI * 0.35",
        "expect": ["ARC 应为 PI/2"],
    },
    {
        "name": "N-12 火焰喷发半径写死（以后改 range 静默失效）",
        "file": FLAME,
        "old": '\t_radius = maxf(32.0, float(ctx.get("radius", 224.0)))',
        "new": "\t_radius = 224.0",
        "expect": ["必须采纳 ctx.radius=777"],
    },
    {
        "name": "N-13 护罩隐藏时仍推进动画（无盾状态下白跑每秒 8 条折线）",
        "file": SHIELD,
        "old": "\tif not visible:\n\t\treturn\n\t_t += delta",
        "new": "\tif not visible and _t < -1.0:\n\t\treturn\n\t_t += delta",
        "test": SHIELD_TEST,
        "expect": ["护罩隐藏时不得推进动画"],
    },
    {
        "name": "N-14 护罩呼吸幅度超出安全区（盖住角色或看不见盾）",
        "file": SHIELD,
        "old": "const BREATH_AMP := 0.15",
        "new": "const BREATH_AMP := 2.4",
        "test": SHIELD_TEST,
        "expect": ["呼吸幅度应落在"],
    },
]


def _run_once(case: dict) -> tuple[bool | None, str]:
    """返回 (是否红在预期断言上, 摘要)。`None` 表示**本轮结果无效**（环境故障），调用方应重试。

    🔴 必须把「环境故障」与「牙齿不存在」分开。`run_isolated_tests.py` 在导入阶段失败时
    只往 stderr 打「资源导入失败」并 return 1，**stdout 里没有任何 FAIL 行** ——
    直接按「有没有 FAIL」判，就会把一次偶发的导入失败误报成「注入后仍然全绿」。
    首轮验证里就撞到过：同一条用例单独跑稳定红、连跑时偶发「仍然全绿」，
    而每次报告的条目还都不一样。那条错误结论比没有验证更危险。
    """
    path: Path = case["file"]
    original = path.read_text(encoding="utf-8")
    if case["old"] not in original:
        return False, "注入点未找到（源码已变更，需更新脚本）"
    path.write_text(original.replace(case["old"], case["new"], 1), encoding="utf-8")
    try:
        result = subprocess.run(
            [sys.executable, "tools/run_isolated_tests.py", case.get("test", TEST)],
            capture_output=True, text=True, timeout=600, cwd=ROOT,
        )
        output = result.stdout + result.stderr
        if "Compile Error" in output or "Parse Error" in output:
            return False, "编译失败（无效红，掩盖真实 bug 形态）"
        # 有效结果必须能在 stdout 里看到该测试的结论行；否则是导入失败 / 超时 / 进程异常。
        test_name = case.get("test", TEST)
        if f"{test_name}: PASS" not in output and f"{test_name}: FAIL" not in output:
            head = next((ln.strip() for ln in output.splitlines() if ln.strip()), "<空输出>")
            return None, f"本轮结果无效（runner 未产出结论行：{head[:100]}）"
        is_red = "FAIL" in output or "SCRIPT ERROR" in output
        if not is_red:
            return False, "仍然全绿（这颗牙不存在）"
        missing = [kw for kw in case["expect"] if kw not in output]
        if missing:
            head = next(
                (ln.strip() for ln in output.splitlines() if "FAIL:" in ln), "<无失败行>")
            return False, f"红错地方（缺预期文案 {missing}）：{head[:120]}"
        return True, "红在预期断言：" + " / ".join(case["expect"])
    finally:
        path.write_text(original, encoding="utf-8")


def run_case(case: dict, retries: int = 2) -> tuple[bool, str]:
    """跑一条负向用例；环境故障时重试，避免把偶发导入失败当成「牙齿不存在」。"""
    summary = ""
    for _attempt in range(retries + 1):
        red, summary = _run_once(case)
        if red is not None:
            return red, summary
    return False, summary


def main() -> int:
    filter_name = sys.argv[1] if len(sys.argv) > 1 else None
    results = []
    for case in CASES:
        if filter_name and filter_name not in case["name"]:
            continue
        red, summary = run_case(case)
        results.append((case["name"], red, summary))
        print(f"[{'RED ' if red else 'BAD!'}] {case['name']}  ->  {summary}", flush=True)
    bad = [name for name, red, _ in results if not red]
    print()
    if bad:
        print(f"❌ 有 {len(bad)} 条负向没能红在对的断言上：{bad}")
        return 1
    print(f"✅ 全部 {len(results)} 条负向都红在预期断言上（已还原源码）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
