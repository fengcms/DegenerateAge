"""负向验证：确认批量兑换弹框（工程 110）的断言真的有牙。

110 全部改动都在 UI 层，风险因此集中在「玩家能感觉到、但没人会报错」的地方：
  · 输入过滤失效 ⇒ 粘贴「1e5」变成 15 次，玩家以为换 100000 次；
  · 关闭不释放焦点 ⇒ `world_controls_blocked()` 恒真，角色永久不能动；
  · Esc 不吃掉事件 ⇒ 想取消兑换，连仓库面板一起关了；
  · 超限不禁用确认 ⇒ 点了才报错（或者更糟：悄悄换掉能换的部分）；
  · 批量落账漏乘次数 ⇒ 说好换 100 块，只到账 1 块。

每条破坏都必须让**对应的那一条**断言变红 ——「随便红了」不算。

N-1 删掉「超过上限」的禁用判断              → PanelAmountDialogTest「超过上限时确认按钮必须禁用」
N-2 删掉 popup() 的 grab_focus               → 同上「打开时应聚焦输入框」
N-3 删掉 Esc 的 set_input_as_handled()      → 同上「Esc 必须 set_input_as_handled」
N-4 删掉 text_changed 的非数字过滤          → 同上「非数字应被过滤」
N-5 plan() 的 to_count 漏乘 times           → GoldExchangeTest「应得 7 块金条」

⚠ N-2 的形态说明：最初写的是「删掉 close() 里的 `release_focus()`」，实测**删了照样绿** ——
Godot 在控件隐藏时会自动释放焦点，那一行是无效防御。按「负向必须有牙」的口径，
把无效防御删掉、把断言改成能红的「打开时必须聚焦」（删 `grab_focus` 才真的会让
玩家敲的数字变成快捷栏操作）。

⚠ N-5 的形态说明：最初想注入「把批量拆成循环调 exchange(id,1)」，但实测那**不会变红** ——
逐次落账的最终状态与一次批量完全一致（99+1 两格），只有「中途失败会留下半成品」与
「100 次 UI 广播」这两点差别，而这两点在当前断言里都不可观测。
所以负向改成「漏乘 times」：这才是批量路径上真正会犯、且必然红在数值上的错。

跑法：python3 tools/verify_110_negative.py
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIALOG = ROOT / "scripts/ui/panel_amount_dialog.gd"
LOGIC = ROOT / "scripts/systems/gold_exchange.gd"
RUNNER = ROOT / "tools/run_isolated_tests.py"

DIALOG_TEST = "PanelAmountDialogTest"
LOGIC_TEST = "GoldExchangeTest"
TESTS = [DIALOG_TEST, LOGIC_TEST]
FILES = [DIALOG, LOGIC]


def replace_once(text: str, old: str, new: str) -> str:
    """替换并断言锚点**唯一命中** —— 锚点漂移会让负向「什么都没改」然后照常绿。"""
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"⚠ 锚点命中 {count} 次（要求恰好 1 次），负向无效：{old[:60]!r}")
    return text.replace(old, new, 1)


CASES = [
    (
        "N-1 删掉「超过上限」的禁用判断（点了才报错）",
        DIALOG_TEST,
        "超过上限时确认按钮必须禁用",
        DIALOG,
        lambda t: replace_once(
            t,
            "\telif times > max_times:\n"
            "\t\treason = Localization.tr_key(\"ui.warehouse_panel.p029\") % max_times\n",
            ""),
    ),
    (
        "N-2 删掉 popup() 的 grab_focus（玩家敲的数字全变成快捷栏操作）",
        DIALOG_TEST,
        "打开时应聚焦输入框",
        DIALOG,
        lambda t: replace_once(t, "\t_edit.grab_focus.call_deferred()\n", ""),
    ),
    (
        "N-3 删掉 Esc 的 set_input_as_handled()（一次关两层）",
        DIALOG_TEST,
        "Esc 必须 set_input_as_handled",
        DIALOG,
        lambda t: replace_once(t, "\t\tget_viewport().set_input_as_handled()\n", ""),
    ),
    (
        "N-4 删掉非数字过滤（「1e5」变成 15 次）",
        DIALOG_TEST,
        "非数字应被过滤",
        DIALOG,
        lambda t: replace_once(
            t,
            "\t\tif ch >= \"0\" and ch <= \"9\":\n"
            "\t\t\tfiltered += ch\n",
            "\t\tfiltered += ch\n"),
    ),
    (
        "N-5 plan() 的 to_count 漏乘 times（换 7 块只到账 1 块）",
        LOGIC_TEST,
        "应得 7 块金条",
        LOGIC,
        lambda t: replace_once(
            t,
            "\tvar to_count := int(row.get(\"toCount\", 0)) * times\n",
            "\tvar to_count := int(row.get(\"toCount\", 0))\n"),
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


def failures_of(out: str, test: str) -> list[str]:
    seen: list[str] = []
    for match in re.finditer(r"\[%s\] ([^\n]+)" % test, out):
        label = match.group(1).strip()
        if label and "失败" not in label and "全部通过" not in label and label not in seen:
            seen.append(label)
    return seen


def baseline_green() -> bool:
    for test in TESTS:
        out = run_test(test)
        if not _is_valid(out, test):
            print(f"⚠ {test} 基线连续多次无结论行（偶发启动失败），本轮验证无效，请重跑。")
            return False
        if "全部通过" not in out:
            print(f"⚠ {test} 基线不是绿的，先修基线再验负向：")
            for item in failures_of(out, test)[:8]:
                print("    " + item)
            return False
    return True


def main() -> int:
    originals = {path: path.read_text(encoding="utf-8") for path in FILES}

    if not baseline_green():
        return 1
    print("前置：未改动时两个测试全绿 ✅")

    failed = 0
    invalid = 0
    try:
        for label, test, expect, path, mutate in CASES:
            for target, text in originals.items():          # 先还原**全部**
                target.write_text(text, encoding="utf-8")
            path.write_text(mutate(originals[path]), encoding="utf-8")
            out = run_test(test)
            if not _is_valid(out, test):
                print(f"{label}\n    → ⚠ 连续多次无结论行（偶发启动失败），本用例判无效")
                invalid += 1
                continue
            hits = failures_of(out, test)
            teeth = [h for h in hits if expect in h]
            ok = bool(teeth)
            print(f"{label}\n    → 期望红在「{expect}」：{'✅ 变红' if ok else '❌ 仍绿（断言无效）'}")
            if ok:
                print("      " + teeth[0][:170])
            else:
                failed += 1
                others = [h[:80] for h in hits if expect not in h]
                print("      实际红项：" + ("无" if not others else " / ".join(others[:4])))
    finally:
        for target, text in originals.items():
            target.write_text(text, encoding="utf-8")

    tail_ok = baseline_green()
    print("还原后复跑：" + ("两个测试全绿 ✅" if tail_ok else "⚠ 无效或无绿"))
    ok_all = failed == 0 and tail_ok and invalid == 0
    if invalid:
        print(f"⚠ 有 {invalid} 个用例因偶发启动失败判无效（非断言问题），请重跑确认")
    print("负向全部有牙 ✅" if ok_all else "存在假绿或无效轮次 ⚠")
    return 0 if ok_all else 1


if __name__ == "__main__":
    raise SystemExit(main())
