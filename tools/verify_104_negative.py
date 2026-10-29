#!/usr/bin/env python3
"""工程 104 负向验证：地面掉落积压性能优化的四条守门。

每条把改动**逐条回滚 / 改坏**，确认 `GroundLootPerfTest` 真的变红后自动还原。
不仅要求「红」，还要求**红在预期的那条断言上** —— 否则可能是被别的原因带红的
（属于假绿）。任一案例不红或红错地方 = 该断言没有牙。

用法：python3 tools/verify_104_negative.py [案例名片段]
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUTO_BATTLE = ROOT / "scripts/systems/auto_battle.gd"
GROUND_ITEM = ROOT / "scripts/entities/ground_item.gd"
GROUND_FX = ROOT / "scripts/systems/ground_fx.gd"
GROUND_ITEM_SCENE = ROOT / "scenes/entities/GroundItem.tscn"
TEST = "GroundLootPerfTest"

CASES = [
    {
        "name": "N-1 装饰圈退回抗锯齿折线（原 bug 形态）",
        "file": GROUND_ITEM,
        "old": "\t\tGroundFx.ring(self, Vector2(0, 8), 26.0, Color(1.0, 0.62, 0.30), 0.85)",
        "new": "\t\tGroundFx.outline(self, Vector2(0, 8), 26.0, Color(1.0, 0.62, 0.30, 0.85), 2.0)",
        "expect": ["掉落物装饰圈不应再用折线"],
    },
    {
        "name": "N-2 背包满早退被删（2400 次 × 137 格扫描复活）",
        "file": AUTO_BATTLE,
        "old": "\tif _bag_full:\n\t\treturn false\n\treturn Inventory.has_space_for",
        "new": "\treturn Inventory.has_space_for",
        "expect": ["背包满缓存应短路"],
    },
    {
        "name": "N-3 节流改成无条件（新掉落会被推迟）",
        "file": AUTO_BATTLE,
        "old": "\t\tif _bag_full and _loot_scan_t > 0.0:",
        "new": "\t\tif _loot_scan_t > 0.0:",
        "expect": ["背包未满时不应被节流挡住"],
    },
    {
        "name": "N-4 距离门控被删（远处静止件也每帧重绘）",
        "file": GROUND_ITEM,
        "old": "\tif not _near_anim:\n\t\treturn",
        "new": "\tif false and not _near_anim:\n\t\treturn",
        "expect": ["远处静止件不应重绘"],
    },
    {
        "name": "N-5 ClickArea 恢复 monitoring（2400 个 Area2D 重新互查）",
        "file": GROUND_ITEM_SCENE,
        "old": "monitoring = false\nmonitorable = false",
        "new": "monitoring = true\nmonitorable = true",
        "expect": ["不应开启 monitoring"],
    },
    {
        "name": "N-6 环纹理生成成空白（圈隐形但性能看起来完美）",
        "file": GROUND_FX,
        "old": "\t\t\tif a > 0.0:\n\t\t\t\timg.set_pixel(x, y, Color(1, 1, 1, a))",
        "new": "\t\t\tif a > 0.0:\n\t\t\t\timg.set_pixel(x, y, Color(1, 1, 1, 0.0))",
        "expect": ["环纹理应有可见像素"],
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
