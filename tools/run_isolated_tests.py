"""在独立 Godot 项目名和 user:// 下运行测试，保护真实存档。"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
import threading
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")
DEFAULT_TESTS = [
    "EquipmentAxesTest",
    "SettingsTest", "PotionAccessibilityTest", "AudioCuesTest", "FlowFeedbackTest",
    "DeathChoiceTest", "DeathDropTest", "RandomTicketTest", "TownScrollTest",
    "HotbarConfigTest", "HotbarUiTest", "InputFeedbackTest", "MenuFlowTest",
    "SkillCombatTest", "AutoControlAcceptance", "AutoExplorationSurvival",
    "BluePotionDropTest", "CaveNavigationTest", "ReviewRegressionTest",
    "BossReviewTest", "ChapterOneAcceptance", "SmokeTest",
]


def run(project: Path, args: list[str], timeout: int = 180, rendered: bool = False) -> tuple[bool, str]:
    process = subprocess.Popen(
        [str(GODOT), *([] if rendered else ["--headless"]), "--path", str(project), *args],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    lines: list[str] = []

    def collect() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            lines.append(line)
            # An aborted GDScript coroutine otherwise leaves the scene running
            # until the frame cap, with no opportunity to call get_tree().quit().
            if "SCRIPT ERROR:" in line:
                process.terminate()

    reader = threading.Thread(target=collect, daemon=True)
    reader.start()
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
        lines.append("FAIL: Godot test timed out\n")
    reader.join()
    output = "".join(lines)
    failed = process.returncode != 0 or "SCRIPT ERROR:" in output or "FAIL" in output
    return not failed, output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="*", default=DEFAULT_TESTS)
    parser.add_argument("--committed-tree", action="store_true", help="用已提交的稳定快照隔离并行美术试作")
    parser.add_argument("--rendered", action="store_true", help="以实际窗口运行指定测试，用于渲染采样")
    args = parser.parse_args()
    if not GODOT.is_file():
        print(f"Godot 未找到：{GODOT}", file=sys.stderr)
        return 2
    name = "DegenerateAge-Test-" + uuid.uuid4().hex[:12]
    # Godot macOS 默认 user:// 目录。只清理本次随机项目名；永不指向正式游戏名。
    user_data = Path.home() / "Library/Application Support/Godot/app_userdata" / name
    try:
        with tempfile.TemporaryDirectory(prefix="degenerateage-test-") as temporary:
            project = Path(temporary)
            if args.committed_tree:
                archive = subprocess.Popen(["git", "archive", "HEAD"], cwd=ROOT, stdout=subprocess.PIPE)
                assert archive.stdout is not None
                subprocess.run(["tar", "-x", "-C", str(project)], stdin=archive.stdout, check=True)
                archive.stdout.close()
                if archive.wait() != 0:
                    raise RuntimeError("无法读取已提交快照")
                print("使用已提交的稳定快照；工作区美术试作不参与本轮功能回归")
            else:
                for item in ROOT.iterdir():
                    if item.name.startswith(".") or item.name in {"project.godot", "build", "docs", "art_source"}:
                        continue
                    if item.name in {"scripts", "autoload", "data", "scenes", "tests", "addons"}:
                        # Freeze code/data so concurrent edits cannot invalidate an imported class cache.
                        shutil.copytree(item, project / item.name)
                    else:
                        (project / item.name).symlink_to(item, target_is_directory=item.is_dir())
            config = (project / "project.godot" if args.committed_tree else ROOT / "project.godot").read_text(encoding="utf-8")
            config = config.replace('config/name="末法纪元：最后的守护者"', f'config/name="{name}"', 1)
            (project / "project.godot").write_text(config, encoding="utf-8")
            ok, output = run(project, ["--editor", "--quit"])
            if not ok:
                print("资源导入失败\n" + output[-4000:], file=sys.stderr)
                return 1
            failures = []
            for test in args.tests:
                scene = f"res://tests/{test}.tscn"
                # Async physics tests must finish, not silently hit a render-frame cap.
                ok, output = run(project, ["--scene", scene, "--max-fps", "120",
                                           "--quit-after", "14400"], timeout=240, rendered=args.rendered)
                completed = any(marker in output for marker in ("PASS", "全部通过", "全部断言通过"))
                ok = ok and completed
                if not completed:
                    output += "\nFAIL: 测试未输出成功完成标记，不能视为通过\n"
                evidence = [line for line in output.splitlines() if "[PERF]" in line or "PASS" in line or "全部通过" in line or "全部断言通过" in line or "失败" in line or "FAIL" in line]
                print(f"{test}: {'PASS' if ok else 'FAIL'}" + (" · " + " | ".join(evidence[-24:]) if evidence else ""))
                if not ok:
                    failures.append(test)
                    diagnostics = [line for line in output.splitlines()
                                   if "SCRIPT ERROR:" in line or "ERROR:" in line or "失败：" in line]
                    for line in list(dict.fromkeys(diagnostics))[:12]:
                        print(line, file=sys.stderr)
            return int(bool(failures))
    finally:
        if user_data.is_dir():
            shutil.rmtree(user_data)


if __name__ == "__main__":
    raise SystemExit(main())
