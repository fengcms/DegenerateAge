"""校验并应用营地可视化编辑草稿，同时重建美术、碰撞和通行。

仅允许平移现有 7 个整体实体、4 段围栏与调整已有道路控制点；
NPC、出入口、画布、世界尺寸和其他布局字段保持不变。失败时恢复正式文件。
用法：python3 tools/apply_camp_map_editor.py data/map_art/camp_editor_draft.json
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from collections import deque
from pathlib import Path

import build_camp_whitebox as whitebox


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/map_art/camp_whitebox_v2.json"
MAPS = ROOT / "data/maps.json"
LAYOUT = ROOT / "data/layouts/camp.json"
ART = ROOT / "assets/maps/camp_style_full_b_v2"


def normalize_numbers(value):
    """Godot JSON 把整数读为浮点；提交前还原整数坐标以保持布局文件稳定。"""
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, list):
        return [normalize_numbers(item) for item in value]
    if isinstance(value, dict):
        return {key: normalize_numbers(item) for key, item in value.items()}
    return value


def translated_polygon(points: list[list[int]], dx: int, dy: int) -> list[list[int]]:
    """按参考画布像素平移完整多边形，不改变轮廓大小或顶点顺序。"""
    return [[x + dx, y + dy] for x, y in points]


def validate_object_edits(original: dict, draft: dict) -> None:
    """只接受既有实体的整体平移；不可通过草稿添加物件或改动关卡元数据。"""
    if set(original) != set(draft):
        raise ValueError("草稿修改了地图顶层字段")
    for key in original:
        if key not in {"entities", "fences", "main_road", "branches"} and draft[key] != original[key]:
            raise ValueError(f"固定地图字段被修改：{key}")
    for group in ("entities", "fences"):
        if len(original[group]) != len(draft[group]):
            raise ValueError(f"{group} 数量不能改变")
        for before, after in zip(original[group], draft[group]):
            if before["id"] != after["id"] or set(before) != set(after):
                raise ValueError("实体 ID 或字段不能改变")
            if group == "entities":
                old_rect, new_rect = before["art_rect"], after["art_rect"]
                dx, dy = new_rect[0] - old_rect[0], new_rect[1] - old_rect[1]
                expected = json.loads(json.dumps(before))
                expected["art_rect"][0] += dx
                expected["art_rect"][1] += dy
                expected["art_foot_y"] += dy
                expected["footprint"] = translated_polygon(before["footprint"], dx, dy)
                if "visual" in before:
                    expected["visual"] = translated_polygon(before["visual"], dx, dy)
                if "visual_foot_y" in before:
                    expected["visual_foot_y"] += dy
            else:
                old_point, new_point = before["polygon"][0], after["polygon"][0]
                dx, dy = new_point[0] - old_point[0], new_point[1] - old_point[1]
                expected = json.loads(json.dumps(before))
                expected["polygon"] = translated_polygon(before["polygon"], dx, dy)
            if not isinstance(dx, int) or not isinstance(dy, int) or expected != after:
                raise ValueError(f"{before['id']} 只支持整体像素平移")
            for point in after["footprint" if group == "entities" else "polygon"]:
                if not (0 <= point[0] <= 1672 and 0 <= point[1] <= 941):
                    raise ValueError(f"{before['id']} 的碰撞超出画布")
            if group == "entities":
                x, y, width, height = after["art_rect"]
                if not (0 <= x and 0 <= y and width > 0 and height > 0
                        and x + width <= 1672 and y + height <= 941):
                    raise ValueError(f"{before['id']} 的美术超出画布")


def validate_roads(original: dict, draft: dict) -> None:
    """道路只允许移动现有点，防止生成器收到零长线段或越界坐标。"""
    before_paths = [original["main_road"], *original["branches"]]
    after_paths = [draft["main_road"], *draft["branches"]]
    if len(before_paths) != len(after_paths):
        raise ValueError("道路分支数量不能改变")
    for before, after in zip(before_paths, after_paths):
        if len(before) != len(after) or len(after) < 2:
            raise ValueError("道路控制点数量不能改变")
        for index, point in enumerate(after):
            if (not isinstance(point, list) or len(point) != 2
                    or any(not isinstance(value, int) for value in point)
                    or not (0 <= point[0] <= 1672 and 0 <= point[1] <= 941)):
                raise ValueError("道路控制点必须是画布内整数像素")
            if index > 0 and point == after[index - 1]:
                raise ValueError("道路出现零长线段")


def compiled_rows(source: dict) -> list[str]:
    """使用正式白盒构建器同一几何函数，在写盘前计算可行走掩码。"""
    width, height = source["grid_size"]
    rx, ry, rw, rh = source["world_rect"]
    polygons = [[whitebox.canvas_to_world(point, source) for point in entity["footprint"]]
                for entity in source["entities"]]
    polygons += [[whitebox.canvas_to_world(point, source) for point in fence["polygon"]]
                 for fence in source["fences"]]
    rows = []
    for row in range(height):
        bits = []
        for col in range(width):
            x, y = whitebox.cell_to_world(col, row)
            inside = (rx + whitebox.CLEARANCE <= x < rx + rw - whitebox.CLEARANCE
                      and ry + whitebox.CLEARANCE <= y < ry + rh - whitebox.CLEARANCE)
            bits.append("1" if inside and not any(whitebox.near_polygon((x, y), polygon)
                                                for polygon in polygons) else "0")
        rows.append("".join(bits))
    return rows


def validate_fixed_targets(source: dict, rows: list[str]) -> None:
    """要求 NPC、入口、出口和出生点保留现有格，且各服务点仍从出生点可达。"""
    maps = json.loads(MAPS.read_text())
    camp = next(item for item in maps if item["id"] == "camp")
    targets = source["targets"]
    expected = {"shop": "shop", "quest": "elder", "blacksmith": "blacksmith",
                "warehouse": "warehouse", "carter": "carter"}
    cells = []
    for npc in camp["npcs"]:
        cell = whitebox.nearest_open(targets[expected[npc["role"]]], rows, source)
        if cell != npc["cell"]:
            raise ValueError(f"编辑会改变 NPC 格：{npc['role']}")
        cells.append(cell)
    for exit_data in camp["exits"]:
        name = "east_exit" if exit_data["id"] == "to_wild" else "north_exit"
        cell = whitebox.nearest_open(targets[name], rows, source)
        if cell != exit_data["cell"]:
            raise ValueError(f"编辑会改变出口格：{name}")
        cells.append(cell)
    for name, point in {"from_wild": [1540, 478], "from_c2": [834, 110]}.items():
        cell = whitebox.nearest_open(point, rows, source)
        if cell != camp["entrances"][name]:
            raise ValueError(f"编辑会改变入口格：{name}")
        cells.append(cell)
    for point, expected_cell in zip(([595, 665], [679, 680], [751, 665]),
                                    camp["spawnPoints"][0]["cells"]):
        if whitebox.nearest_open(point, rows, source) != expected_cell:
            raise ValueError("编辑会改变训练场刷新格")
    arrival = camp.get("carterArrival", [])
    if len(arrival) == 2 and rows[arrival[1]][arrival[0]] != "1":
        raise ValueError("编辑会挡住马车旅行落点")
    spawn = whitebox.nearest_open(source["spawn"], rows, source)
    if spawn != json.loads(LAYOUT.read_text())["points"]["spawn"]:
        raise ValueError("编辑会改变玩家出生格")
    seen = {tuple(spawn)}
    queue = deque([tuple(spawn)])
    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if (0 <= ny < len(rows) and 0 <= nx < len(rows[0])
                    and rows[ny][nx] == "1" and (nx, ny) not in seen):
                seen.add((nx, ny))
                queue.append((nx, ny))
    if any(tuple(cell) not in seen for cell in cells):
        raise ValueError("编辑切断了 NPC 或出入口到出生点的通路")


def apply(draft_path: Path) -> None:
    """验证草稿后运行两套正式构建器；任何失败都恢复原文件，成功后删除草稿。"""
    source_bytes = SOURCE.read_bytes()
    envelope = json.loads(draft_path.read_text())
    if envelope.get("base_hash") != hashlib.sha256(source_bytes).hexdigest():
        raise ValueError("正式营地自打开草稿后已变化，请重新载入后再编辑")
    original = json.loads(source_bytes)
    draft = normalize_numbers(envelope["layout"])
    if not isinstance(draft, dict):
        raise ValueError("草稿缺少布局对象")
    validate_object_edits(original, draft)
    validate_roads(original, draft)
    rows = compiled_rows(draft)
    validate_fixed_targets(draft, rows)
    paths = [SOURCE, MAPS, LAYOUT, *ART.glob("*.png"), ART / "manifest.json"]
    backup = {path: path.read_bytes() for path in paths if path.is_file()}
    try:
        SOURCE.write_text(json.dumps(draft, ensure_ascii=False, indent=2) + "\n")
        for script in ("build_camp_whitebox.py", "build_camp_style_full_b_v2.py"):
            subprocess.run([sys.executable, str(ROOT / "tools" / script)], check=True,
                           cwd=ROOT, capture_output=True, text=True)
    except Exception:
        for path, contents in backup.items():
            path.write_bytes(contents)
        raise
    draft_path.unlink()
    print("营地草稿已应用：整体美术、道路、碰撞与通行已同步重建。")


def main() -> int:
    """命令行入口：错误以中文返回到 Godot 编辑器状态栏，不写真实游戏存档。"""
    if len(sys.argv) != 2:
        print("用法：python3 tools/apply_camp_map_editor.py <草稿路径>", file=sys.stderr)
        return 2
    try:
        apply(Path(sys.argv[1]).resolve())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"营地编辑应用失败：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
