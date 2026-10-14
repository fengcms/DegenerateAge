"""Export the committed chapter-two gameplay without concurrent worktree drafts."""

from __future__ import annotations

import argparse
import subprocess
import tarfile
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    output = (args.output or ROOT / f"build/DegenerateAge-Chapter2-FunctionPreview-{revision[:7]}.app").resolve()
    if not GODOT.is_file():
        raise SystemExit("Godot.app 未安装")
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise SystemExit(f"目标已存在，请另选路径或手动清理：{output}")
    with tempfile.TemporaryDirectory(prefix="degenerateage-export-") as temporary:
        project = Path(temporary)
        archive = subprocess.Popen(["git", "archive", revision], cwd=ROOT, stdout=subprocess.PIPE)
        assert archive.stdout is not None
        with tarfile.open(fileobj=archive.stdout, mode="r|") as tar:
            tar.extractall(project, filter="data")
        if archive.wait() != 0:
            raise SystemExit("无法读取已提交代码")
        for flags in (["--editor", "--quit"],
                      ["--export-debug", "Mac OSX", str(output)]):
            result = subprocess.run([str(GODOT), "--headless", "--path", str(project), *flags],
                                    capture_output=True, text=True, check=False)
            diagnostics = [line for line in (result.stdout + result.stderr).splitlines()
                           if "SCRIPT ERROR" in line or "ERROR:" in line or "ERROR " in line]
            for line in diagnostics[-20:]:
                print(line)
            if result.returncode != 0 or diagnostics:
                raise SystemExit(result.returncode or 1)
    print(f"导出完成：{output}，源提交 {revision}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
