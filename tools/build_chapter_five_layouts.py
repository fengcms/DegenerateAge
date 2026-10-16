"""Compile the approved chapter-five references into runtime walkable masks.

Reference polygons live in docs; the game reads only data/layouts/*.json.
Run this script after a layout revision and review both the reference and result.
The NPC / Boss cell coordinates come from the content source
`docs/游戏创意/21-60级内容规划/第五章/02-地图与布局.md`.
"""

import json
from collections import deque
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSION = "2026-10-15-content-v1"
SOURCE_DIR = ROOT / "docs/游戏创意/21-60级内容规划/第五章/地图参考"
DEST = ROOT / "data/layouts"

## NPC 与 Boss 圆心坐标：创意事实源表格（创意 JSON 只给 id，不给格坐标）。
NPC_CELLS = {
    "c5_npc01": [33, 22], "c5_npc02": [42, 22], "c5_npc03": [52, 22], "c5_npc04": [61, 22],
    "c5_npc05": [33, 35], "c5_npc06": [42, 35], "c5_npc07": [52, 35], "c5_npc08": [61, 35],
    "c5_npc09": [25, 59], "c5_npc10": [21, 50], "c5_npc11": [25, 59],
}
BOSS_CELLS = {
    "c5_boss01": [165, 54], "c5_boss02": [151, 50],
    "c5_boss03": [179, 59], "c5_boss04": [193, 63],
}


def inside_polygon(x, y, polygon):
    inside = False
    j = len(polygon) - 1
    for i, (xi, yi) in enumerate(polygon):
        xj, yj = polygon[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def fixed_cells(source):
    """所有必须落在掩码 "1" 上的固定格：出口 / 刷新位 / 精英 / Boss / NPC / 地标。"""
    cells = []
    for entry in source.get("exits", []):
        cells.append(tuple(entry["cell"]))
    for entry in source.get("spawns", []):
        cells.append(tuple(entry["cell"]))
    for entry in source.get("elites", []):
        cells.append(tuple(entry["cell"]))
    for boss_id in source.get("bosses", []):
        cells.append(tuple(BOSS_CELLS[boss_id]))
    for npc_id in source.get("npcs", []):
        cells.append(tuple(NPC_CELLS[npc_id]))
    for entry in source.get("landmarks", []):
        cells.append(tuple(entry["cell"]))
    return cells


def collect_points(source):
    """导出给运行时的具名点；出口用出口 id，其余用稳定可读键。"""
    points = {}
    for entry in source.get("exits", []):
        points[entry["id"]] = entry["cell"]
    for index, entry in enumerate(source.get("spawns", [])):
        points["spawn%03d" % index] = entry["cell"]
    for index, entry in enumerate(source.get("elites", [])):
        points["elite%02d" % index] = entry["cell"]
    for boss_id in source.get("bosses", []):
        points[boss_id] = BOSS_CELLS[boss_id]
    for npc_id in source.get("npcs", []):
        points[npc_id] = NPC_CELLS[npc_id]
    for entry in source.get("landmarks", []):
        points[entry["name"]] = entry["cell"]
    return points


def nearest_walkable(rows, width, height, cell):
    """最近的可走格（含自身）；用于断言前的兜底定位。"""
    start = (int(cell[0]), int(cell[1]))
    if 0 <= start[0] < width and 0 <= start[1] < height and rows[start[1]][start[0]] == "1":
        return start
    seen = {start}
    queue = deque([start])
    while queue:
        x, y = queue.popleft()
        for candidate in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            nx, ny = candidate
            if not (0 <= nx < width and 0 <= ny < height) or candidate in seen:
                continue
            if rows[ny][nx] == "1":
                return candidate
            seen.add(candidate)
            queue.append(candidate)
    return start


def carter_arrival(source, rows, width, height):
    """回程出口附近 4—6 格内侧的可走落点（仿 c2/c3 写法）。"""
    exit_cell = source["exits"][0]["cell"]
    target = (int(exit_cell[0]) + 6, int(exit_cell[1]))
    return list(nearest_walkable(rows, width, height, target))


def compile_one(source):
    assert source["layoutVersion"] == VERSION, source["id"]
    width, height = source["w"], source["h"]
    assert width * 9 == height * 16, source["id"]
    rows = []
    for y in range(height):
        rows.append("".join(
            "0" if any(inside_polygon(x + 0.5, y + 0.5, polygon)
                       for polygon in source["obstacles"]) else "1"
            for x in range(width)
        ))
    fixed = fixed_cells(source)
    for x, y in fixed:
        assert 0 <= x < width and 0 <= y < height, (source["id"], "out of bounds", x, y)
        assert rows[y][x] == "1", (source["id"], "blocked fixed point", x, y)
    start = fixed[0]
    seen = {start}
    queue = deque([start])
    while queue:
        x, y = queue.popleft()
        for candidate in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            nx, ny = candidate
            if 0 <= nx < width and 0 <= ny < height and rows[ny][nx] == "1" and candidate not in seen:
                seen.add(candidate)
                queue.append(candidate)
    assert all(cell in seen for cell in fixed), (source["id"], "unreachable fixed point")
    ones = sum(row.count("1") for row in rows)
    assert ones == len(seen), (source["id"], "disconnected floor", ones, len(seen))
    return {
        "id": source["id"],
        "layoutVersion": VERSION,
        "grid_size": [width, height],
        "points": collect_points(source),
        "walkable_rows": rows,
    }


def main():
    sources = sorted(SOURCE_DIR.glob("c5_map0*.json"))
    assert len(sources) == 7, len(sources)
    DEST.mkdir(parents=True, exist_ok=True)
    for path in sources:
        source = json.loads(path.read_text())
        result = compile_one(source)
        target = DEST / (result["id"] + ".json")
        target.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n")
        print(result["id"], result["grid_size"],
              "walkable", sum(row.count("1") for row in result["walkable_rows"]),
              "reachableCount", source.get("reachableCount"))


if __name__ == "__main__":
    main()
