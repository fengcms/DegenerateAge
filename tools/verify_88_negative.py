#!/usr/bin/env python3
"""工程 88 负向验证：逐条注入典型 bug，确认 `DurabilityTest` 对应断言变红后自动还原。

用法：python3 tools/verify_88_negative.py [案例名]
⚠ 本脚本会临时改写源码，必须与全量隔离集**串行**执行（工程 77 并发事故教训）。

注入原则（工程 08 §11.3）：注入形态必须与**真实 bug 同形**，且结果必须是断言失败；
凡是靠「写死常量 / 删一整段」让编译器先炸掉的，都是假红（脚本会识别 Compile/Parse Error）。

六个靶子分三层：
- **口径层**（N-1 全清回归 / N-2 漏判耐久 / N-3 连星级品质一起砍）
- **分裂层**（N-4 bonus 抄回旧 continue / N-6 score 仍用 effective_attrs）
  —— 这是本改动最现实的退化方式：**只改一处、另一处漏了**，面板与结算从此各说各话。
- **评分层**（N-5 score 破损仍归 0）

两条最容易假绿的记在这里：
- **N-2**：若测试只断「破损 atk 等于基底」，把 `attrs_for_use` 写成恒返 `effective_attrs`
  会让 atk **大于**基底 —— 仍然红。真正必须同时存在的判据是「**严格小于满耐久**」那一条。
- **N-4**：`bonus()` 抄回 `continue` 后 atk 变 0，与「破损返回 {}」结果相同、报错文案也相同。
  两者不是重复：一个是口径函数坏、一个是调用点没接上，真实修法完全不同，所以分开列。
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MATH = ROOT / "scripts/systems/equipment_math.gd"
EQUIPMENT = ROOT / "scripts/systems/equipment.gd"
TEST = "DurabilityTest"

BROKEN_LINE = "\treturn base_attrs(item) if Durability.is_broken(item) else effective_attrs(item)"

CASES = [
    {
        # 真实 bug 形态 = 「回滚旧语义时只回滚了一半」：破损照样清空，挂机还是会被打死。
        "name": "N-1 破损返回空字典（全清回归，本需求被撤销）",
        "file": MATH,
        "old": BROKEN_LINE,
        "new": "\treturn {} if Durability.is_broken(item) else effective_attrs(item)  # 负向注入：全清",
    },
    {
        # 真实 bug 形态 = 「写了 attrs_for_use 但忘了判耐久」：破损件属性一点没降。
        "name": "N-2 漏判耐久（破损件词条照常生效）",
        "file": MATH,
        "old": BROKEN_LINE,
        "new": "\treturn effective_attrs(item)  # 负向注入：忘了判耐久",
    },
    {
        # 真实 bug 形态 = 「觉得原始基底才是基础」：品质与升星投入被一起砍掉（R4）。
        "name": "N-3 只返 rawBaseAttrs（星级与品质被砍）",
        "file": MATH,
        "old": BROKEN_LINE,
        "new": "\tif Durability.is_broken(item):\n"
               "\t\tvar raw: Variant = item.get(\"rawBaseAttrs\", {})\n"
               "\t\treturn raw if raw is Dictionary else {}  # 负向注入：砍掉品质/星级\n"
               "\treturn effective_attrs(item)",
    },
    {
        # 真实 bug 形态 = 「从工程 77 的文档抄回旧实现」：bonus 跳过、score 用基底 ⇒ 口径分裂。
        "name": "N-4 bonus() 抄回旧 continue（面板与结算分裂）",
        "file": EQUIPMENT,
        "old": "\t\taccumulate(b, EquipmentMath.attrs_for_use(it))",
        "new": "\t\tif Durability.is_broken(it):\n"
               "\t\t\tcontinue  # 负向注入：抄回工程 77 的旧实现\n"
               "\t\taccumulate(b, EquipmentMath.attrs_for_use(it))",
    },
    {
        # 真实 bug 形态 = 「只改生效、没改评分」：破损件仍 0 分，「属性更高」提示接着说谎（R2）。
        "name": "N-5 score() 破损仍归 0（换装提示谎报）",
        "file": EQUIPMENT,
        "old": "\tif item.is_empty():\n\t\treturn 0.0",
        "new": "\tif item.is_empty() or Durability.is_broken(item):\n\t\treturn 0.0  # 负向注入：评分仍归 0",
    },
    {
        # 真实 bug 形态 = 「改错调用点」：score 仍读 effective_attrs，破损件残值虚高。
        "name": "N-6 score() 仍用 effective_attrs（破损件残值虚高）",
        "file": EQUIPMENT,
        "old": "\taccumulate(b, EquipmentMath.attrs_for_use(item))",
        "new": "\taccumulate(b, EquipmentMath.effective_attrs(item))  # 负向注入：没接上口径",
    },
]


def run_case(case: dict) -> tuple[bool, str]:
    path: Path = case["file"]
    original = path.read_text(encoding="utf-8")
    if case["old"] not in original:
        return False, "注入点未找到（代码已变更，需更新脚本）：%s" % path.name
    path.write_text(original.replace(case["old"], case["new"], 1), encoding="utf-8")
    try:
        result = subprocess.run(
            ["python3", "tools/run_isolated_tests.py", TEST],
            capture_output=True, text=True, timeout=300, cwd=ROOT,
        )
        output = result.stdout + result.stderr
        if "Compile Error" in output or "Parse Error" in output:
            return False, "编译失败（无效红，掩盖真实 bug 形态）"
        is_red = "FAIL" in output or "失败" in output
        # 逐条列出**所有**失败断言：只看第一条会误判「红的不是我想要的那条」。
        details = list(dict.fromkeys(
            ln.strip().replace("ERROR: ", "")
            for ln in output.splitlines() if "ERROR:" in ln))
        return is_red, " / ".join(details[:4]) or "（无 ERROR 明细）"
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
    print()
    if bad:
        print(f"❌ 有 {len(bad)} 条负向没能变红：{bad}")
        return 1
    print(f"✅ 全部 {total} 条负向都变红（已还原源码）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
