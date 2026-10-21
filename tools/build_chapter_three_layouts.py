"""第三章地图布局编译工具：从创意参考生成通行掩码与具名点。

运行时只读取 data/layouts；本工具在内容调整后手工执行，并验证剧情点与整张地形连通。
"""

import json
from collections import deque
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSION = "2026-10-15-content-v1"
SOURCE_DIR = ROOT / "docs/游戏创意/21-60级内容规划/第三章/地图参考"
DEST = ROOT / "data/layouts"

## NPC 与 Boss 圆心坐标：创意事实源表格（创意 JSON 只给 id，不给格坐标）。
NPC_CELLS = {
    "c3_npc01": [33, 22], "c3_npc02": [42, 22], "c3_npc03": [52, 22], "c3_npc04": [61, 22],
    "c3_npc05": [33, 35], "c3_npc06": [42, 35], "c3_npc07": [52, 35], "c3_npc08": [61, 35],
    "c3_npc09": [23, 54], "c3_npc10": [21, 50],
}
BOSS_CELLS = {"c3_boss01": [179, 59], "c3_boss02": [151, 50], "c3_boss03": [179, 59]}


def inside_polygon(x, y, polygon):
    """判断格中心是否落在不可走多边形内，编译每张静态布局时调用。"""
    inside = False
    j = len(polygon) - 1
    for i, (xi, yi) in enumerate(polygon):
        xj, yj = polygon[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def fixed_cells(source):
    """收集出口、刷新、NPC 和剧情地标等不可被地形封死的格坐标。"""
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
    """把布局参考中的具名位置导出为运行时索引，不改变点的格坐标。"""
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
    """查询指定格附近的可走点，用于车夫回程落点容错。"""
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
    """从回程出口附近选取车夫落点；城镇正式落点由地图配置控制。"""
    exit_cell = source["exits"][0]["cell"]
    target = (int(exit_cell[0]) + 6, int(exit_cell[1]))
    return list(nearest_walkable(rows, width, height, target))


def compile_one(source):
    """将原障碍与主题地形编译成唯一通行掩码，并检查全部固定点连通。"""
    assert source["layoutVersion"] == VERSION, source["id"]
    width, height = source["w"], source["h"]
    # 中段图允许轻微改变画幅比例，让每张地图的尺寸组合与外轮廓都可辨认。
    assert width > 0 and height > 0 and 1.5 <= width / height <= 2.0, source["id"]
    # 主题地形与原障碍共同决定显示、碰撞和寻路；只在编译时合并一次。
    obstacles = source["obstacles"] + [feature["polygon"] for feature in source.get("terrainFeatures", [])]
    rows = []
    for y in range(height):
        rows.append("".join(
            "0" if any(inside_polygon(x + 0.5, y + 0.5, polygon)
                       for polygon in obstacles) else "1"
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
    """批量编译本章地图参考到运行布局文件，供地图服务和碰撞寻路共用。"""
    sources = sorted(SOURCE_DIR.glob("c3_map0*.json"))
    assert len(sources) == 6, len(sources)
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
