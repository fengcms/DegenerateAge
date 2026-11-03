"""检查 Godot ZIP 资源包边界与配置完整性；输入 --export-pack 产物，不读取玩家数据。"""
import argparse
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = ("docs/", "art_source/", "outputs/", "tests/", "tools/", "addons/")


def check_package(path: Path) -> list[str]:
    """校验资源清单及导入资源源路径，防预览纹理改名后藏入 .godot。"""
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        issues = [f"非运行文件混入：{name}" for name in names if name.startswith(FORBIDDEN)]
        for name in names:
            if name.endswith(".import"):
                text = archive.read(name).decode("utf-8")
                if any(f'res://{prefix}' in text for prefix in FORBIDDEN):
                    issues.append(f"非运行导入资源：{name}")
        for source in (ROOT / "data").rglob("*.json"):
            relative = source.relative_to(ROOT).as_posix()
            if relative not in names:
                issues.append(f"配置缺失：{relative}")
        return sorted(issues)


def main() -> int:
    """命令行检查已有 ZIP，非零退出表示导出不完整或越界。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    args = parser.parse_args()
    issues = check_package(args.package)
    print("\n".join(issues) if issues else "导出资源边界与全部 JSON 配置检查通过")
    return int(bool(issues))

if __name__ == "__main__":
    raise SystemExit(main())
