"""负向验证：确认随身铁匠（工程 108）的断言真的有牙。

背景：108 交付的是「第四个随身道具 + 复用铁匠面板 + 随身加价」。这三件事错起来
**几乎都是静默的**：
  · 面板登记漏了 ⇒ 双击道具什么都不发生（不报错）；
  · 服务费只改了扣费没改显示 ⇒ 按钮写一个数、实扣另一个数（不报错，玩家对账才发现）；
  · 任务 `unlocks` 写成单数 ⇒ 读档把档判坏（不报错）。

所以每条破坏都必须让**对应的那一条**断言变红 —— 「随便红了」不算，那说明判据之间互相污染。
另外每条用例只改**一个** anchor，改之前断言锚点唯一命中；每轮先还原全部被改文件。

N-1 删掉 `PanelRouter.PANELS["blacksmith"]`        → 用例 2「blacksmith 应登记在 PANELS」
N-2 道具 `panelId` 改成 `blacksmth`（脏 id）         → 用例 1「panelId 应为 blacksmith」
     ⚠ 这一条**同时**要验启动校验层：`--quit` 必须打印「未登记」WARNING。
     实测它在 `--quit` 层、**不在 `--import` 层** —— `--import` 只扫资源不跑 autoload 校验。
     而且它是 **WARNING 不是硬错误**，游戏照样启动（`panel_router.gd` 原注释写「启动期就报错」，
     实际只是警告 —— 这条差别记在 08 坑清单）。
N-3 `blacksmith_panel.set_open` 的 `if _portable` 反转 → 用例 4「随身模式应直接显示服务卡」
N-4 任务 `requiresLevel` 80 → 79                    → 用例 6「requiresLevel 应为 80」
N-5 `reward.unlocks` 改成单数 `unlock`              → 用例 6「reward.unlocks 必须是数组」
N-6 升星**只改扣费、不改显示**（面板端去掉 apply）  → 用例 9「实扣 ≠ 按钮显示」
N-7 重铸**显示用截断 int()、扣费用 ceil**             → 用例 9「随身重铸实扣 ≠ 按钮显示」
    N-6 / N-7 是本轮唯一能守住「显示价 == 实扣」的机制，形态不同：
    前者完全不乘费率，后者乘了但取整方向不一致（差 1 金）。
    ⚠ 注入形态必须是「截断」而不是「round」：重铸 base 在当前数据下 mod 5 只会是 0 或 3
      （endgame.json baseGold=500 / levelFactor=0.75 / lockFactor=0.5），×1.2 分别是整数或小数 0.6，
      round 在两种情况下都**等于** ceil —— 用 round 注入会假绿（N-7 首轮实测「全部通过」）。

跑法：python3 tools/verify_108_negative.py
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ITEMS = ROOT / "data/miscItems.json"
QUESTS = ROOT / "data/quests.json"
ROUTER = ROOT / "scripts/systems/panel_router.gd"
PANEL = ROOT / "scripts/ui/blacksmith_panel.gd"
UPGRADE = ROOT / "scripts/ui/upgrade_panel.gd"
REFORGE = ROOT / "scripts/ui/reforge_panel.gd"
GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")
TEST = "PortableBlacksmithTest"
RUNNER = ROOT / "tools/run_isolated_tests.py"


# ---- 文本 / 数据变换 ----

def replace_once(text: str, old: str, new: str) -> str:
    """替换并断言锚点**唯一命中** —— 锚点漂移会让负向「什么都没改」然后照常绿。"""
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"⚠ 锚点命中 {count} 次（要求恰好 1 次），负向无效：{old[:60]!r}")
    return text.replace(old, new, 1)


def _roundtrip(text: str, mutate) -> str:
    data = json.loads(text)
    mutate(data)
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def dirty_panel_id(text: str) -> str:
    def mutate(rows) -> None:
        hits = 0
        for row in rows:
            if isinstance(row, dict) and row.get("id") == "tool_portable_blacksmith":
                if row.get("panelId") != "blacksmith":
                    raise SystemExit("⚠ panelId 已不是 blacksmith，负向无效")
                row["panelId"] = "blacksmth"
                hits += 1
        if hits != 1:
            raise SystemExit(f"⚠ 命中 {hits} 条道具（应为 1），负向无效")
    return _roundtrip(text, mutate)


def lower_quest_level(text: str) -> str:
    def mutate(rows) -> None:
        for row in rows:
            if isinstance(row, dict) and row.get("id") == "C7S01":
                if int(row.get("requiresLevel", 0)) != 80:
                    raise SystemExit("⚠ requiresLevel 已不是 80，负向无效")
                row["requiresLevel"] = 79
                return
        raise SystemExit("⚠ 找不到任务 C7S01")
    return _roundtrip(text, mutate)


def singular_unlock(text: str) -> str:
    def mutate(rows) -> None:
        for row in rows:
            if isinstance(row, dict) and row.get("id") == "C7S01":
                reward = row.get("reward", {})
                if "unlocks" not in reward:
                    raise SystemExit("⚠ reward 里没有 unlocks，负向无效")
                reward["unlock"] = reward.pop("unlocks")
                return
        raise SystemExit("⚠ 找不到任务 C7S01")
    return _roundtrip(text, mutate)


CASES = [
    ("N-1 删掉 PANELS[\"blacksmith\"]（面板没登记）",
     "blacksmith 应登记在 PANELS", ROUTER,
     lambda t: replace_once(t,
        '\t"blacksmith": {"ready": true, "title": "ui.panel.portable_blacksmith"},\n',
        "")),
    ("N-2 道具 panelId 改成 blacksmth（脏 id）",
     "panelId 应为 blacksmith", ITEMS,
     dirty_panel_id),
    ("N-3 set_open 的 if _portable 反转（随身走成回城）",
     "随身模式应直接显示服务卡", PANEL,
     lambda t: replace_once(t,
        "\t\tif _portable:\n\t\t\t# 直接进服务菜单",
        "\t\tif not _portable:\n\t\t\t# 直接进服务菜单")),
    ("N-4 任务 requiresLevel 80 → 79（门槛矮一档）",
     "requiresLevel 应为 80", QUESTS,
     lower_quest_level),
    ("N-5 reward.unlocks 改成单数 unlock（读档判档坏）",
     "reward.unlocks 必须是数组", QUESTS,
     singular_unlock),
    ("N-6 升星只改扣费、不改显示（面板端去掉费率）",
     "随身升星**实扣", UPGRADE,
     lambda t: replace_once(t,
        "\tvar price := ServiceFee.apply(Upgrade.cost(star), ServiceFee.rate_for(_portable))",
        "\tvar price := Upgrade.cost(star)")),
    ("N-7 重铸显示用截断、扣费用 ceil（差 1 金）",
     "随身重铸**实扣", REFORGE,
     lambda t: replace_once(t,
        "\tvar price := ServiceFee.apply(Reforge.cost(Equipment.level_req(item), _locked.size()),\n\t\tServiceFee.rate_for(_portable))",
        "\tvar price := int(float(Reforge.cost(Equipment.level_req(item), _locked.size()))\n\t\t* ServiceFee.rate_for(_portable))")),
]

# 每个用例会碰到的文件（还原时要全部写回）
FILES = [ITEMS, QUESTS, ROUTER, PANEL, UPGRADE, REFORGE]


# ---- 运行与解析 ----

def _is_valid(out: str) -> bool:
    """🔴 坑 76：Godot 偶发导入/启动失败时，输出里既没有 `{TEST}: PASS` 也没有
    `{TEST}: FAIL` —— 此时 `failures_of()` 返回空，会被误读成「断言没有牙」。
    判据只认运行器 `run_isolated_tests.py` 第 349 行打印的结论行（两种都算有效）。
    """
    return (f"{TEST}: PASS" in out) or (f"{TEST}: FAIL" in out)


def run_test() -> str:
    out = ""
    for attempt in range(3):
        proc = subprocess.run([sys.executable, str(RUNNER), TEST],
                              cwd=ROOT, capture_output=True, text=True)
        out = proc.stdout + proc.stderr
        if _is_valid(out):
            return out
        print(f"    ⚠ 本轮无 PASS/FAIL 结论行（偶发启动失败），重试 {attempt + 1}/3")
    # 三次都无效：返回最后一次输出，让上层判红而非静默当绿。
    return out


def failures_of(out: str) -> list[str]:
    """抓测试自己 push_error 出来的断言标签（去重保序）。"""
    seen: list[str] = []
    for match in re.finditer(r"\[%s\] ([^\n]+)" % TEST, out):
        label = match.group(1).strip()
        if label and "失败" not in label and label not in seen:
            seen.append(label)
    return seen


def bootstrap_warnings() -> str:
    """启动校验层：脏 panelId 应在 `--quit` 打印「未登记」。
    ⚠ 同样防坑 76：`--quit` 偶发空输出时重试，否则会把「没启动起来」误判成「没报警」。
    """
    out = ""
    for _ in range(3):
        proc = subprocess.run([str(GODOT), "--headless", "--path", str(ROOT), "--quit"],
                              cwd=ROOT, capture_output=True, text=True)
        out = proc.stdout + proc.stderr
        if out.strip():
            return out
    return out


def main() -> int:
    originals = {path: path.read_text(encoding="utf-8") for path in FILES}

    # 前置：不改任何东西时必须全绿，否则后面的「变红」不说明任何问题。
    out = run_test()
    if not _is_valid(out):
        print("⚠ 基线连续多次无 PASS/FAIL 结论行（偶发启动失败），本轮验证无效，请重跑。")
        return 1
    if "全部通过" not in out:
        print("⚠ 基线不是绿的，先修基线再验负向：")
        for item in failures_of(out)[:8]:
            print("    " + item)
        return 1
    print("前置：未改动时十条断言全绿 ✅")

    failed = 0
    invalid = 0
    try:
        for label, expect, path, mutate in CASES:
            for target, text in originals.items():        # 先还原**全部**
                target.write_text(text, encoding="utf-8")
            path.write_text(mutate(originals[path]), encoding="utf-8")
            out = run_test()
            if not _is_valid(out):
                print(f"{label}\n    → ⚠ 连续多次无结论行（偶发启动失败），本用例判无效")
                invalid += 1
                continue
            hits = failures_of(out)
            teeth = [h for h in hits if expect in h]
            ok = bool(teeth)
            print(f"{label}\n    → 期望红在「{expect}」：{'✅ 变红' if ok else '❌ 仍绿（断言无效）'}")
            if ok:
                print("      " + teeth[0][:170])
            else:
                failed += 1
                others = [h[:80] for h in hits if expect not in h]
                print("      实际红项：" + ("无" if not others else " / ".join(others[:4])))
            # N-2 额外验启动校验层
            if label.startswith("N-2"):
                boot = bootstrap_warnings()
                boot_ok = "未登记" in boot and "blacksmth" in boot
                print("    → 启动校验（--quit 层）：" + ("✅ 报出未登记 ✅" if boot_ok else "❌ 没报"))
                if not boot_ok:
                    failed += 1
    finally:
        for target, text in originals.items():
            target.write_text(text, encoding="utf-8")

    out = run_test()
    tail_ok = _is_valid(out) and "全部通过" in out
    print("还原后复跑：" + ("十条全绿 ✅" if tail_ok else
        "⚠ 无效或无绿 → " + (" / ".join(failures_of(out))[:300] or "无结论行")))
    ok_all = failed == 0 and tail_ok and invalid == 0
    if invalid:
        print(f"⚠ 有 {invalid} 个用例因偶发启动失败判无效（非断言问题），请重跑确认")
    print("负向全部有牙 ✅" if ok_all else "存在假绿或无效轮次 ⚠")
    return 0 if ok_all else 1


if __name__ == "__main__":
    raise SystemExit(main())
