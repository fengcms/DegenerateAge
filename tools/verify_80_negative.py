#!/usr/bin/env python3
"""工程 80 负向验证：逐条注入典型 bug，确认 PortableToolsHotbarTest 对应断言变红后自动还原。

用法：python3 tools/verify_80_negative.py [案例名]
⚠ 本脚本会临时改写源码，必须与全量隔离集**串行**执行（工程 77 并发事故教训）。

注入原则（工程 08 §11.3）：注入形态必须与**真实 bug 同形**，且结果必须是断言失败；
凡是靠「写死常量 / 删一整段」让编译器先炸掉的，都是假红。
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOTBAR_CONFIG = ROOT / "scripts/systems/hotbar_config.gd"
HOTBAR_VISUAL = ROOT / "scripts/ui/hotbar_visual.gd"
CARTER = ROOT / "scripts/ui/carter_panel.gd"
TOKEN = ROOT / "scripts/ui/boss_token_panel.gd"
TEST = "PortableToolsHotbarTest"

CASES = [
    {
        "name": "N-1 放行口径回退成两个写死 id（三件套又拖不上）",
        "file": HOTBAR_CONFIG,
        "test": TEST,
        "old": '\t\t"item": return _usable_misc(id)',
        "new": '\t\t"item": return (id == TOWN_SCROLL or id == RANDOM_TICKET) '
               'and DataLoader.get_entry("miscItems", id) is Dictionary',
    },
    {
        "name": "N-2 放行口径放宽到 useType 非空（revive/quest 变假功能）",
        "file": HOTBAR_CONFIG,
        "test": TEST,
        "old": '\treturn USABLE_TYPES.has(String((template as Dictionary).get("useType", "")))',
        "new": '\treturn not String((template as Dictionary).get("useType", "")).is_empty()',
    },
    {
        "name": "N-3 简称退化成空（两件工具都显示首字「随」）",
        "file": HOTBAR_VISUAL,
        "test": TEST,
        "old": '\treturn "" if text == key else text',
        "new": '\treturn ""  # 负向注入：简称丢失',
    },
    {
        "name": "N-4 panel 类仍显示数量角标（像消耗品）",
        "file": HOTBAR_VISUAL,
        "test": TEST,
        "old": '\treturn not (template is Dictionary '
               'and String((template as Dictionary).get("useType", "")) == "panel")',
        "new": '\treturn true  # 负向注入：一律显示角标',
    },
    {
        "name": "N-5 缺件提示不区分仓库（玩家不知道东西在哪儿）",
        "file": HOTBAR_VISUAL,
        "test": TEST,
        "old": '\treturn Localization.tr_key("ui.hud.p020") % name if in_warehouse \\\n'
               '\t\telse Localization.tr_key("ui.hud.p017") % _name_of(binding)',
        "new": '\treturn Localization.tr_key("ui.hud.p017") % _name_of(binding)',
    },
    {
        "name": "N-6 折叠改坏统计口径（row_count 跟着可见行走）",
        "file": CARTER,
        "test": TEST,
        "old": '\t\t\t_row_count += 1\n\t\t\tif collapsed:\n\t\t\t\tcontinue\n',
        "new": '\t\t\tif collapsed:\n\t\t\t\tcontinue\n\t\t\t_row_count += 1\n',
    },
    {
        "name": "N-7 手风琴失效（多组可同时展开，+100 行没上限）",
        "file": TOKEN,
        "test": TEST,
        "old": '\t_expanded_group = "" if _expanded_group == key else key',
        "new": '\t_expanded_group = key  # 负向注入：只能展开、收不回',
    },
    {
        "name": "N-8 过滤不裁剪（过滤条只是摆设）",
        "file": TOKEN,
        "test": TEST,
        "old": '\t\tif bool((row as Dictionary).get("alive", false)) == (_filter == FILTER_ALIVE):',
        "new": "\t\tif true:  # 负向注入：过滤不生效",
    },
]


def run_case(case: dict) -> tuple[bool, str]:
    path: Path = case["file"]
    original = path.read_text(encoding="utf-8")
    if case["old"] not in original:
        return False, "注入点未找到（代码已变更，需更新脚本）"
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
        path.write_text(original, encoding="utf-8")


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
