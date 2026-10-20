"""工程 76 的负向验证：逐条注入真实 bug 形态，确认对应断言变红，然后还原。

每条用例只改一处、只跑一个测试，跑完立刻从内存备份还原原文件。
可按用例名过滤：python3 tools/verify_76_negative.py N-3
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UTIL = ROOT / "scripts/systems/item_util.gd"
SLOT = ROOT / "scripts/ui/item_slot.gd"

CASES = [
    {
        "name": "N-1 0 星也显示徽标",
        "file": UTIL,
        "test": "EquipmentLevelBadgeTest",
        "old": '\tif star <= 0:\n\t\treturn ""\n\tif star >= Upgrade.max_star():\n\t\treturn "☀️"',
        "new": '\tif star >= Upgrade.max_star():\n\t\treturn "☀️"',
    },
    {
        "name": "N-2 6 星错落到蓝档（判据写成 > 6）",
        "file": UTIL,
        "test": "EquipmentLevelBadgeTest",
        "old": '\tif star >= 6:\n\t\treturn STAR_BADGE_COLOR["mid"]',
        "new": '\tif star > 6:\n\t\treturn STAR_BADGE_COLOR["mid"]',
    },
    {
        "name": "N-3 星级色偷用品质色原值",
        "file": UTIL,
        "test": "EquipmentLevelBadgeTest",
        "old": '\tif star >= 6:\n\t\treturn STAR_BADGE_COLOR["mid"]',
        "new": '\tif star >= 6:\n\t\treturn QUALITY_COLOR["rare"]',
    },
    {
        "name": "N-3b 满星漏写 U+FE0F（渲染成灰白太阳）",
        "file": UTIL,
        "test": "EquipmentLevelBadgeTest",
        "old": '\tif star >= Upgrade.max_star():\n\t\treturn "☀️"',
        "new": '\tif star >= Upgrade.max_star():\n\t\treturn "☀"',
    },
    {
        "name": "N-4 星级徽标抢鼠标与拖放",
        "file": SLOT,
        "test": "EquipmentLevelBadgeTest",
        "old": "\t_star_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE\n",
        "new": "\t_star_marker.mouse_filter = Control.MOUSE_FILTER_STOP\n",
    },
    {
        "name": "N-5 item setter 里不刷新星级",
        "file": SLOT,
        "test": "EquipmentLevelBadgeTest",
        "old": "\t\t_refresh_favorite_marker()\n\t\t_refresh_star_badge()\n",
        "new": "\t\t_refresh_favorite_marker()\n",
    },
    {
        "name": "N-6 11 星被误判成满星",
        "file": UTIL,
        "test": "EquipmentLevelBadgeTest",
        "old": "\tif star >= Upgrade.max_star():\n\t\treturn STAR_BADGE_COLOR[\"max\"]",
        "new": "\tif star >= Upgrade.max_star() - 1:\n\t\treturn STAR_BADGE_COLOR[\"max\"]",
    },
    {
        "name": "N-7 收藏 ◆ 搬回左上与星级重叠",
        "file": SLOT,
        "test": "EquipmentLevelBadgeTest",
        "old": "\t_favorite_marker.offset_left = -26\n",
        "new": "\t_favorite_marker.offset_left = 2\n",
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
        # 只认「断言失败」；编译失败会掩盖真实形态，必须算作无效红。
        compile_broken = "Compile Error" in text or "Parse Error" in text or "Failed to load script" in text
        failed = proc.returncode != 0 or ": FAIL" in text or "SCRIPT ERROR" in text
        labels = [line.strip() for line in text.splitlines()
                  if "FAIL:" in line or ": FAIL" in line or "SCRIPT ERROR" in line]
        if failed and compile_broken:
            return False, "编译失败（无效红，会掩盖真实 bug 形态）"
        return failed, " | ".join(labels[:3]) or ("仍然全绿" if not failed else "未知失败形态")
    finally:
        path.write_text(original, encoding="utf-8")


def main() -> int:
    backups = {p: p.read_text(encoding="utf-8") for p in (UTIL, SLOT)}
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
