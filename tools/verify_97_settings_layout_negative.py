#!/usr/bin/env python3
"""工程 97 负向验证：设置面板分组层与统一行规格。

每个用例都**只改一处**，跑 `SettingsTest`，期望变红；每个用例开始前还原**所有**被改文件
（铁律：只还原当次那个 ⇒ 上一轮补丁留在盘上，第二次「变红」证明的不是想验的那条）。

判据必须是「结果」而不是「我改了代码」：
- 拆掉卡片层 / 卡片标题 ⇒ 卡片结构断言红（不是「代码里没有 style_card」）
- 只建第一组改键 ⇒ 29 条与 3 组小标题断言红
- 把 680 改回 600 ⇒ 高度断言红（在 1280×800 的独立视口里验，否则被 logical.y-64 夹住照样绿）
"""

from __future__ import annotations

import json
import subprocess
import sys
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PANEL = ROOT / "scripts/ui/settings_panel.gd"
LOC = ROOT / "data/localization.json"
TEST = "SettingsTest"
ORIGINALS = {PANEL: PANEL.read_text(encoding="utf-8"), LOC: LOC.read_text(encoding="utf-8")}


def restore() -> None:
    for path, text in ORIGINALS.items():
        path.write_text(text, encoding="utf-8")


def run_test(test: str = TEST) -> tuple[bool, str]:
    proc = subprocess.run(["python3", "tools/run_isolated_tests.py", test],
                          cwd=ROOT, capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    return (test + ": PASS" in out) and proc.returncode == 0, out


def first_failure(out: str) -> str:
    for line in out.splitlines():
        if "ERROR: [" in line:
            return line.strip()[:180]
    for line in out.splitlines():
        if "FAIL" in line or "SCRIPT ERROR" in line:
            return line.strip()[:180]
    return "(未捕获失败行)"


def patch_panel(old: str, new: str) -> None:
    text = ORIGINALS[PANEL]
    if text.count(old) != 1:
        raise SystemExit("锚点不唯一或缺失（%d 次）：%r" % (text.count(old), old[:60]))
    PANEL.write_text(text.replace(old, new), encoding="utf-8")


def patch_localization(key: str, value: str) -> None:
    data = json.loads(ORIGINALS[LOC], object_pairs_hook=OrderedDict)
    if key not in data:
        raise SystemExit("键不存在：%s" % key)
    data[key] = value
    LOC.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


CARD_BODY = '''	var panel := PanelContainer.new()
	PanelChrome.style_card(panel)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
'''

CARD_TITLE_BLOCK = '''	if not title_key.is_empty():
		var title := Label.new()
		title.text = Localization.tr_key(title_key)
		PanelChrome.style_section(title)
		box.add_child(title)
'''

SECTION_TITLE_BLOCK = '''	var title := Label.new()
	title.text = Localization.tr_key(title_key)
	PanelChrome.style_section(title)
	_key_list.add_child(title)
'''


def case_no_card() -> None:
    """N-1 卡片层整个拆掉：控件回到「页签下直接平铺」的老样子。"""
    patch_panel(CARD_BODY, "\tvar box: VBoxContainer = parent\n")


def case_no_card_title() -> None:
    """N-2 卡片保留但不给标题：分组有框无名字，玩家仍读不出层次。"""
    patch_panel(CARD_TITLE_BLOCK, "")


def case_first_group_only() -> None:
    """N-3 只建第一组改键：29 条变 7 条，后 22 条凭空消失。"""
    patch_panel("\tfor i in KEY_GROUPS.size():", "\tfor i in range(1):")


def case_no_section_title() -> None:
    """N-4 改键分组建了，但不加小标题：仍旧是一长条看不清分组。"""
    patch_panel(SECTION_TITLE_BLOCK, "")


def case_tab_name_reverted() -> None:
    """N-5 页签名改回「控制」：锚点找不到页，等于换页签这件事没人守。"""
    patch_localization("ui.settings_panel.p038", "控制")


def case_height_reverted() -> None:
    """N-6 面板高度上限改回 600：拆卡后游戏页要多滚 2 行。"""
    patch_panel("const PANEL_MAX_HEIGHT := 680.0", "const PANEL_MAX_HEIGHT := 600.0")


def case_hint_not_demoted() -> None:
    """N-7 注解字号回到正文大小：注解又变成「一行控件」。"""
    patch_panel("const HINT_FONT_SIZE := 14", "const HINT_FONT_SIZE := 16")


def case_caption_width() -> None:
    """N-8 左标签列不统一（150 → 160）：控件起点又错开。"""
    patch_panel("const CAPTION_WIDTH := 150.0", "const CAPTION_WIDTH := 160.0")


def case_checkbox_initial_state() -> None:
    """N-9 勾选框不再读初值：已开启的档打开面板显示成未勾选（工程 97 重排时真踩过）。"""
    patch_panel('\t_auto_sell_check.button_pressed = bool(GameState.settings.get("autoSellEquipOnPickup", false))\n', "")
    globals()["_CASE_TEST"] = "AutoSellPickupTest"


CASES = [
    ("N-1 拆掉卡片层", case_no_card),
    ("N-2 卡片不给标题", case_no_card_title),
    ("N-3 只建第一组改键", case_first_group_only),
    ("N-4 改键不加分组小标题", case_no_section_title),
    ("N-5 页签名改回「控制」", case_tab_name_reverted),
    ("N-6 面板高度改回 600", case_height_reverted),
    ("N-7 注解字号回到 16", case_hint_not_demoted),
    ("N-8 左标签列改 160", case_caption_width),
    ("N-9 勾选框丢初值", case_checkbox_initial_state),
]


def main() -> int:
    restore()
    ok, out = run_test()
    if not ok:
        print("前置条件：基线应为绿，实际红")
        print(first_failure(out))
        return 1
    print("前置：基线 SettingsTest 为绿 ✅\n")

    failures = 0
    for label, apply_case in CASES:
        restore()
        globals()["_CASE_TEST"] = TEST
        apply_case()
        case_test = globals().get("_CASE_TEST", TEST)
        ok, out = run_test(case_test)
        detail = first_failure(out)
        # 「变红但没有失败输出」不是证据（进程被杀 / 偶发空输出都会这样），必须重试一次；
        # 仍无输出的判无效，绝不能记成「✅ 变红」—— 那等于用一次崩溃冒充断言的牙。
        if not ok and detail == "(未捕获失败行)":
            ok, out = run_test(case_test)
            detail = first_failure(out)
        if ok:
            print("%-26s ❌ 仍绿（断言无效）" % label)
            failures += 1
        elif detail == "(未捕获失败行)":
            print("%-26s ⚠ 变红但无失败输出（不接受为证据）" % label)
            failures += 1
        else:
            print("%-26s ✅ 变红：%s" % (label, detail))
    restore()
    ok, out = run_test()
    print("\n还原后复跑：%s" % ("绿 ✅" if ok else "红 ❌ " + first_failure(out)))
    if not ok:
        failures += 1
    if failures:
        print("\n负向验证未全部通过：%d 项" % failures)
        return 1
    print("负向 %d 条全部有牙，还原后复绿 ✅" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
