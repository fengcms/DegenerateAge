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
TEST = "MageFxCastingTest"

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
]


def run_case(case: dict) -> tuple[bool, str]:
    """返回 (是否红在预期断言上, 摘要)。"""
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
