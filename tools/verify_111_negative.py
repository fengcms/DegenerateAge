"""负向验证：确认如意边框分色（工程 111）的断言真的有牙。

111 的风险全在「改错了没人报错」这一类：
  · 某一档 accent 漏配 ⇒ 该档回落青绿，玩家看到两档长得一样；
  · 色值写错一位 ⇒ 颜色还在、只是不是约定那一档；
  · 两档重复 ⇒ 数据看着合法、体验上等于没做（坑 65 同族）；
  · 回落落到白色 ⇒ 与空格子同色，等于没上色；
  · 只在背包写特例 ⇒ 同一只钻石如意在背包紫框、在仓库青框（比统一青色更困惑）；
  · 启动校验失守 ⇒ 上面几种数据错法都不会在启动时被发现。

每条破坏都必须让**对应的那一条**断言变红 ——「随便红了」不算。

A 组（跑测试，断言红在对的 label）
N-1 删掉 rune_diamond 的 accent            → RuneAccentTest「rune_diamond 的 accent 应为」
N-2 ACCENT_COLOR 的 jade 改错一位色值      → 同上「rune_jade 应为 rare 的装备品质色」
N-3 把 rune_iron 的 accent 改成和玉一样     → 同上「与 … 重复」
N-4 回落目标改成纯白                        → 同上「未登记的如意应回落」
N-5 背包改回自己写判定（绕过唯一入口）      → 同上「不得再直接调 ItemUtil.quality_color」

B 组（跑 --quit，断言启动校验报错）
N-6 accent 写成未登记值 "purple"            → 启动输出含「不合法」
N-7 两档 accent 重复（iron 与 jade 都是 steel） → 启动输出含「accent 重复」

跑法：python3 tools/verify_111_negative.py
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ITEM_UTIL = ROOT / "scripts/systems/item_util.gd"
RUNES = ROOT / "data/runes.json"
INVENTORY = ROOT / "scripts/ui/inventory_panel.gd"
RUNNER = ROOT / "tools/run_isolated_tests.py"
GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")

TEST = "RuneAccentTest"
FILES = [ITEM_UTIL, RUNES, INVENTORY]


def replace_once(text: str, old: str, new: str) -> str:
    """替换并断言锚点**唯一命中** —— 锚点漂移会让负向「什么都没改」然后照常绿。"""
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"⚠ 锚点命中 {count} 次（要求恰好 1 次），负向无效：{old[:60]!r}")
    return text.replace(old, new, 1)


# ---- A 组：跑隔离测试 ----

CASES = [
    (
        "N-1 删掉 rune_diamond 的 accent（该档回落青绿）",
        "rune_diamond 的 accent 应为",
        RUNES,
        lambda t: replace_once(t, '"accent": "diamond", ', ""),
    ),
    (
        "N-2 ACCENT_COLOR 的 jade 改错一位（颜色还在但不对档）",
        "rune_jade 应为 rare 的装备品质色",
        ITEM_UTIL,
        lambda t: replace_once(t, '"jade": Color("46c46a")', '"jade": Color("46c46b")'),
    ),
    (
        "N-3 铁如意 accent 改成和玉一样（两档重复）",
        "重复",
        RUNES,
        lambda t: replace_once(t, '"accent": "steel"', '"accent": "jade"'),
    ),
    (
        "N-4 回落目标改成纯白（与空格子同色，等于没上色）",
        "未登记的如意应回落",
        ITEM_UTIL,
        lambda t: replace_once(t,
                               'return ACCENT_COLOR.get(accent, KIND_COLOR["rune"])',
                               "return ACCENT_COLOR.get(accent, Color.WHITE)"),
    ),
    (
        "N-5 背包改回自己写判定（绕过唯一入口）",
        "不得再直接调 ItemUtil.quality_color",
        INVENTORY,
        lambda t: replace_once(
            t,
            "\treturn ItemUtil.item_accent_color(item)",
            "\tif String(item.get(\"kind\", \"\")) == \"equip\":\n"
            "\t\treturn ItemUtil.quality_color(String(item.get(\"quality\", \"common\")))\n"
            "\treturn ItemUtil.item_accent_color(item)"),
    ),
]

# ---- B 组：跑启动校验 ----

BOOT_CASES = [
    (
        "N-6 accent 写成未登记值 purple（启动校验须拦下）",
        "不合法",
        RUNES,
        lambda t: replace_once(t, '"accent": "steel"', '"accent": "purple"'),
    ),
    (
        "N-7 两档 accent 重复（启动校验须拦下）",
        "accent 重复",
        RUNES,
        lambda t: replace_once(t, '"accent": "jade"', '"accent": "steel"'),
    ),
]


# ---- 运行与解析 ----

def _is_valid(out: str, test: str) -> bool:
    """🔴 坑 76：Godot 偶发启动失败时输出里既无 PASS 也无 FAIL，
    此时 `failures_of()` 返回空，会被误读成「断言没有牙」。只认结论行。"""
    return (f"{test}: PASS" in out) or (f"{test}: FAIL" in out)


def run_test(test: str) -> str:
    out = ""
    for attempt in range(3):
        proc = subprocess.run([sys.executable, str(RUNNER), test],
                              cwd=ROOT, capture_output=True, text=True)
        out = proc.stdout + proc.stderr
        if _is_valid(out, test):
            return out
        print(f"    ⚠ 本轮无 PASS/FAIL 结论行（偶发启动失败），重试 {attempt + 1}/3")
    return out


def run_boot() -> str:
    proc = subprocess.run([str(GODOT), "--headless", "--path", str(ROOT), "--quit"],
                          capture_output=True, text=True, timeout=300)
    return proc.stdout + proc.stderr


def failures_of(out: str, test: str) -> list[str]:
    seen: list[str] = []
    for match in re.finditer(r"\[%s\] ([^\n]+)" % test, out):
        label = match.group(1).strip()
        if label and "失败" not in label and "全部通过" not in label and label not in seen:
            seen.append(label)
    return seen


def baseline_green() -> bool:
    out = run_test(TEST)
    if not _is_valid(out, TEST):
        print(f"⚠ {TEST} 基线连续多次无结论行（偶发启动失败），本轮验证无效，请重跑。")
        return False
    if "全部通过" not in out:
        print(f"⚠ {TEST} 基线不是绿的，先修基线再验负向：")
        for item in failures_of(out, TEST)[:8]:
            print("    " + item)
        return False
    boot = run_boot()
    if "配置校验通过" not in boot:
        print("⚠ 基线启动校验未通过（数据本身就有问题），先修基线：")
        print("    " + "\n    ".join([ln for ln in boot.splitlines() if "[runes]" in ln][:5]))
        return False
    return True


def main() -> int:
    originals = {path: path.read_text(encoding="utf-8") for path in FILES}

    if not baseline_green():
        return 1
    print("前置：未改动时测试全绿、启动校验通过 ✅\n")

    failed = 0
    invalid = 0
    try:
        for label, expect, path, mutate in CASES:
            for target, text in originals.items():          # 先还原**全部**
                target.write_text(text, encoding="utf-8")
            path.write_text(mutate(originals[path]), encoding="utf-8")
            out = run_test(TEST)
            if not _is_valid(out, TEST):
                print(f"{label}\n    → ⚠ 连续多次无结论行（偶发启动失败），本用例判无效")
                invalid += 1
                continue
            hits = failures_of(out, TEST)
            teeth = [h for h in hits if expect in h]
            ok = bool(teeth)
            print(f"{label}\n    → 期望红在「{expect}」：{'✅ 变红' if ok else '❌ 仍绿（断言无效）'}")
            if ok:
                print("      " + teeth[0][:170])
            else:
                failed += 1
                others = [h[:80] for h in hits if expect not in h]
                print("      实际红项：" + ("无" if not others else " / ".join(others[:4])))

        for label, expect, path, mutate in BOOT_CASES:
            for target, text in originals.items():
                target.write_text(text, encoding="utf-8")
            path.write_text(mutate(originals[path]), encoding="utf-8")
            out = run_boot()
            if "Godot Engine" not in out and "配置校验" not in out:
                print(f"{label}\n    → ⚠ 引擎没起来，本用例判无效")
                invalid += 1
                continue
            ok = expect in out
            print(f"{label}\n    → 期望启动输出含「{expect}」：{'✅ 报错' if ok else '❌ 静默通过'}")
            if ok:
                hit = [ln for ln in out.splitlines() if expect in ln]
                print("      " + hit[0][:170])
            else:
                failed += 1
    finally:
        for target, text in originals.items():
            target.write_text(text, encoding="utf-8")

    tail_ok = baseline_green()
    print("还原后复跑：" + ("测试全绿 + 启动校验通过 ✅" if tail_ok else "⚠ 无效或无绿"))
    ok_all = failed == 0 and tail_ok and invalid == 0
    if invalid:
        print(f"⚠ 有 {invalid} 个用例因偶发启动失败判无效（非断言问题），请重跑确认")
    print("负向全部有牙 ✅" if ok_all else "存在假绿或无效轮次 ⚠")
    return 0 if ok_all else 1


if __name__ == "__main__":
    raise SystemExit(main())
