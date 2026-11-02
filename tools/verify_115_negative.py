"""负向验证：确认 UI 尺寸非法值防线（工程 115）的断言真的有牙。

115 修的是「UI 尺寸变成 NaN / INF 后一路铺到渲染层导致引擎 C++ 层闪退」。
它的风险全在「改错了没人报错」这一类：

  · 守卫写成 `size.x <= 0.0` —— 看起来在防零尺寸，实际对 NaN / INF 一律放行；
  · 倍率入口透传 NaN —— `clampf(NAN, ..)` 实测原样返回 nan，clamp 不是兜底；
  · 显示倍率的兜底漏掉 —— 只有 uiScale 兜住了，手动显示倍率仍能带进 NaN；
  · 一刀切成「永不重排」—— 崩溃没了，但拖窗口后面板不再跟随（过修）。

每条破坏都必须让**对应的那一条**断言变红 ——「随便红了」不算。

N-1 判据退化成 `size.x > 0 && size.y > 0`（NaN / INF 全放行）
        → 「NaN 尺寸必须判为不可用」/「INF 尺寸必须判为不可用」
N-2 去掉 ui_scale_value 对 uiScale 的有限性兜底
        → 「uiScale 为 NaN 时倍率必须是有限值」
N-3 去掉 ui_scale_value 对显示倍率的有限性兜底
        → 「手动显示倍率为 NaN 时必须回落 1.0」

不加独立注入的一条（有意为之，非遗漏）：
  · 「端到端：倍率非法时控件尺寸仍必须有限」属**多层防御的最后一道**。
    单点破坏（只删某一道）会被前一道拦住 —— 这正是分层的意义，
    强行构造三处同时损坏的注入只会误伤，收益为零。

跑法：python3 tools/verify_115_negative.py
"""

from __future__ import annotations

import shutil
import signal
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "scripts/systems/settings_runtime.gd"
GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")
SCENE = "res://tests/NanGuardTest.tscn"

TEST = "NanGuardTest"
FILES = [RUNTIME]
BACKUP = Path("/tmp/verify_115_originals")


def restore_previous_backup() -> None:
    """上一轮被 SIGTERM / SIGKILL 打断时 finally 跑不到，破坏会留在文件里。

    一旦留下，下一轮的「基线」就是被改坏的代码 —— 负向从此永远判「基线不绿」，
    而人很容易把它当成「偶发」跳过。启动时先还原残留（坑 102）。
    """
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


CASES = [
    (
        "N-1 判据退回 `<= 0.0` 写法（NaN / INF 全放行）",
        "NaN 尺寸必须判为不可用",
        RUNTIME,
        # 🔴 必须还原成**原始 bug 的形态** `not (x <= 0 or y <= 0)`。
        # 写成 `x > 0 and y > 0` 是**没牙**的：`NAN > 0` 为 false，反而把 NaN 拦住了，
        # 只会红在 INF 那条上（第一版就踩了，判成「红错断言」）。
        # 两者在浮点语义下并不等价 —— 这正是本 bug 的全部要害。
        lambda t: replace_once(
            t,
            "\treturn is_finite(size.x) and is_finite(size.y) and size.x > 0.0 and size.y > 0.0",
            "\treturn not (size.x <= 0.0 or size.y <= 0.0)",
        ),
    ),
    (
        "N-2 去掉 uiScale 的有限性兜底（NaN 直接透传）",
        "uiScale 为 NaN 时倍率必须是有限值",
        RUNTIME,
        lambda t: replace_once(
            t,
            "\tif not is_finite(raw):\n\t\traw = 1.0\n",
            "",
        ),
    ),
    (
        "N-3 去掉显示倍率的有限性兜底",
        "手动显示倍率为 NaN 时必须回落 1.0",
        RUNTIME,
        lambda t: replace_once(
            t,
            "\tif not is_finite(factor) or factor <= 0.0:\n\t\tfactor = 1.0\n",
            "\tif factor <= 0.0:\n\t\tfactor = 1.0\n",
        ),
    ),
]


def _is_valid(out: str, test: str) -> bool:
    """🔴 坑 76：Godot 偶发启动失败时输出里既无 PASS 也无 FAIL，
    此时会被误读成「断言没有牙」。只认结论行。"""
    return (f"{test}: PASS" in out) or (f"{test}: FAIL" in out)


def run_test() -> str:
    """直跑测试场景（≈5 s）。不走 `run_isolated_tests.py`：它每次重建隔离项目要 130 s，
    5 次就会撞外部超时被 SIGKILL，反而留下注入残留（坑 102）。

    安全性：`NanGuardTest.tscn` 位于 `res://tests/`，`SaveManager._is_test_scene()` 为真、
    `_autosave_allowed()` 恒假；且本用例只改内存里的 `GameState.settings`，不读档不写档。
    """
    out = ""
    for attempt in range(3):
        proc = subprocess.run([str(GODOT), "--path", str(ROOT), SCENE, "--quit-after", "400"],
                              cwd=ROOT, capture_output=True, text=True, timeout=180)
        out = proc.stdout + proc.stderr
        if _is_valid(out, TEST):
            return out
        print(f"    ⚠ 本轮无 PASS/FAIL 结论行（偶发启动失败），重试 {attempt + 1}/3")
    return out


def main() -> int:
    restore_previous_backup()
    originals = {path: path.read_text(encoding="utf-8") for path in FILES}

    print("── 基线：未注入时必须全绿 ──")
    base = run_test()
    if f"{TEST}: PASS" not in base:
        print(base[-2000:])
        print(f"❌ 基线不绿，负向无意义（{TEST} 应为 PASS）")
        return 1
    print(f"✅ 基线 {TEST}: PASS\n")

    BACKUP.mkdir(parents=True, exist_ok=True)
    for path, text in originals.items():
        (BACKUP / path.name).write_text(text, encoding="utf-8")

    failures: list[str] = []
    try:
        for name, label, path, mutate in CASES:
            print(f"── {name} ──")
            original = originals[path]
            try:
                path.write_text(mutate(original), encoding="utf-8")
                out = run_test()
            finally:
                path.write_text(original, encoding="utf-8")

            if f"{TEST}: FAIL" not in out:
                print(f"  ❌ 没牙：注入后仍为 PASS\n{out[-1200:]}")
                failures.append(f"{name}（未变红）")
                continue
            if label not in out:
                print(f"  ❌ 红错了断言：期望「{label}」\n{out[-1200:]}")
                failures.append(f"{name}（红在别的断言上）")
                continue
            print(f"  ✅ 如期变红：{label}\n")
    finally:
        for path, text in originals.items():
            path.write_text(text, encoding="utf-8")
        shutil.rmtree(BACKUP, ignore_errors=True)

    print("── 还原后复跑基线 ──")
    after = run_test()
    if f"{TEST}: PASS" not in after:
        print(after[-2000:])
        print("❌ 还原后基线不绿：文件可能没还原干净")
        return 1
    print(f"✅ 还原后 {TEST}: PASS\n")

    total = len(CASES)
    if failures:
        print(f"负向验证失败 {len(failures)}/{total}：")
        for item in failures:
            print(f"  · {item}")
        return 1
    print(f"负向验证 {total}/{total} 全部有牙 ✅")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
