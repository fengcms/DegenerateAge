#!/usr/bin/env python3
"""工程 83 负向验证：把两只近战怪换回远程 / 只改一半数据，确认断言变红后自动还原。

用法：python3 tools/verify_83_negative.py [案例名]
⚠ 本脚本会临时改写数据与生成器源码，必须与全量隔离集**串行**执行（工程 77 并发事故教训）。

工程 83 的两层靶子缺一层就有空洞：
- **产物层**（N-1 换回远程 / N-2 norm 表留孤儿 id）→ `EndgameCycleMapTest` 变红
- **生成器层**（N-3 换出远程时生成器自己 assert）→ `build_c7_cycle_maps.py` 非零退出

注入原则（工程 08 §11.3）：注入形态必须与**真实 bug 同形**。「换怪时手滑选回远程」
就是只改 `map.json` 那一行 monsterId，不是删断言、不是写死常量。
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GOLD_MAP = ROOT / "data/maps/ch07/c7_gold_field/map.json"
ENDGAME = ROOT / "data/endgame.json"
BUILDER = ROOT / "tools/build_c7_cycle_maps.py"
MAP_TEST = "EndgameCycleMapTest"

# 被换掉的两只远程怪，注入时按真实形态换回去。
REMOTE = {"c5_normal05": "c6_normal03", "c5_normal08": "c6_normal06"}


def swap_one_back_to_ranged(data: dict) -> None:
    """只改一行 monsterId：把席位换回射程 6 格的远程怪（其余 7 组不动）。"""
    for group in data["spawnPoints"]:
        if group.get("monsterId") == "c5_normal05":
            group["monsterId"] = REMOTE["c5_normal05"]
            return
    raise AssertionError("map.json 里没有 c5_normal05，用例需随数据更新")


def orphan_norm_id(data: dict) -> None:
    """只改了地图、忘了改 endgame：norm 表留着被换掉的两个 id（8 条仍成立，但对不上怪种）。"""
    for row in data["goldFieldNormals"]:
        if row.get("monsterId") == "c5_normal05":
            row["monsterId"] = REMOTE["c5_normal05"]
            return
    raise AssertionError("endgame.json 里没有 c5_normal05，用例需随数据更新")


def builder_puts_back_ranged() -> bool:
    """生成器侧：把 GOLD_NORMALS 里一只换回远程，`assert_gold_normals_melee()` 必须拦下。

    直接跑生成器（不是跑测试场景）：这是「生成器守卫」唯一能被证明的地方 ——
    只看产物断言，无法排除「生成时就不该产出这张图」。
    """
    original = BUILDER.read_text(encoding="utf-8")
    marker = '"c6_normal01", "c6_normal02", "c5_normal05", "c6_normal04",'
    if marker not in original:
        print("注入点未找到（生成器已变更，需更新脚本）：GOLD_NORMALS 首行")
        return False
    try:
        BUILDER.write_text(original.replace(marker, marker.replace("c5_normal05", "c6_normal03"), 1),
                           encoding="utf-8")
        result = subprocess.run([sys.executable, "tools/build_c7_cycle_maps.py"],
                                capture_output=True, text=True, timeout=120, cwd=ROOT)
        output = result.stdout + result.stderr
        blocked = result.returncode != 0 and "远程怪" in output
        summary = next((ln.strip() for ln in output.splitlines() if "远程怪" in ln), "")
        print(f"[{'RED ' if blocked else 'GREEN!'}] N-3 生成器放过远程怪  ->  {summary or '生成器未拦截'}")
        return blocked
    finally:
        BUILDER.write_text(original, encoding="utf-8")


CASES = [
    {"name": "N-1 席位换回远程怪（战士又得逐个追）", "json": GOLD_MAP, "mutate": swap_one_back_to_ranged},
    {"name": "N-2 只改地图不改 norm 表（8 条仍在但对不上怪种）", "json": ENDGAME, "mutate": orphan_norm_id},
]


def run_case(case: dict) -> tuple[bool, str]:
    path: Path = case["json"]
    original = path.read_text(encoding="utf-8")
    payload = json.loads(original)
    case["mutate"](payload)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    try:
        result = subprocess.run(
            ["python3", "tools/run_isolated_tests.py", MAP_TEST],
            capture_output=True, text=True, timeout=300, cwd=ROOT,
        )
        output = result.stdout + result.stderr
        if "Compile Error" in output or "Parse Error" in output:
            return False, "编译失败（无效红，掩盖真实 bug 形态）"
        is_red = "FAIL" in output or "失败" in output
        # 逐条列出**所有**失败断言：只看第一条会误判「红的不是我想要的那条」
        # （N-1 会同时踩「远程怪」与「norm 覆盖」两条，只报第一条就看不出近战判据有没有牙）。
        details = list(dict.fromkeys(ln.strip().replace("ERROR: ", "")
                                     for ln in output.splitlines() if "ERROR:" in ln))[:4]
        return is_red, " / ".join(details)
    finally:
        path.write_text(original, encoding="utf-8")


def main() -> int:
    filter_name = sys.argv[1] if len(sys.argv) > 1 else None
    bad: list[str] = []
    total = 0
    for case in CASES:
        if filter_name and filter_name not in case["name"]:
            continue
        total += 1
        red, summary = run_case(case)
        print(f"[{'RED ' if red else 'GREEN!'}] {case['name']}  ->  {summary}", flush=True)
        if not red:
            bad.append(case["name"])
    if not filter_name or "N-3" in filter_name:
        total += 1
        if not builder_puts_back_ranged():
            bad.append("N-3 生成器放过远程怪")
    print()
    if bad:
        print(f"❌ 有 {len(bad)} 条负向没能变红：{bad}")
        return 1
    print(f"✅ 全部 {total} 条负向都变红（已还原数据与生成器源码）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
