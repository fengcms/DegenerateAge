"""负向验证：确认仓库兑换台（工程 109）的断言真的有牙。

背景：109 的风险几乎全是「静默」的：
  · 汇率写错一位 ⇒ 白送金条，运行时不报错；
  · 金币上限靠 `add_gold` 的 clampi 兜底 ⇒ 玩家兑回时超出的部分被静默吞掉；
  · 仓库满不校验 ⇒ 金币扣了、金条没给（先扣后判）；
  · 堆叠上限改口径 ⇒ 一格装 100 块，玩家看到数量对不上；
  · 删掉 bound 守卫 ⇒ 100 万一枚的资产能被手滑丢到地上。

所以每条破坏都必须让**对应的那一条**断言变红 —— 「随便红了」不算。
另外每条用例只改**一个** anchor，改前断言锚点唯一命中；每轮先还原全部被改文件。

N-1 汇率 100 万 → 150 万                        → 用例 1「gold_to_ingot 的 fromCount 应为 1000000」
N-2 删掉金币上限前置判断（改回靠 clampi 兜底）   → 用例 5「超出金币上限时必须拒绝」
N-3 去掉仓库容量校验（先扣钱后给货）             → 用例 6「仓库放不下时必须拒绝」
N-4 默认堆叠上限 99 → 100                       → 用例 3「金条堆叠上限应为 99」
N-5 砖→金币 1000 万 → 100 万                    → 用例 4「1 砖应兑 1000 万金币」
N-6 删掉 can_drop_item 的 bound 分支            → 用例 8「拒绝原因应为 bound」
N-7 删除 SampleArt.ICONS 里的两条金条登记       → 用例 9「必须有图标」
N-8 汇率表塞一条非法 pair（to 指向不存在物品）   → 启动校验层必须报出来（只用 --quit 层判）

N-3 的注入形态：`if not Inventory.add(...)` → `if store.size() < 0`。
  这是「永远不拦」而不是「删掉整段」—— 删整段会改变缩进结构，容易连带炸成语法错；
  也不写 `if false:`，`warnings_as_errors` 下不可达代码会变成编译错误（假红）。

跑法：python3 tools/verify_109_negative.py
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXCHANGE = ROOT / "data/exchange.json"
LOGIC = ROOT / "scripts/systems/gold_exchange.gd"
STATE = ROOT / "autoload/game_state.gd"
ITEM_UTIL = ROOT / "scripts/systems/item_util.gd"
ART = ROOT / "scripts/systems/sample_art.gd"
GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")
TEST = "GoldExchangeTest"
RUNNER = ROOT / "tools/run_isolated_tests.py"


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


def rate_150w(text: str) -> str:
    def mutate(data) -> None:
        hits = 0
        for row in data.get("pairs", []):
            if isinstance(row, dict) and row.get("id") == "gold_to_ingot":
                if int(row.get("fromCount", 0)) != 1000000:
                    raise SystemExit("⚠ fromCount 已不是 1000000，负向无效")
                row["fromCount"] = 1500000
                hits += 1
        if hits != 1:
            raise SystemExit(f"⚠ 命中 {hits} 条 gold_to_ingot（应为 1），负向无效")

    return _roundtrip(text, mutate)


def brick_to_million(text: str) -> str:
    def mutate(data) -> None:
        hits = 0
        for row in data.get("pairs", []):
            if isinstance(row, dict) and row.get("id") == "brick_to_gold":
                if int(row.get("toCount", 0)) != 10000000:
                    raise SystemExit("⚠ brick_to_gold.toCount 已不是 10000000，负向无效")
                row["toCount"] = 1000000
                hits += 1
        if hits != 1:
            raise SystemExit(f"⚠ 命中 {hits} 条 brick_to_gold（应为 1），负向无效")

    return _roundtrip(text, mutate)


def bogus_pair(text: str) -> str:
    def mutate(data) -> None:
        pairs = data.get("pairs", [])
        if any(row.get("id") == "bogus_to_nothing" for row in pairs if isinstance(row, dict)):
            raise SystemExit("⚠ 已存在 bogus 用例，负向无效")
        pairs.append({
            "id": "bogus_to_nothing",
            "from": "gold",
            "to": "no_such_item",
            "fromCount": 1,
            "toCount": 1,
        })

    return _roundtrip(text, mutate)


CASES = [
    ("N-1 汇率 100 万 → 150 万（白送金条）",
     "gold_to_ingot 的 fromCount 应为 1000000", EXCHANGE,
     rate_150w, None),
    ("N-2 删掉金币上限前置判断（靠 clampi 兜底）",
     "超出金币上限时必须拒绝", LOGIC,
     lambda t: replace_once(
        t,
        "\t\tif gold_after + to_count > GameState.GOLD_CAP:\n"
        "\t\t\treturn _fail(Localization.tr_key(\"msg.exchange.p005\"))\n",
        ""),
     None),
    ("N-3 去掉仓库容量校验（金币扣了、货没给）",
     "仓库放不下时必须拒绝", LOGIC,
     lambda t: replace_once(
        t,
        "\t\tif not Inventory.add(store, stack_item(to_id, to_count)):",
        "\t\tif store.size() < 0:"),
     None),
    ("N-4 默认堆叠上限 99 → 100（一格装 100）",
     "金条堆叠上限应为 99", ITEM_UTIL,
     lambda t: replace_once(
        t,
        "const DEFAULT_STACK_MAX := 99",
        "const DEFAULT_STACK_MAX := 100"),
     None),
    ("N-5 砖→金币 1000 万 → 100 万（吞掉九成）",
     "1 砖应兑 1000 万金币", EXCHANGE,
     brick_to_million, None),
    ("N-6 删掉 can_drop_item 的 bound 分支（可丢 100 万）",
     "的拒绝原因应为 bound", STATE,
     lambda t: replace_once(
        t,
        "\tif Shop.is_bound(item):\n"
        "\t\treturn {\"ok\": false, \"reason\": \"bound\"}\n",
        ""),
     None),
    ("N-7 删掉 SampleArt.ICONS 的两条金条登记（空白格）",
     "必须有图标", ART,
     lambda t: replace_once(
        t,
        "\t\"gold_ingot\": preload(\"res://assets/sprites/items/gold_ingot.png\"),\n"
        "\t\"gold_brick\": preload(\"res://assets/sprites/items/gold_brick.png\"),\n",
        ""),
     None),
    ("N-8 汇率表塞非法 pair（to 指向不存在物品）",
     "[exchange]", EXCHANGE,
     bogus_pair, "startup"),
]

FILES = [EXCHANGE, LOGIC, STATE, ITEM_UTIL, ART]


# ---- 运行与解析 ----

def _is_valid(out: str) -> bool:
    """🔴 坑 76：Godot 偶发启动失败时输出里既无 PASS 也无 FAIL，
    此时 `failures_of()` 返回空，会被误读成「断言没有牙」。只认结论行。"""
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
    return out


def failures_of(out: str) -> list[str]:
    seen: list[str] = []
    for match in re.finditer(r"\[%s\] ([^\n]+)" % TEST, out):
        label = match.group(1).strip()
        if label and "失败" not in label and label not in seen:
            seen.append(label)
    return seen


def startup_report() -> str:
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
        for label, expect, path, mutate, layer in CASES:
            for target, text in originals.items():          # 先还原**全部**
                target.write_text(text, encoding="utf-8")
            path.write_text(mutate(originals[path]), encoding="utf-8")
            if layer == "startup":
                boot = startup_report()
                hit = expect in boot
                print(f"{label}\n    → 启动校验（--quit 层）："
                      + ("✅ 报出非法兑换对" if hit else "❌ 没报"))
                if not hit:
                    failed += 1
                    print("      输出尾部：" + boot.strip()[-200:].replace("\n", " / "))
                continue
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
