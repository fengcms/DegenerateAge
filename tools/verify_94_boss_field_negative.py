"""负向验证：确认「百首禁域攻击倍率 3.0」的断言真的有牙（工程 94 / D-32）。

背景：原地 1.5 倍在 140 级满紫 12 星（防御 41,857）下仍在破防线（20,928）之下，
`Combat.resolve` 判 `攻击 − 防御×0.5 ≤ 0` ⇒ 每击恒走保底 60（血量的 0.07%），
Boss 打人 14.7 秒只掉 270 血。这类 bug **零报错、零崩溃、照常掉落**，只能靠断言拦。

N-1 全场退回 1.5（退回血包）—— 同形 bug：就是修复前的状态。期望「应为 3.0」变红。
N-2 改成 2.40（**恰配破防阈值**）—— 最阴的一条：2.40 刚好卡在 `攻击 == 防御×0.5` 上，
    此时 `raw ≤ 0` 仍成立但差值极小，每击只剩 **12 点**，比保底 60 还轻。
    ⇒ 若断言被放宽成「≥ 破防线」就会假绿，所以必须断**精确值**。
N-3 生成器常量退回 1.5 并重跑生成器 —— R6 同形 bug：只改 `map.json` 不改生成器，
    下一次有人跑 `build_c7_cycle_maps.py` 就静默冲掉。反过来验证「生成器常量才是真相源」。
N-4 只把第 1 席改回 1.5（漏改一条）—— 「只看集合大小 100 条」会被漏写绕过，
    逐席断言必须红。

跑法：python3 tools/verify_94_boss_field_negative.py
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAP = ROOT / "data/maps/ch07/c7_boss_field/map.json"
BUILD = ROOT / "tools/build_c7_cycle_maps.py"
## 两个测试都要红：
##   `EndgameCycleMapTest`  守**配置**（100 席都是 3.0）；
##   `BossFieldDamageTest`  守**结果**（每击 / 破防余量 / 60 秒掉血）。
## 只跑其中一个会让另一个变成「永远绿」的摆设。
TESTS = ["EndgameCycleMapTest", "BossFieldDamageTest"]
SEAT_KEY = '"atkMultiplier": 3.0'
BUILD_KEY = "BOSS_FIELD_ATK = 3.0"


def run_test(name: str) -> tuple[bool, str]:
    proc = subprocess.run(["python3", "tools/run_isolated_tests.py", name],
                          cwd=ROOT, capture_output=True, text=True)
    return proc.returncode == 0, proc.stdout + proc.stderr


def run_build() -> None:
    subprocess.run(["python3", "tools/build_c7_cycle_maps.py"],
                   cwd=ROOT, capture_output=True, text=True)


def first_failure(out: str) -> str:
    """取测试自己 push_error 的断言正文（runner 的「未输出标记」是通用外壳）。"""
    lines = [line.strip() for line in out.splitlines()]
    errors = [line for line in lines
              if line.startswith("ERROR:") and "未输出成功完成标记" not in line
              and "caller thread" not in line]
    if errors:
        return " / ".join(list(dict.fromkeys(errors))[:3])[:400]
    for line in lines:
        if "FAIL" in line:
            return line[:160]
    return "(未捕获到失败行)"


def digest(path: Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()


def main() -> int:
    sources = {path: path.read_text(encoding="utf-8") for path in (MAP, BUILD)}

    # 前置：生成器重跑后产物必须**逐字节不变**（R6 闭合）。不一致说明有人手改了 map.json。
    before = digest(MAP)
    run_build()
    if digest(MAP) != before:
        print("⚠ 生成器重跑后 map.json 变了：产物与生成器不同步，先修这个再验负向")
        return 1
    print(f"前置 R6：生成器重跑后 map.json 不变（md5 {before[:8]}…）✅")

    cases = [
        ("N-1 全场退回 1.5 倍（退回血包）", "MAP_ALL_15"),
        ("N-2 改成 2.40（恰配破防阈值，每击只剩 12 点）", "MAP_ALL_240"),
        ("N-3 生成器常量退回 1.5 并重跑（R6 冲掉）", "BUILD_15"),
        ("N-4 只漏改第 1 席（100 条里错 1 条）", "MAP_ONE"),
    ]

    failures = 0
    try:
        for label, mode in cases:
            # 🔴 每个用例前还原所有被改文件：否则上一轮补丁留在盘上，
            # 第二次变红证明的不是想验的那条（工程 89 已踩）。
            for path, text in sources.items():
                path.write_text(text, encoding="utf-8")

            if mode == "MAP_ALL_15":
                MAP.write_text(sources[MAP].replace(SEAT_KEY, '"atkMultiplier": 1.5'),
                               encoding="utf-8")
            elif mode == "MAP_ALL_240":
                MAP.write_text(sources[MAP].replace(SEAT_KEY, '"atkMultiplier": 2.4'),
                               encoding="utf-8")
            elif mode == "BUILD_15":
                BUILD.write_text(sources[BUILD].replace(BUILD_KEY, "BOSS_FIELD_ATK = 1.5"),
                                 encoding="utf-8")
                run_build()
            elif mode == "MAP_ONE":
                _mutate_one_seat()

            for test_name in TESTS:
                ok, out = run_test(test_name)
                print(f"{label} · {test_name}：{'❌ 仍绿（断言无效）' if ok else '✅ 变红'}")
                if ok:
                    failures += 1
                else:
                    print("    " + first_failure(out))
    finally:
        for path, text in sources.items():
            path.write_text(text, encoding="utf-8")
        # 生成器用例可能已改写产物，还原后必须再重跑一次才能回到干净状态。
        run_build()

    restored = digest(MAP)
    print(f"还原完成（md5 {restored[:8]}…）；"
          + ("负向全部有牙 ✅" if failures == 0 else "存在假绿 ⚠"))
    return 1 if failures else 0


def _mutate_one_seat() -> None:
    """结构化改法：只动第一条席位。文本 replace(count=1) 也行，但这里要保证落到席位而非 desc。"""
    data = json.loads(MAP.read_text(encoding="utf-8"))
    seats = data["bossSpawns"]
    assert len(seats) == 100, f"席位应为 100，实际 {len(seats)}"
    seats[0]["atkMultiplier"] = 1.5
    MAP.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
