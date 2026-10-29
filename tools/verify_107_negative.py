"""负向验证：确认武士轮转探针（工程 107 §七）的六条判据真的有牙。

背景：107 把武士从「固定点耗蓝 + 无上限 AOE」改成「百分比耗蓝 + 上限 8 只」，
这两件事错起来**全是静默的** —— 技能照放、伤害照出、零报错，只是「打着打着没蓝了」
或者「一片怪越打越爽」。探针本身如果只打印不判定，等于什么都没守。

所以每条破坏都必须让**对应的那一条**判据变红（不是「随便红了就行」——
被连带红也算假绿：那说明判据之间互相污染，真正坏掉的那条没人看着）。

N-1 破甲重击「低频大技能化」（系数 1.7→8、CD 6→10）：同一个技能在相邻窗口里
    落 2 次或 3 次，摆幅从 2% 涨到 11.4% —— 判据 ① 变红。
    （只把系数调大是**测不出来**的：CD 不变时每窗口命中次数恒定，摆幅照样 2%。
      第一次写这条负向时就是这么假绿的，判据 ① 守的是「节奏」不是「数值大小」。）
N-2 武士全部 `manaCostPct` ×3（耗蓝翻三倍）—— 判据 ② 打空时间 + 跨职业比变红。
N-3 `spirit_storm` 耗蓝 4% → 20%（蓝池被霰弹打空）—— 判据 ③ 8 怪蓝量低尾变红。
N-4 `spirit_storm` 系数 1.0 → 2.0（把「缩短 CD 不白送强度」这条忘了）—— 判据 ④ 8 怪倍数变红。
N-5 删掉 `spirit_storm` 的 `maxTargets: 8`（上限没接上）—— 判据 ④ 宽窄比变红。
N-6 `battle_focus` 减伤 0.2 → 0.0（减伤键被摘掉）—— 判据 ⑤ 承伤下降变红。
N-7 武士全部 `manaCostPct` ×0.3（回到「固定点耗」的免费手感）—— 判据 ⑥ 瓶数变红。

🔴 每个用例前还原**所有**被改文件：只还原当次那个的话，上一轮补丁会留在盘上，
   第二次「变红」证明的就不是想验的那一条（工程 89 已踩）。

跑法：python3 tools/verify_107_negative.py
"""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKILLS = ROOT / "data/skills.json"
GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")
SCENE = "res://tools/warrior_rotation_probe.tscn"


# ---- 文本/数据变换 ----

def replace_once(text: str, old: str, new: str) -> str:
    """替换并断言锚点**唯一命中** —— 锚点漂移或撞车都会让负向「什么都没改」然后照常绿。"""
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"⚠ 锚点命中 {count} 次（要求恰好 1 次），负向无效：{old[:60]!r}")
    return text.replace(old, new, 1)


def _roundtrip(text: str, mutate) -> str:
    data = json.loads(text)
    items = data["skills"] if isinstance(data, dict) and "skills" in data else data
    mutate(items)
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def scale_warrior_pct(text: str, factor: float) -> str:
    """把所有**武士**技能的 `manaCostPct` 按倍数缩放（法师不动，否则跨职业比也失去意义）。"""
    def mutate(items) -> None:
        hits = 0
        for skill in items:
            if skill.get("class") == "warrior" and "manaCostPct" in skill:
                skill["manaCostPct"] = round(float(skill["manaCostPct"]) * factor, 6)
                hits += 1
        if hits < 5:
            raise SystemExit(f"⚠ 只缩放 {hits} 条武士耗蓝（应为 5 条），负向无效")
    return _roundtrip(text, mutate)


def drop_key(text: str, skill_id: str, key: str) -> str:
    def mutate(items) -> None:
        for skill in items:
            if skill.get("id") == skill_id:
                if key not in skill:
                    raise SystemExit(f"⚠ {skill_id} 没有 {key} 字段，负向无效")
                del skill[key]
                return
        raise SystemExit(f"⚠ 找不到技能 {skill_id}")
    return _roundtrip(text, mutate)


def bump_spirit_storm_coef(text: str) -> str:
    """只改灵刃风暴的系数：它的下一行是 `"hits": 3`，用它当唯一上下文。"""
    return replace_once(
        text,
        '"coefficient": 1.0,\n    "hits": 3,',
        '"coefficient": 2.0,\n    "hits": 3,',
    )


CASES = [
    ("N-1 破甲重击改成低频大技能（系数 1.7→8、CD 6→10）", "①",
     lambda t: replace_once(replace_once(t, '"coefficient": 1.7,', '"coefficient": 8.0,'),
                            '"cooldown": 6.0,', '"cooldown": 10.0,')),
    ("N-2 武士耗蓝 ×3（耗蓝翻三倍）", "②",
     lambda t: scale_warrior_pct(t, 3.0)),
    ("N-3 灵刃风暴耗蓝 4% → 20%", "③",
     lambda t: replace_once(t, '"manaCostPct": 0.04,', '"manaCostPct": 0.2,')),
    ("N-4 灵刃风暴系数 1.0 → 2.0（CD 短了却把强度加倍还回去）", "④",
     bump_spirit_storm_coef),
    ("N-5 删掉灵刃风暴的 maxTargets（上限没接上）", "④",
     lambda t: drop_key(t, "spirit_storm", "maxTargets")),
    ("N-6 战意觉醒减伤 0.2 → 0.0（减伤键被摘掉）", "⑤",
     lambda t: replace_once(t, '"effects": { "damageReducePct": 0.2, "attackSpeedPct": 0.15 },',
                            '"effects": { "damageReducePct": 0.0, "attackSpeedPct": 0.15 },')),
    ("N-7 武士耗蓝 ×0.3（回到固定点耗的免费手感）", "⑥",
     lambda t: scale_warrior_pct(t, 0.3)),
]


# ---- 运行与解析 ----

def run_probe() -> tuple[int, str]:
    proc = subprocess.run([str(GODOT), "--headless", "--path", str(ROOT), SCENE],
                          cwd=ROOT, capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


def failures_of(out: str) -> list[str]:
    """探针结尾的失败清单每行形如 `  - ④ 8 怪 DPS 倍数 ...`。"""
    result = []
    for line in out.splitlines():
        stripped = line.strip()
        if stripped.startswith("- ") and re.match(r"^- [①②③④⑤⑥]", stripped):
            result.append(stripped[2:])
    return result


def main() -> int:
    original = SKILLS.read_text(encoding="utf-8")

    # 前置：不改任何东西时必须六条全绿，否则后面的「变红」不说明任何问题。
    code, out = run_probe()
    if code != 0:
        print("⚠ 基线不是绿的，先修基线再验负向：")
        for item in failures_of(out):
            print("    " + item)
        return 1
    print("前置：未改动时六条判据全绿 ✅")

    failed = 0
    try:
        for label, tag, mutate in CASES:
            SKILLS.write_text(original, encoding="utf-8")     # 先还原全部
            SKILLS.write_text(mutate(original), encoding="utf-8")
            code, out = run_probe()
            hits = failures_of(out)
            teeth = [h for h in hits if h.startswith(tag)]
            print(f"{label}\n    → 判据 {tag}：{'✅ 变红' if teeth else '❌ 仍绿（断言无效）'}")
            if teeth:
                print("      " + teeth[0][:160])
            else:
                failed += 1
                others = [h[:90] for h in hits if not h.startswith(tag)]
                print("      其余红项：" + ("无" if not others else " / ".join(others)))
                if not hits:
                    print("      原始输出尾部：" + " | ".join(
                        [ln.strip() for ln in out.splitlines() if ln.strip()][-5:])[:300])
    finally:
        SKILLS.write_text(original, encoding="utf-8")

    code, out = run_probe()
    tail_ok = code == 0
    print("还原后复跑：" + ("六条全绿 ✅" if tail_ok else "⚠ 仍红 → " + " / ".join(failures_of(out))[:300]))
    print("负向全部有牙 ✅" if failed == 0 and tail_ok else "存在假绿 ⚠")
    return 1 if failed or not tail_ok else 0


if __name__ == "__main__":
    raise SystemExit(main())
