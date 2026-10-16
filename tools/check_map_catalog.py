"""检查地图目录、配置、布局与 README 同步情况；可选择刷新自动参数区。

用法：python3 tools/check_map_catalog.py [--update]。只检查本地配置，不读写游戏存档。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from map_catalog import END, ROOT, START, chapter_of, map_paths, parameter_section, refresh_readme


def main() -> int:
    """检查 1 图 1 目录、章节、布局和说明，返回非零值表示需修正。"""
    update = len(sys.argv) == 2 and sys.argv[1] == "--update"
    if len(sys.argv) > 2 or (len(sys.argv) == 2 and not update):
        print("用法：python3 tools/check_map_catalog.py [--update]", file=sys.stderr)
        return 2
    paths = map_paths(ROOT)
    errors = []
    if not (ROOT / "data/maps/README.md").is_file():
        errors.append("地图总目录缺少 README.md")
    registered = set(paths.values())
    actual = set((ROOT / "data/maps").glob("ch*/*/map.json"))
    if actual != registered:
        errors.append(f"索引与目录文件不一致：未登记 {actual - registered}；缺失 {registered - actual}")
    for map_id, path in paths.items():
        chapter_readme = path.parent.parent / "README.md"
        if not chapter_readme.is_file() or f"({map_id}/README.md)" not in chapter_readme.read_text(encoding="utf-8"):
            errors.append(f"章节说明未登记地图：{map_id}")
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or data.get("id") != map_id:
            errors.append(f"目录 ID 与配置不符：{path}")
            continue
        if path.parent.parent.name != f"ch{chapter_of(map_id):02d}":
            errors.append(f"章节目录与地图 ID 不符：{path}")
        layout = str(data.get("layoutPath", ""))
        if layout and (not layout.startswith("res://") or not (ROOT / layout[6:]).is_file()):
            errors.append(f"布局文件缺失：{map_id} -> {layout}")
        readme = path.parent / "README.md"
        if update:
            refresh_readme(path, data)
        if not readme.is_file():
            errors.append(f"地图说明缺失：{readme}")
            continue
        content = readme.read_text(encoding="utf-8")
        if (not content.startswith(f"# {data['name']}\n") or content.count(START) != 1
                or content.count(END) != 1 or parameter_section(data) not in content):
            errors.append(f"地图说明与配置不一致：{readme}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"地图目录校验通过：{len(paths)} 张地图、配置与 README 一致")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
