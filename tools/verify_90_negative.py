"""负向验证：确认「F 联动开拾取」与「提示文案准确」两条断言真的有牙。

N-1 去掉联动（开战斗不再打开拾取）
N-2 提示恒定说「已同时开启」（拾取本来就开着时误导玩家）
"""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT / "autoload/game_state.gd"
TEST = "InputFeedbackTest"

CASES = [
    ("N-1 开战斗不再联动打开拾取", "\tif on and not auto_pickup_on:\n",
     "\tif false and not auto_pickup_on:\n"),
    ("N-2 提示恒说「已同时开启」", "\tif on and pickup_was_on:\n",
     "\tif false and pickup_was_on:\n"),
]


def run() -> tuple[bool, str]:
    proc = subprocess.run(["python3", "tools/run_isolated_tests.py", TEST],
                          cwd=ROOT, capture_output=True, text=True)
    return proc.returncode == 0, proc.stdout + proc.stderr


def main() -> int:
    source = STATE.read_text(encoding="utf-8")
    failures = 0
    try:
        for label, old, new in CASES:
            assert old in source, f"注入点缺失：{label}"
            STATE.write_text(source.replace(old, new, 1), encoding="utf-8")
            ok, out = run()
            print(f"{label}：{'❌ 仍绿（断言无效）' if ok else '✅ 变红'}")
            if ok:
                failures += 1
            else:
                for line in out.splitlines():
                    if "FAIL:" in line or "FAIL ·" in line:
                        print("    " + line.strip()[:180])
                        break
    finally:
        STATE.write_text(source, encoding="utf-8")
    print("还原完成；负向全部有牙 ✅" if failures == 0 else "存在假绿 ⚠")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
