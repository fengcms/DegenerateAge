"""临时负向验证：确认「并排同一行」与「无滚动条」两条断言真的有牙。

N-1 把服务网格压成 1 列（并排断言的同形 bug）
N-2 撤掉 fit_content 接管、把服务区高度写死回 clampf(logical.y-250, 54, 380)，
    并让服务内容再长 60px —— 等价于「以后再加一个服务项」。
    现阶段内容 369px 恰好还没顶到 380，所以只撤接管并不会红；加上这 60px 才是
    真实复发形态：硬上限会让滚动条重新常驻。三处注入必须一起撤，漏一处仍绿
    （「双保险只删一层＝假绿」）。
"""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PANEL = ROOT / "scripts/ui/blacksmith_panel.gd"
TEST = "EquipmentFusionUiTest"

# N-2 的三处注入点，全部撤回改动前的形态。
N2_EDITS = [
    ("\t# 交给浮窗层按可见区结算服务区高度（F-P2-3）：放得下就是内容高度，放不下才出滚动条。\n"
     "\t_center.set_content_scroll(_service_scroll)\n", ""),
    ("\t# 问候卡与服务卡互换后最小尺寸会变，重新触发一次结算再抢焦点。\n"
     "\t_center.set_content_scroll(_service_scroll)\n", ""),
    ("\t# 同一滚动容器重复注入是幂等的，只是触发一次 deferred 重排。\n"
     "\t_center.set_content_scroll(_service_scroll)\n",
     "\t_service_scroll.custom_minimum_size.y = clampf(logical.y - 250.0, 54.0, 380.0)\n"),
]


def run() -> tuple[bool, str]:
    proc = subprocess.run(["python3", "tools/run_isolated_tests.py", TEST],
                          cwd=ROOT, capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    return proc.returncode == 0, out


def main() -> int:
    source = PANEL.read_text(encoding="utf-8")
    failures = 0
    try:
        single_column = source.replace("\tgrid.columns = 2\n", "\tgrid.columns = 1\n", 1)
        assert single_column != source, "注入点缺失：N-1"
        rolled_back = source
        for old, new in N2_EDITS:
            assert old in rolled_back, f"注入点缺失：N-2 → {old.strip()[:24]}"
            rolled_back = rolled_back.replace(old, new, 1)
        # 「以后再加一个服务项」：内容 +60px。接管时仍应无滚动条，撤掉接管就该溢出。
        pad_anchor = "\t_continue.pressed.connect(_show_menu)\n"
        assert pad_anchor in rolled_back, "注入点缺失：N-2 pad"
        rolled_back = rolled_back.replace(pad_anchor, pad_anchor
            + "\tvar pad := Control.new()\n"
            + "\tpad.custom_minimum_size.y = 60.0\n"
            + "\t(forge_grid.get_parent() as VBoxContainer).add_child(pad)\n", 1)
        cases = [
            ("N-1 服务网格退回单列", single_column),
            ("N-2 撤掉 fit_content 接管、高度写死回 380", rolled_back),
        ]
        for label, patched in cases:
            PANEL.write_text(patched, encoding="utf-8")
            ok, out = run()
            print(f"{label}：{'❌ 仍绿（断言无效）' if ok else '✅ 变红'}")
            if ok:
                failures += 1
            else:
                for line in out.splitlines():
                    if "FAIL:" in line or "FAIL ·" in line or "FAIL " in line:
                        print("    " + line.strip()[:160])
                        break
    finally:
        PANEL.write_text(source, encoding="utf-8")
    print("还原完成；负向全部有牙 ✅" if failures == 0 else "存在假绿 ⚠")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
