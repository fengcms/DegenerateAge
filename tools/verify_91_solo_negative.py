"""负向验证：确认工程 91「孤王绝域」的四条断言真的有牙。

N-1 去掉 `Loot` 里的 `+ levelOffset`（只加 0）—— 同形 bug：「比玩家高 10 级」整条链路失效，
    但装备照掉、游戏照跑、报告零错误。期望用例 7「最低装备等级应为 101」变红。
N-2 `levelOffset` 改成 20 —— 同形 bug：偏移接上了但值配错（等于「高 20 级」）。
    **只断「≥101」的测试抓不到它**，所以用例 7 必须双向断上界 110。
N-3 装备件数只放大 5 倍 —— 同形 bug：「十倍掉落」变成五倍，玩家只会觉得「好像没那么多」。
    期望用例 6（逐组比值 10）变红。
N-4 重生 1800 → 600 秒 —— 同形 bug：半小时一只变 10 分钟一只，图从「仪式」变成「刷图」。
    期望用例 3「重生应为 1800 秒」变红。

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
        ("N-3 装备件数只放大 5 倍", DROPS, None, None),
        ("N-4 重生 1800 → 600 秒", MAP, '"respawnTime": 1800', '"respawnTime": 600'),
    ]
    # N-3 要改三处件数，用结构化改法（文本替换会误伤别的 10/20）。
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
            if label.startswith("N-3"):
                tables = json.loads(sources[DROPS])
                for table in tables:
                    if table.get("id") != "DT_C7_Solo_Boss":
                        continue
                    for entry in table.get("entries", []):
                        if entry.get("kind") == "equip":
                            lo, hi = entry["countRange"]
                            entry["countRange"] = [max(1, int(lo) // 2), max(1, int(hi) // 2)]
                path.write_text(json.dumps(tables, ensure_ascii=False, indent=2), encoding="utf-8")
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


if __name__ == "__main__":
    raise SystemExit(main())
