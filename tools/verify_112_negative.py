"""负向验证：确认如意重掷取优（工程 112）的断言真的有牙。

112 的风险全在「改错了没人报错」这一类：
  · 零如意时多掷一次 ⇒ 所有玩家的重铸结果整体漂移，但画面看起来一切正常；
  · 取优写成「取第一个 / 取最后一个」 ⇒ 界面提示写着取最优，实际随机；
  · 权重表写错 ⇒ 铁如意与玉如意完全等价，玩家只买便宜的；
  · 提前扣如意 ⇒ 金币不足时如意没了、装备没变（这一条玩家一发现就会炸）；
  · 非保星模式也吃如意 ⇒ 四紫升紫的「件数换概率」被绕过；
  · 保星取优根本没接上 ⇒ 花了四枚钻石如意，产物和不投完全一样；
  · 启动校验失守 ⇒ 上面几种数据错法都不会在启动时被发现。

每条破坏都必须让**对应的那一条**断言变红 ——「随便红了」不算。

A 组（跑测试，断言红在对的 label）
N-1 零如意也多掷一次（循环改成 tries + 1）      → 「零如意时随机流消耗必须与单次重掷完全相同」
N-2 取优改成取最后一个                          → 「取优结果必须等于」
N-3 铁如意权重 0.5 → 1                          → 「的重掷权重应为」
N-4 如意提前到金币校验之前扣                     → 「金币不足时如意一枚都不应扣」
N-5 非保星模式也吃如意                          → 「非保星模式不得消耗如意」
N-6 保星不调取优                                → 「投 17 次的产物词条不应与只掷 1 次完全相同」
N-9 如意格改回一行四列（面板被撑宽）             → 「内容区最小宽度不应超过设计宽度 520」

B 组（跑 --quit，断言启动校验报错）
N-7 删掉 rune_gold 的 rerollWeight              → 启动输出含「缺少 rerollWeight」
N-8 两档权重重复（gold 也写 1）                  → 启动输出含「rerollWeight 重复」

跑法：python3 tools/verify_112_negative.py
"""

from __future__ import annotations

import re
import shutil
import signal
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNES = ROOT / "data/runes.json"
CHARGE = ROOT / "scripts/systems/rune_charge.gd"
STATE = ROOT / "autoload/game_state.gd"
REFORGE_PANEL = ROOT / "scripts/ui/reforge_panel.gd"
RUNNER = ROOT / "tools/run_isolated_tests.py"
GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")

TEST = "RuneRerollTest"
FILES = [RUNES, CHARGE, STATE, REFORGE_PANEL]

## 🔴 上一轮被 SIGTERM / SIGKILL 打断时 `finally` 跑不到，破坏会留在文件里。
## 它一旦留下，下一轮的「基线」就是被改坏的代码 —— 负向从此永远判「基线不绿」，
## 而人很容易把它当成「偶发」跳过，于是带着 N-4 的「提前扣如意」去提交。
## 这里把原始内容落盘，启动时先还原残留（本文件第一版就踩过：N-4 的注入留在了
## `if gold < price:` 之前，表现为「10 枚投 2 枚剩 6 枚」）。
BACKUP = Path("/tmp/verify_112_originals")


def restore_previous_backup() -> None:
    if not BACKUP.exists():
        return
    restored = 0
    for path in FILES:
        saved = BACKUP / path.name
        if saved.exists():
            path.write_text(saved.read_text(encoding="utf-8"), encoding="utf-8")
            restored += 1
    shutil.rmtree(BACKUP, ignore_errors=True)
    if restored:
        print(f"⚠ 检测到上次被中断的残留备份，已还原 {restored} 个文件（否则会污染基线）\n")


def _on_signal(_signum, _frame) -> None:
    # 转成 SystemExit，让 finally 有机会还原文件（SIGKILL 拦不住，靠上面的备份兜）。
    raise SystemExit(130)


signal.signal(signal.SIGTERM, _on_signal)
signal.signal(signal.SIGINT, _on_signal)


def replace_once(text: str, old: str, new: str) -> str:
    """替换并断言锚点**唯一命中** —— 锚点漂移会让负向「什么都没改」然后照常绿。"""
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"⚠ 锚点命中 {count} 次（要求恰好 1 次），负向无效：{old[:70]!r}")
    return text.replace(old, new, 1)


# ---- A 组：跑隔离测试 ----

CASES = [
    (
        "N-1 零如意也多掷一次（随机流整体漂移）",
        "零如意时随机流消耗必须与单次重掷完全相同",
        STATE,
        # 🔴 只改循环次数是**没牙**的：`_roll_affixes_best` 开头有 `if tries <= 1` 直返，
        # 零如意根本进不到循环。第一版就漏了这一点，8 条里唯独这条仍绿。
        # 必须同时打断那条直返，才能让「零如意多掷一次」真的发生。
        lambda t: replace_once(
            replace_once(
                t,
                "\tif tries <= 1:\n\t\treturn ItemFactory.reroll_affixes(item, rng, locked_stats, floor)",
                "\tif tries < 0:\n\t\treturn ItemFactory.reroll_affixes(item, rng, locked_stats, floor)",
            ),
            "\tfor _i in range(tries):",
            "\tfor _i in range(tries + 1):",
        ),
    ),
    (
        "N-2 取优改成取最后一个（提示说取最优，实际随机）",
        "取优结果必须等于",
        CHARGE,
        lambda t: replace_once(t, "\tvar best: Dictionary = samples[0]",
                               "\tvar best: Dictionary = samples[samples.size() - 1]"),
    ),
    (
        "N-3 铁如意权重改成 1（与玉如意等价）",
        "的重掷权重应为",
        RUNES,
        lambda t: replace_once(t, '"rerollWeight": 0.5', '"rerollWeight": 1.0'),
    ),
    (
        "N-4 如意提前到金币校验之前扣（失败也不退）",
        "金币不足时如意一枚都不应扣",
        STATE,
        lambda t: replace_once(
            t,
            "\tif gold < price:\n\t\treturn _reforge_fail(Localization.tr_key(\"msg.game_state.p037\")",
            "\t_consume_rune_uses(rune_charge.get(\"uses\", []))\n"
            "\tif gold < price:\n\t\treturn _reforge_fail(Localization.tr_key(\"msg.game_state.p037\")"),
    ),
    (
        "N-5 非保星模式也吃如意（四紫升紫的件数换概率被绕过）",
        "非保星模式不得消耗如意",
        STATE,
        lambda t: replace_once(t, "\tif mode == EquipmentFusion.STAR_TRANSFER:\n\t\trune_charge = RuneCharge.plan",
                               "\tif mode != \"\":\n\t\trune_charge = RuneCharge.plan"),
    ),
    (
        "N-6 保星不调取优（花了四枚钻石如意，产物和不投一样）",
        "投 17 次的产物词条不应与只掷 1 次完全相同",
        STATE,
        lambda t: replace_once(t, "\t\tif tries > 1:\n\t\t\t_reroll_output_best(output, rng, tries)",
                               "\t\tif tries > 999:\n\t\t\t_reroll_output_best(output, rng, tries)"),
    ),
    (
        "N-9 如意格排成一行四列（把面板最小宽度顶到 588）",
        "内容区最小宽度不应超过设计宽度 520",
        REFORGE_PANEL,
        # 🔴 只能改 `columns`，不能把 `_rune_row` 换成 HBoxContainer：
        # 变量声明是 `GridContainer`，换类型是编译错误，负向会退化成「脚本 load 失败」，
        # 于是「红在对的断言上」变成「红在任何地方」（坑 76 同族）。
        lambda t: replace_once(t, "\t_rune_row.columns = 2", "\t_rune_row.columns = 4"),
    ),
]

# ---- B 组：跑启动校验 ----

BOOT_CASES = [
    (
        "N-7 删掉 rune_gold 的 rerollWeight（启动校验须拦下）",
        "缺少 rerollWeight",
        RUNES,
        lambda t: replace_once(t, ' "rerollWeight": 2, ', " "),
    ),
    (
        "N-8 两档权重重复（gold 也写 1）",
        "rerollWeight 重复",
        RUNES,
        lambda t: replace_once(t, '"rerollWeight": 2', '"rerollWeight": 1'),
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
    restore_previous_backup()
    originals = {path: path.read_text(encoding="utf-8") for path in FILES}
    BACKUP.mkdir(parents=True, exist_ok=True)
    for path, text in originals.items():
        (BACKUP / path.name).write_text(text, encoding="utf-8")

    if not baseline_green():
        shutil.rmtree(BACKUP, ignore_errors=True)
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
        shutil.rmtree(BACKUP, ignore_errors=True)

    tail_ok = baseline_green()
    print("还原后复跑：" + ("测试全绿 + 启动校验通过 ✅" if tail_ok else "⚠ 无效或无绿"))
    ok_all = failed == 0 and tail_ok and invalid == 0
    if invalid:
        print(f"⚠ 有 {invalid} 个用例因偶发启动失败判无效（非断言问题），请重跑确认")
    print("负向全部有牙 ✅" if ok_all else "存在假绿或无效轮次 ⚠")
    return 0 if ok_all else 1


if __name__ == "__main__":
    raise SystemExit(main())
