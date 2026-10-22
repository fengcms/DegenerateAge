"""临时负向验证：确认工程 89「拖拽丢弃」的四条断言真的有牙。

N-1 去掉 token 校验（`Warehouse.token_matches`）—— 同形 bug：拖拽那 3 秒里背包被整理过
    ⇒ 按旧下标移除错的那件。期望用例「token 失效」变红。
N-2 让 `manual_only` 失效（撤掉 `GroundItem._physics_process` 的早退）—— 同形 bug：丢弃物
    落在脚边 96px 内、保护期只有 0.2s ⇒ 松手即被自动捡回，功能等于没做。期望用例
    「manual_only 不被拾回」变红。**只撤 `AutoBattle._can_pick` 那一层不算**（那是顺路拾取，
    与本用例驱动的靠近拾取不是同一条路径 —— 双保险只删一层＝假绿）。
N-3 允许丢弃任务物品（删掉 `Shop.is_quest_item` 判定）—— 同形 bug：任务链断。期望用例
    「三类不可丢弃」变红。

跑法：python3 tools/verify_89_drop_negative.py
"""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT / "autoload/game_state.gd"
ITEM = ROOT / "scripts/entities/ground_item.gd"
TEST = "DropToGroundTest"

TOKEN_GUARD = """\tif not Warehouse.token_matches(item, token):
\t\treturn {"ok": false, "reason": "stale"}
"""
MANUAL_GUARD = """\t# 工程 89：玩家丢弃物只认点击 —— 否则丢在脚边会被立刻捡回去。
\tif manual_only:
\t\treturn
"""
QUEST_GUARD = """\tif Shop.is_quest_item(item):
\t\treturn {"ok": false, "reason": "quest_item"}
"""


def run() -> tuple[bool, str]:
    proc = subprocess.run(["python3", "tools/run_isolated_tests.py", TEST],
                          cwd=ROOT, capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    return proc.returncode == 0, out


def first_failure(out: str) -> str:
    """取测试自己 `push_error` 的断言正文（runner 的 `FAIL: 未输出标记` 是同一条根因的
    通用外壳，拿它当证据等于没验证「红的是哪条断言」）。同一轮可能红多条，全部列出。"""
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
    state_src = STATE.read_text(encoding="utf-8")
    item_src = ITEM.read_text(encoding="utf-8")
    cases = [
        ("N-1 去掉 token 校验", STATE, state_src, TOKEN_GUARD),
        ("N-2 manual_only 失效（丢弃物被自动捡回）", ITEM, item_src, MANUAL_GUARD),
        ("N-3 允许丢弃任务物品", STATE, state_src, QUEST_GUARD),
    ]
    for label, _path, source, guard in cases:
        assert guard in source, f"注入点缺失：{label}"
    failures = 0
    try:
        for label, path, source, guard in cases:
            # 🔴 每个用例前**先把两个文件都还原**：否则上一个用例的补丁会留在盘上，
            # 后面的用例变成「两个 bug 同时存在」，证据看起来全一样（第一轮就踩了）。
            STATE.write_text(state_src, encoding="utf-8")
            ITEM.write_text(item_src, encoding="utf-8")
            path.write_text(source.replace(guard, "", 1), encoding="utf-8")
            ok, out = run()
            print(f"{label}：{'❌ 仍绿（断言无效）' if ok else '✅ 变红'}")
            if ok:
                failures += 1
                continue
            print("    " + first_failure(out))
    finally:
        STATE.write_text(state_src, encoding="utf-8")
        ITEM.write_text(item_src, encoding="utf-8")
    print("还原完成；负向全部有牙 ✅" if failures == 0 else "存在假绿 ⚠")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
