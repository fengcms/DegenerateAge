"""负向验证：确认「保星产物暂时穿不上」的 9 组用例真的有牙（工程 96）。

背景：这三层提示错起来都是**静默**的 —— 预览行不显示、确认区漏一句、toast 仍是「合成成功」，
游戏照常跑、保星照做、零报错，玩家只会某天一低头发现背包里有件 12★ 紫装穿不上，
既不知道差几级，也不知道是不是自己弄丢了。

N-1 `transfer_output_level` 丢掉 `slot_offset`（只看档不看部位）—— 用例 1「十个部位铺满」变红。
N-2 删掉预览里的 `_refresh_out_level(plan)` —— 用例 5「预览行应提示」变红。
N-3 删掉确认区的 `elif locked_level > 0` —— 用例 6「确认区应提示」变红。
N-4 toast 不再判等级（恒用「合成成功」）—— 用例 7「toast 必须带门槛」变红。
N-5 P4 退回普通 worn_warning（不判 locked）—— 用例 8「会少一件装备」变红。
N-6 文案里塞一个裸 `%`（incomplete format）—— 用例 4「解析出正文」变红。

🔴 每个用例前还原**所有**被改文件：只还原当次那个的话，上一轮补丁会留在盘上，
   第二次「变红」证明的就不是想验的那一条（工程 89 / 95 已踩两次）。

跑法：python3 tools/verify_96_star_transfer_hint_negative.py
"""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FUSION = ROOT / "scripts/systems/equipment_fusion.gd"
PANEL = ROOT / "scripts/ui/equipment_fusion_panel.gd"
LOCALIZATION = ROOT / "data/localization.json"
TEST = "StarTransferLevelHintTest"

# ---- 锚点（原文必须逐字命中，命中失败要报出来，不能静默跳过）----
OUTPUT_LEVEL_BODY = (
    "static func transfer_output_level(tier: int, kind: String) -> int:\n"
    "\tvar template_id := template_for(tier, kind)\n"
    "\tif template_id.is_empty():\n"
    "\t\treturn 0\n"
    "\treturn ItemFactory.dynamic_level_for(template_id, tier)"
)
OUTPUT_LEVEL_NO_OFFSET = (
    "static func transfer_output_level(tier: int, kind: String) -> int:\n"
    "\treturn ItemFactory.dynamic_tier_start(tier)"
)

PREVIEW_CALL = "\t\t_refresh_out_level(plan)\n"

CONFIRM_BRANCH = (
    "\t\telif locked_level > 0:\n"
    "\t\t\tlines.append(Localization.tr_key(\"ui.fusion.out_level_confirm\",\n"
    "\t\t\t\t[locked_level, level, locked_level - level]))\n"
)

TOAST_GUARD = (
    "\t\tif need > level:\n"
    "\t\t\ttext = Localization.tr_key(\"ui.fusion.done_locked\", [ItemUtil.display_name(gained), need])\n"
)

WORN_OVERLAY = (
    "\t\t\tlines.append(Localization.tr_key(\"ui.fusion.worn_locked_warning\", [names, locked_level])\n"
    "\t\t\t\tif locked_level > 0 else Localization.tr_key(\"ui.fusion.worn_warning\", [names]))\n"
)
WORN_PLAIN = "\t\t\tlines.append(Localization.tr_key(\"ui.fusion.worn_warning\", [names]))\n"

TEXT_OK = "还差 %d 级才能穿"
TEXT_BARE = "还差 %级才能穿"


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
    sources = {path: path.read_text(encoding="utf-8") for path in (FUSION, PANEL, LOCALIZATION)}

    # 前置：不改任何东西时必须全绿，否则后面的「变红」不说明任何问题。
    ok, out = run_test()
    if not ok:
        print("⚠ 基线不是绿的，先修基线再验负向：")
        print("    " + first_failure(out))
        return 1
    print("前置：未改动时 StarTransferLevelHintTest 全绿 ✅")

    cases = [
        ("N-1 产物等级丢掉 slot_offset（只看档不看部位）", "NO_OFFSET"),
        ("N-2 删掉预览行的 _refresh_out_level", "NO_PREVIEW"),
        ("N-3 删掉确认区的等级提示", "NO_CONFIRM"),
        ("N-4 toast 不再判等级", "NO_TOAST_GUARD"),
        ("N-5 P4 退回普通 worn_warning", "NO_WORN_OVERLAY"),
        ("N-6 文案塞裸 %（incomplete format）", "BARE_PERCENT"),
    ]

    failures = 0
    try:
        for label, mode in cases:
            # 🔴 每个用例前还原所有被改文件（不只是当次要改的那个）。
            for path, text in sources.items():
                path.write_text(text, encoding="utf-8")

            if mode == "NO_OFFSET":
                patch(FUSION, sources[FUSION], OUTPUT_LEVEL_BODY, OUTPUT_LEVEL_NO_OFFSET)
            elif mode == "NO_PREVIEW":
                patch(PANEL, sources[PANEL], PREVIEW_CALL, "")
            elif mode == "NO_CONFIRM":
                patch(PANEL, sources[PANEL], CONFIRM_BRANCH, "")
            elif mode == "NO_TOAST_GUARD":
                patch(PANEL, sources[PANEL], TOAST_GUARD, "")
            elif mode == "NO_WORN_OVERLAY":
                patch(PANEL, sources[PANEL], WORN_OVERLAY, WORN_PLAIN)
            elif mode == "BARE_PERCENT":
                patch(LOCALIZATION, sources[LOCALIZATION], TEXT_OK, TEXT_BARE)

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
