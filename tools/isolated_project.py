"""为诊断与负向注入创建一次性代码快照和随机user目录，不改工作区或正式存档。"""
from contextlib import contextmanager
from pathlib import Path
import os
import re
import shutil
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]


def userdata_paths(name: str) -> list[Path]:
    """只返回本次随机项目名的跨平台默认user目录，供退出时清理。"""
    return [Path.home() / "Library/Application Support/Godot/app_userdata" / name,
            Path(os.environ.get("APPDATA", str(Path.home() / "AppData/Roaming"))) / "Godot/app_userdata" / name,
            Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "godot/app_userdata" / name]


@contextmanager
def isolated_project():
    """冻结代码/数据、复用只读素材；退出或异常时清理本次唯一命名目录。"""
    name = "DegenerateAge-Test-" + uuid.uuid4().hex[:12]
    try:
        with tempfile.TemporaryDirectory(prefix="degenerateage-probe-") as temporary:
            project = Path(temporary)
            for item in ROOT.iterdir():
                if item.name.startswith(".") or item.name in {"project.godot", "build", "docs", "art_source"}:
                    continue
                if item.name in {"scripts", "autoload", "data", "scenes", "tests", "addons", "tools"}:
                    shutil.copytree(item, project / item.name)
                else:
                    (project / item.name).symlink_to(item, target_is_directory=item.is_dir())
            config = (ROOT / "project.godot").read_text()
            config, matches = re.subn(r'^config/name=".*"$', f'config/name="{name}"', config, count=1, flags=re.M)
            if matches != 1:
                raise RuntimeError("无法设置隔离项目名")
            config = config.replace('config/use_custom_user_dir=true', 'config/use_custom_user_dir=false')
            (project / "project.godot").write_text(config)
            yield project, name
    finally:
        for path in userdata_paths(name):
            shutil.rmtree(path, ignore_errors=True)
