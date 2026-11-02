"""在一次性代码快照中负向验证NaN边界断言，不注入工作区，不恢复历史备份。

执行：python3 tools/verify_115_negative.py。每个变异必须红在指定断言，结束复核原始快照。
"""
from pathlib import Path
from isolated_project import isolated_project
from run_isolated_tests import run

RUNTIME = Path("scripts/systems/settings_runtime.gd")
SCENE = "res://tests/NanGuardTest.tscn"


def replace_once(text: str, old: str, new: str) -> str:
    """变异锚点必须唯一，避免源代码演进后出现无效负向覆盖。"""
    if text.count(old) != 1:
        raise RuntimeError("负向锚点不唯一：" + old)
    return text.replace(old, new, 1)


CASES = [
    (
        "N-1 判据退回 `<= 0.0` 写法（NaN / INF 全放行）",
        "NaN 尺寸必须判为不可用",
        RUNTIME,
        # 🔴 必须还原成**原始 bug 的形态** `not (x <= 0 or y <= 0)`。
        # 写成 `x > 0 and y > 0` 是**没牙**的：`NAN > 0` 为 false，反而把 NaN 拦住了，
        # 只会红在 INF 那条上（第一版就踩了，判成「红错断言」）。
        # 两者在浮点语义下并不等价 —— 这正是本 bug 的全部要害。
        lambda t: replace_once(
            t,
            "\treturn is_finite(size.x) and is_finite(size.y) and size.x > 0.0 and size.y > 0.0",
            "\treturn not (size.x <= 0.0 or size.y <= 0.0)",
        ),
    ),
    (
        "N-2 去掉 uiScale 的有限性兜底（NaN 直接透传）",
        "uiScale 为 NaN 时倍率必须是有限值",
        RUNTIME,
        lambda t: replace_once(
            t,
            "\tif not is_finite(raw):\n\t\traw = 1.0\n",
            "",
        ),
    ),
    (
        "N-3 去掉显示倍率的有限性兜底",
        "手动显示倍率为 NaN 时必须回落 1.0",
        RUNTIME,
        lambda t: replace_once(
            t,
            "\tif not is_finite(factor) or factor <= 0.0:\n\t\tfactor = 1.0\n",
            "\tif factor <= 0.0:\n\t\tfactor = 1.0\n",
        ),
    ),
]


def run_test(project: Path) -> tuple[bool, str]:
    """只启动隔离user目录中的短用例，不因无结果而冒充通过。"""
    return run(project, ["--scene", SCENE, "--quit-after", "600"], timeout=60)


def main() -> int:
    """同一代码快照内运行基线、三项独立变异和还原复测；源码工作区始终只读。"""
    with isolated_project() as (project, _name):
        ok, output = run(project, ["--editor", "--quit"], timeout=180)
        if not ok:
            print(output[-4000:])
            return 1
        ok, output = run_test(project)
        if not ok or "NanGuardTest: PASS" not in output:
            print("基线未通过\n" + output[-4000:])
            return 1
        for name, label, relative, mutate in CASES:
            path = project / relative
            original = path.read_text()
            try:
                path.write_text(mutate(original))
                ok, output = run_test(project)
            finally:
                path.write_text(original)
            if ok or "NanGuardTest: FAIL" not in output or label not in output:
                print("变异未在指定断言失败：" + name + "\n" + output[-4000:])
                return 1
            print("负向命中：" + name)
        ok, output = run_test(project)
        if not ok or "NanGuardTest: PASS" not in output:
            print("快照还原复测未通过\n" + output[-4000:])
            return 1
    print("负向验证3/3通过；工作区未被注入")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
