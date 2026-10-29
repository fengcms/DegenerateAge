#!/usr/bin/env python3
"""工程 105 负向验证：单体技能不画范围提示 / 雷电术走专属落雷的六颗牙。

每条把改动**逐条回滚 / 改坏**，确认 `SkillFxShapeTest` 真的变红后自动还原。
不仅要求「红」，还要求**红在预期的那条断言上** —— 否则可能是被别的原因带红的
（属于假绿）。任一案例不红或红错地方 = 该断言没有牙。

⚠ 注入点必须选**不会产生未使用变量**的改法：本项目 `warnings_as_errors` 开着，
   `if false and ...` 这类保留引用的写法是安全的，直接删语句会把红变成编译错误
   （编译错误属于「无效红」，会掩盖真实 bug 形态）。

用法：python3 tools/verify_105_negative.py [案例名片段]
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RANGE_FX = ROOT / "scripts/systems/skill_range_fx.gd"
PLAYER = ROOT / "scripts/entities/player.gd"
SKILLS = ROOT / "data/skills.json"
THUNDER_FX = ROOT / "scripts/systems/thunder_fx.gd"
TEST = "SkillFxShapeTest"

CASES = [
    {
        "name": "N-1 单体被重新当成圆形画（原 bug 形态）",
        "file": RANGE_FX,
        "old": '\treturn shape_id == "circle" or shape_id == "cone"',
        "new": '\treturn shape_id == "circle" or shape_id == "cone" or shape_id == "single"',
        "expect": ["single 一次地面几何都不得绘制"],
    },
    {
        "name": "N-2 未知形状走兜底画圆（else 复活）",
        "file": RANGE_FX,
        "old": '\treturn shape_id == "circle" or shape_id == "cone"',
        "new": '\treturn shape_id != "single"',
        "expect": ["未识别的 shape 不得绘制任何地面几何"],
    },
    {
        # 工程 106 升级了 `skill_range_fx` 的绘制，注入点从「三行 fill/outline」改成
        # 「`_draw` 末尾那一行 `_draw_circle` 调用」。`k` / `env` 仍被 cone 分支引用，
        # 所以换成 `pass` 不会产生未使用变量（`warnings_as_errors` 开着）。
        "name": "N-3 circle 绘制被一刀切删掉（真 AoE 提示也消失）",
        "file": RANGE_FX,
        "old": "\t_draw_circle(k, env)",
        "new": "\tpass",
        "expect": ["circle 必须照常绘制地面几何"],
    },
    {
        "name": "N-4 数据层 fx 字段被删（分派键不在数据里）",
        "file": SKILLS,
        "old": '    "fx": "thunder",\n',
        "new": "",
        "expect": ["必须在 skills.json 标 fx=thunder"],
    },
    {
        # 工程 106 把 `if skill.get("fx") == "thunder"` 换成了 `CAST_FX` 分派表，
        # 注入点随之改为「把 thunder 从表里删掉」—— 这才是现在唯一能让雷电退回投射物的改法。
        "name": "N-5 分派表删掉 thunder（雷电又变成扔球）",
        "file": PLAYER,
        "old": '\t"thunder": preload("res://scripts/systems/thunder_fx.gd"),\n',
        "new": "",
        "expect": ["必须生成 1 个落雷节点"],
    },
    {
        # 工程 106 把「挂哪」从调用点搬进了 `thunder_fx.setup(ctx)`，注入点随之搬家。
        "name": "N-6 落雷原点错挂到施法者身上（位置不对齐目标）",
        "file": THUNDER_FX,
        "old": '\tglobal_position = ctx.get("target", Vector2.ZERO)',
        "new": '\tglobal_position = ctx.get("origin", Vector2.ZERO)',
        "expect": ["落雷原点必须对齐目标位置"],
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
