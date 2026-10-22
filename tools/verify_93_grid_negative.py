"""负向验证：确认「一格一件铺格」（工程 93）的判据真的有牙。

N-1 所有件都记同一个格（只写 cells 忘了逐件写）—— 同形 bug：算法算对了但没落到 row 上，
    实机表现是「全部掉在尸体脚下」，而时序 / 认领 / 拾取全都正常、游戏零报错。
    期望用例 1「两件掉落落在同一格」变红。
N-2 忽略 `walkable` 回调（不跳过不可走格）—— 同形 bug：掉落铺进墙里 / 地图外，
    再被 `clamp_to_map` 全部挤回边界同一堆。**只有靠边时才看得出来**，最容易漏测。
    期望用例 4「落进了不可走区」变红。
N-3 内侧优先反向（好装备反而铺最外圈）—— 同形 bug：一件不丢、一格不错，只是传说掉在最远处，
    玩家得走一圈才能看见。纯体验退化，任何功能测试都抓不到。期望用例 3 变红。
N-4 名字降噪阈值抬到 100000（等于取消）—— 同形 bug：图标铺好了，但 100 个宽 240px 的名字
    重新糊成一片，等于白改。期望用例 7 变红。
N-5 `rings_for` 的容量公式从 `1+4r(r+1)` 改成 `1+2r(r+1)`（算少了）—— 同形 bug：
    圈数不够就触发兜底复用，件数一多立刻重叠。期望用例 2 的**硬编码表**变红
    （第二组断言复用本函数算期望，只靠它必假绿 —— 这正是工程 08 §7 第 37 条）。
N-6 `MAX_RING` 12 → 2（为了「性能」调小）—— 容量从 625 格塌到 25 格，
    102 件必然走循环复用。期望用例 1「同一格」变红。

跑法：python3 tools/verify_93_grid_negative.py
"""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BURST = ROOT / "scripts/systems/loot_burst.gd"
ITEM = ROOT / "scripts/entities/ground_item.gd"
TEST = "LootGridTest"


def run() -> tuple[bool, str]:
    proc = subprocess.run(["python3", "tools/run_isolated_tests.py", TEST],
                          cwd=ROOT, capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    return proc.returncode == 0, out


def first_failure(out: str) -> str:
    """取测试自己 `push_error` 的断言正文（runner 的「未输出标记」是通用外壳）。"""
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


def main() -> int:
    sources = {path: path.read_text(encoding="utf-8") for path in (BURST, ITEM)}
    cases = [
        ("N-1 每件都记成击杀格（格位没落到 row 上）", BURST,
         '\t\trow["cell"] = cell\n', '\t\trow["cell"] = origin\n'),
        ("N-2 忽略可走性回调（掉落铺进墙里）", BURST,
         "\t\t\tif walk.is_valid() and not bool(walk.call(cell)):\n\t\t\t\tcontinue\n", ""),
        ("N-3 内侧优先反向（传说铺最外圈）", BURST,
         "return ra < rb)", "return ra > rb)"),
        ("N-4 名字降噪阈值取消（100 个名字糊成一团）", ITEM,
         "const LABEL_CROWD_LIMIT := 20", "const LABEL_CROWD_LIMIT := 100000"),
        ("N-5 容量公式算少（1+2r(r+1)）", BURST,
         "while 1 + 4 * r * (r + 1) < count:", "while 1 + 2 * r * (r + 1) < count:"),
        ("N-6 圈数上限 12 → 2（容量塌到 25 格）", BURST,
         "const MAX_RING := 12", "const MAX_RING := 2"),
    ]
    failures = 0
    try:
        for path, text in sources.items():
            path.write_text(text, encoding="utf-8")

        for label, path, old, new in cases:
            # 🔴 每个用例前**还原所有被改文件**：否则上一轮补丁留在盘上，
            # 第二次「变红」证明的不是想验的那条（工程 89 已踩过一次，两条证据一模一样）。
            for p, text in sources.items():
                p.write_text(text, encoding="utf-8")
            patched = sources[path].replace(old, new, 1)
            if patched == sources[path]:
                print(f"{label}：⚠ 替换未命中（脚本已失效，需同步源码）")
                failures += 1
                continue
            path.write_text(patched, encoding="utf-8")
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
