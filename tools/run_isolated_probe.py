"""安全运行重铸调查探针：源存档只读复制到随机隔离项目，禁止沿用正式user目录。

例：python3 tools/run_isolated_probe.py ReforgeCrashProbe --save-file /path/to/copy.json
"""
import argparse
from pathlib import Path
import shutil
from isolated_project import isolated_project
from run_isolated_tests import run

PROBES = {"ReforgeCrashProbe", "ReloadCrashProbe", "FullPathProbe", "SplitProbe", "NoopProbe"}


def main() -> int:
    """校验显式存档副本并启动真实窗口；--headless仅用于逻辑诊断。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("probe", choices=sorted(PROBES))
    parser.add_argument("--save-file", type=Path, required=True)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--size", default="1280x1200")
    parser.add_argument("--probe-args", nargs=argparse.REMAINDER, default=[])
    args = parser.parse_args()
    if not args.save_file.is_file():
        parser.error("存档副本不存在")
    with isolated_project() as (project, name):
        ok, output = run(project, ["--editor", "--quit"], timeout=180)
        if not ok:
            print(output[-4000:])
            return 1
        # 由同一Godot进程先返回真实默认user路径，避免按宿主系统猜测目录。
        locator = project / "locate_user.gd"
        locator.write_text('extends SceneTree\nfunc _initialize() -> void:\n print("PROBE_USER=",OS.get_user_data_dir())\n quit()\n')
        ok, output = run(project, ["--script", str(locator)], timeout=30)
        paths = [line.removeprefix("PROBE_USER=") for line in output.splitlines() if line.startswith("PROBE_USER=")]
        if not ok or len(paths) != 1 or Path(paths[0]).name != name:
            raise RuntimeError("无法确认隔离user目录：" + output[-1000:])
        saves = Path(paths[0]) / "saves"
        saves.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(args.save_file, saves / "slot_1.json")
        ok, output = run(project, ["--scene", f"res://tools/{args.probe}.tscn", "--resolution", args.size, "--", *args.probe_args], timeout=180, rendered=not args.headless)
        print(output)
        return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
