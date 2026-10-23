"""负向验证：确认「挂机自动维护」的 11 个用例真的有牙（工程 95）。

背景：这两条流程错起来是**静默**的 —— 倍率配错、阈值判反、漏金币校验、误吃 12 星金装，
游戏都照常跑、照常挂机、零报错，玩家只会在某天发现「金币少了」或「12 星金装没了」。
所以每条破坏都必须让对应断言变红。

N-1 `autoRepair.feeRate` 1.5 → 1.0（自动修复变平价）—— 用例 3「应为铁匠 ×1.50」变红。
N-2 阈值判断 `<` → `<=`（20% 整也触发）—— 用例 2 的边界断言变红。
N-3 删掉 `auto_forge_gold` 的金币校验 —— 用例 11（钱不够还照合）变红。
N-4 删掉 `random_materials` 的 `star != 0` 守卫 —— 用例 8（12 星金装被吃）变红。
N-5 挑料函数改成也扫穿戴件 —— 用例 7（穿戴件被当肥料吃掉）变红。

🔴 每个用例前还原**所有**被改文件：只还原当次那个的话，上一轮补丁会留在盘上，
   第二次「变红」证明的就不是想验的那一条（工程 89 已踩）。

跑法：python3 tools/verify_95_auto_maintenance_negative.py
"""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DURABILITY = ROOT / "data/durability.json"
GAME_STATE = ROOT / "autoload/game_state.gd"
FUSION = ROOT / "scripts/systems/equipment_fusion.gd"
TEST = "AutoMaintenanceTest"

# ---- 锚点（原文必须逐字命中，命中失败要报出来，不能静默跳过）----
FEE_RATE = '    "feeRate": 1.5,'
THRESHOLD_LT = "\t\tif it is Dictionary and float(Durability.current(it)) < limit:"
THRESHOLD_LE = "\t\tif it is Dictionary and float(Durability.current(it)) <= limit:"
GOLD_CHECK = (
    '\tif gold < fee:\n'
    '\t\t_auto_warn(false, fee)\n'
    '\t\treturn {"ok": false, "cost": fee, "reason": "金币不足"}\n'
)
STAR_GUARD = "\t\t\t\tor bool(entry.get(\"favorite\", false)) or int(entry.get(\"star\", -1)) != 0 \\\n"
STAR_GUARD_OFF = "\t\t\t\tor bool(entry.get(\"favorite\", false)) \\\n"
PICK_BAG = "\tvar mats := EquipmentFusion.random_materials(inventory, EquipmentFusion.GOLD_TO_PURPLE)"
PICK_ALL = "\tvar mats := EquipmentFusion.random_materials(inventory + equipment.values(), EquipmentFusion.GOLD_TO_PURPLE)"


def run_test() -> tuple[bool, str]:
    proc = subprocess.run(["python3", "tools/run_isolated_tests.py", TEST],
                          cwd=ROOT, capture_output=True, text=True)
    return proc.returncode == 0, proc.stdout + proc.stderr


def first_failure(out: str) -> str:
    lines = [line.strip() for line in out.splitlines()]
    errors = [line for line in lines
              if line.startswith("ERROR:") and "未输出成功完成标记" not in line
              and "caller thread" not in line]
    if errors:
        return " / ".join(list(dict.fromkeys(errors))[:2])[:400]
    for line in lines:
        if "FAIL" in line:
            return line[:200]
    return "(未捕获到失败行)"


def patch(path: Path, source: str, old: str, new: str) -> None:
    """替换并断言锚点确实命中 —— 锚点漂移会让负向「什么都不改」然后照常绿。"""
    if old not in source:
        raise SystemExit(f"⚠ 锚点未命中，负向无效：{path.name} ← {old[:60]!r}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def main() -> int:
    sources = {path: path.read_text(encoding="utf-8") for path in (DURABILITY, GAME_STATE, FUSION)}

    # 前置：不改任何东西时必须全绿，否则后面的「变红」不说明任何问题。
    ok, out = run_test()
    if not ok:
        print("⚠ 基线不是绿的，先修基线再验负向：")
        print("    " + first_failure(out))
        return 1
    print("前置：未改动时 AutoMaintenanceTest 全绿 ✅")

    cases = [
        ("N-1 feeRate 1.5 → 1.0（自动修复变平价）", "FEE_10"),
        ("N-2 阈值 < 改成 <=（20% 整也触发）", "THRESHOLD"),
        ("N-3 删掉自动合成的金币校验", "NO_GOLD_CHECK"),
        ("N-4 删掉 star != 0 守卫（12 星金装被吃）", "NO_STAR_GUARD"),
        ("N-5 挑料也扫穿戴件（穿在身上的被吃掉）", "PICK_WORN"),
    ]

    failures = 0
    try:
        for label, mode in cases:
            # 🔴 每个用例前还原所有被改文件（不只是当次要改的那个）。
            for path, text in sources.items():
                path.write_text(text, encoding="utf-8")

            if mode == "FEE_10":
                patch(DURABILITY, sources[DURABILITY], FEE_RATE, '    "feeRate": 1.0,')
            elif mode == "THRESHOLD":
                patch(GAME_STATE, sources[GAME_STATE], THRESHOLD_LT, THRESHOLD_LE)
            elif mode == "NO_GOLD_CHECK":
                patch(GAME_STATE, sources[GAME_STATE], GOLD_CHECK, "")
            elif mode == "NO_STAR_GUARD":
                patch(FUSION, sources[FUSION], STAR_GUARD, STAR_GUARD_OFF)
            elif mode == "PICK_WORN":
                patch(GAME_STATE, sources[GAME_STATE], PICK_BAG, PICK_ALL)

            ok, out = run_test()
            print(f"{label}：{'❌ 仍绿（断言无效）' if ok else '✅ 变红'}")
            if ok:
                failures += 1
            else:
                print("    " + first_failure(out))
    finally:
        for path, text in sources.items():
            path.write_text(text, encoding="utf-8")

    ok, out = run_test()
    print("还原后复跑：" + ("全绿 ✅" if ok else "⚠ 仍红 —— " + first_failure(out)))
    print("负向全部有牙 ✅" if failures == 0 and ok else "存在假绿 ⚠")
    return 1 if failures or not ok else 0


if __name__ == "__main__":
    raise SystemExit(main())
