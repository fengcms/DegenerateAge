"""Compile the approved landscape-v2 references into runtime walkable masks.

Reference polygons live in docs; the game reads only data/layouts/*.json.
Run this script after a layout revision and review both the reference and result.
"""

import json
from collections import deque
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSION = "2026-10-14-landscape-v2"
SOURCES = [
    *sorted((ROOT / "docs/游戏创意/第一章地图重设计示意图").glob("*-布局参考.json")),
    *sorted((ROOT / "docs/游戏创意/地图示意图").glob("*-布局参考.json")),
]
DEST = ROOT / "data/layouts"


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
    cells = []
    for value in source.get("entrances", {}).values():
        cells.append(tuple(value))
    cells.append(tuple(source["carterArrival"]))
    for entry in source.get("exits", []):
        cells.append(tuple(entry["cell"]))
    for entry in source.get("points", []):
        if entry.get("kind") != "landmark":
            cells.append(tuple(entry["cell"]))
    for zone in source.get("zones", []):
        cells.append(tuple(zone["center"]))
    return cells


def compile_one(source):
    assert source["layoutVersion"] == VERSION, source["id"]
    width, height = source["size"]
    assert width * 9 == height * 16, source["id"]
    rows = []
    for y in range(height):
        rows.append("".join(
            "0" if any(inside_polygon(x + 0.5, y + 0.5, polygon)
                       for polygon in source["blocks"]) else "1"
            for x in range(width)
        ))
    for x, y in fixed_cells(source):
        assert 0 <= x < width and 0 <= y < height, (source["id"], x, y)
        assert rows[y][x] == "1", (source["id"], "blocked fixed point", x, y)
    start = fixed_cells(source)[0]
    seen = {start}
    queue = deque([start])
    while queue:
        x, y = queue.popleft()
        for candidate in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            nx, ny = candidate
            if 0 <= nx < width and 0 <= ny < height and rows[ny][nx] == "1" and candidate not in seen:
                seen.add(candidate)
                queue.append(candidate)
    assert all(cell in seen for cell in fixed_cells(source)), (source["id"], "unreachable fixed point")
    assert sum(row.count("1") for row in rows) == len(seen), (source["id"], "disconnected floor")
    return {
        "id": source["id"],
        "layoutVersion": VERSION,
        "grid_size": [width, height],
        "points": {entry["id"]: entry["cell"] for entry in source.get("points", [])},
        "walkable_rows": rows,
    }


def main():
    assert len(SOURCES) == 10, len(SOURCES)
    DEST.mkdir(parents=True, exist_ok=True)
    for path in SOURCES:
        result = compile_one(json.loads(path.read_text()))
        target = DEST / (result["id"] + ".json")
        target.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n")
        print(result["id"], result["grid_size"], "walkable", sum(row.count("1") for row in result["walkable_rows"]))


if __name__ == "__main__":
    main()
