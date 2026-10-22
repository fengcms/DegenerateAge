"""负向验证：确认「孤王绝域」的七条断言真的有牙。

N-1 去掉 `Loot` 里的 `+ levelOffset`（只加 0）—— 同形 bug：「比玩家高 10 级」整条链路失效，
    但装备照掉、游戏照跑、报告零错误。期望用例 7「最低装备等级应为 101」变红。
N-2 `levelOffset` 改成 20 —— 同形 bug：偏移接上了但值配错（等于「高 20 级」）。
    **只断「≥101」的测试抓不到它**，所以用例 7 必须双向断上界 110。
N-3 前两组件数只放大 5 倍 —— 同形 bug：「十倍掉落」变成五倍，玩家只会觉得「好像没那么多」。
    期望用例 6（逐组比值 10）变红。
N-4 重生 1800 → 600 秒 —— 同形 bug：半小时一只变 10 分钟一只，图从「仪式」变成「刷图」。
    期望用例 3「重生应为 1800 秒」变红。
N-5 攻击倍率 3.3 → 1.0 —— **最隐蔽的一条**（工程 92）：配置写错了，但游戏照常进、照常掉、
    照常报 PASS，只是每击恒走保底 60，玩家站桩 148 秒只掉 1.9% 血。工程 91 就是这么发布的。
    期望用例 3「atkMultiplier 应为 3.3」变红。
N-6 传说组 chance 1.0 → 0.05 —— 同形 bug：「必出紫」退回概率掉落（每只掉不进紫，玩家只当运气差）。
    期望用例 6「传说组必须 chance 1.0」变红。
N-7 传说组件数 1 → 10 —— 「必出」还在，但一次爆 10 件紫，与用户「只出一件」的拍板相反。
    期望用例 6「传说组必须只出 1 件」变红。

跑法：python3 tools/verify_91_solo_negative.py
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOOT = ROOT / "scripts/systems/loot.gd"
DROPS = ROOT / "data/dropTables.json"
MAP = ROOT / "data/maps/ch07/c7_solo_boss/map.json"
TEST = "SoloBossFieldTest"

# 偏移在 loot.gd 里的唯一落点（连注释一起删会更好读，但删注释不算注入，必须删代码行）。
OFFSET_LINE = '\t\tboss_level += int(e.get("levelOffset", 0))\n'
OFFSET_DOC = """\t\t# 工程 91：`levelOffset` 让「掉落比击杀目标高 N 级」（孤王绝域 = +10）。
\t\t# 🔴 只能加在**动态条**上：静态条的穿戴等级由 `tierStart` 决定，加偏移会让实例
\t\t# `level` 与 `requiredLevel` 脱钩，直接违反存档硬约束（读档必被 `_valid_item` 剔除）。
\t\t# 位置在品质抽取之后、等级使用之前 ⇒ 随机调用序列一步未变（同 M10-2 的分岔原则）。
"""


def run() -> tuple[bool, str]:
    proc = subprocess.run(["python3", "tools/run_isolated_tests.py", TEST],
                          cwd=ROOT, capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    return proc.returncode == 0, out


def first_failure(out: str) -> str:
    """取测试自己 `push_error` 的断言正文（runner 的 `FAIL: 未输出标记` 是通用外壳）。"""
    lines = [line.strip() for line in out.splitlines()]
    errors = [line for line in lines
              if line.startswith("ERROR:") and "未输出成功完成标记" not in line
              and "caller thread" not in line]
    if errors:
        return " / ".join(list(dict.fromkeys(errors))[:4])[:400]
    for line in lines:
        if "FAIL" in line:
            return line[:160]
    return "(未捕获到失败行)"


def main() -> int:
    sources = {path: path.read_text(encoding="utf-8") for path in (LOOT, DROPS, MAP)}
    cases = [
        ("N-1 去掉 levelOffset（掉落还是玩家等级）", LOOT,
         OFFSET_DOC + OFFSET_LINE, OFFSET_DOC),
        ("N-2 levelOffset 改成 20（高 20 级）", DROPS,
         '"levelOffset": 10', '"levelOffset": 20'),
        ("N-3 前两组件数只放大 5 倍", "DROPS_HALVE", None, None),
        ("N-4 重生 1800 → 600 秒", MAP, '"respawnTime": 1800', '"respawnTime": 600'),
        ("N-5 攻击倍率 3.3 → 1.0（退回血包）", MAP,
         '"atkMultiplier": 3.3', '"atkMultiplier": 1.0'),
        ("N-6 传说组退回 5% 概率（不再必出）", "DROPS_LEGEND_CHANCE", None, None),
        ("N-7 传说组放回 10 件（爆量换爽感）", "DROPS_LEGEND_COUNT", None, None),
    ]
    # N-3/N-6/N-7 要精确落到某一条 entry 上，用结构化改法（文本替换会误伤别的 10/20/0.05）。
    failures = 0
    try:
        # 先把全部源文件还原一遍，保证起点干净。
        for path, text in sources.items():
            path.write_text(text, encoding="utf-8")

        for label, path, old, new in cases:
            # 🔴 每个用例前**还原所有被改文件**：否则上一个补丁留在盘上，第二次变红
            # 证明的不是想验的那条（工程 89 已踩过一次，现象是两条证据一模一样）。
            for p, text in sources.items():
                p.write_text(text, encoding="utf-8")
            if isinstance(path, str):  # 结构化改法
                _mutate_solo_equips(path)
            else:
                path.write_text(sources[path].replace(old, new, 1), encoding="utf-8")
            ok, out = run()
            print(f"{label}：{'❌ 仍绿（断言无效）' if ok else '✅ 变红'}")
            if ok:
                failures += 1
                continue
            print("    " + first_failure(out))
    finally:
        for path, text in sources.items():
            path.write_text(text, encoding="utf-8")
    print("还原完成；负向全部有牙 ✅" if failures == 0 else "存在假绿 ⚠")
    return 1 if failures else 0


def _mutate_solo_equips(mode: str) -> None:
    """只改 `DT_C7_Solo_Boss` 的装备组，并按 mode 做对应破坏。"""
    tables = json.loads(DROPS.read_text(encoding="utf-8"))
    for table in tables:
        if table.get("id") != "DT_C7_Solo_Boss":
            continue
        for entry in table.get("entries", []):
            if entry.get("kind") != "equip":
                continue
            is_legend = "legendary" in entry.get("qualityWeight", {})
            if mode == "DROPS_HALVE":
                lo, hi = entry["countRange"]
                entry["countRange"] = [max(1, int(lo) // 2), max(1, int(hi) // 2)]
            elif mode == "DROPS_LEGEND_CHANCE" and is_legend:
                entry["chance"] = 0.05
            elif mode == "DROPS_LEGEND_COUNT" and is_legend:
                entry["countRange"] = [10, 10]
    DROPS.write_text(json.dumps(tables, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
