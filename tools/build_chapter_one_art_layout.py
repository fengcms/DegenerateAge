"""由第一章已批准的横向布局参考生成道路与多格美术实体摆放数据。

此脚本只读取文档参考和现有运行掩码，输出 data/map_art/chapter1_v2。
大型障碍一块一记录，轮廓由与运行掩码相同的格子边界合并而成。
"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "docs/游戏创意/第一章地图重设计示意图"
TARGET = ROOT / "data/map_art/chapter1_v2"
MAPS = {
    "camp": ("幸存者营地", ["merchant_stall", "forge_shelter", "warehouse", "forge_shelter", "guardian_lamp", "warehouse", "merchant_stall"]),
    "wild_trial": ("试炼野外", ["moss_ridge", "moss_ridge", "dead_tree", "moss_ridge", "dead_tree"]),
    "ash_land": ("灰烬之地", ["ruin_wall", "collapsed_house", "collapsed_house", "ruin_wall", "ruin_wall", "spirit_trench"]),
    "corruption_source": ("腐化源头", ["cave_buttress", "cave_buttress", "seal_arch", "cave_buttress", "cave_buttress", "arena_edge"]),
}
LANDMARKS = {
    "camp": [("campfire", "training_fire", (29, 28)), ("crate", "service_crate", (39, 23))],
    "wild_trial": [("insect_stone", "relic", (131, 34)), ("broken_cart", "road_cart", (70, 49)),
                   ("dead_tree", "wolf_king_branch", (142, 84))],
    "ash_land": [("ash_memorial", "memorial", (100, 31)), ("spirit_trench", "east_trench", (160, 22))],
    "corruption_source": [("seal_arch", "gate", (113, 45)), ("ritual_altar", "altar", (121, 43)),
                          ],
}
SMALL_DECOR = {"camp": ("camp", 10), "wild_trial": ("wild", 65),
               "ash_land": ("ash", 75), "corruption_source": ("cave", 55)}


def inside_polygon(x: float, y: float, vertices: list) -> bool:
    """复用编译布局相同的射线法，以格中心判定某格属于哪个规划障碍。"""
    inside = False
    previous = vertices[-1]
    for current in vertices:
        xi, yi = current
        xj, yj = previous
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        previous = current
    return inside


def outline(cells: set[tuple[int, int]]) -> list[list[float]]:
    """把一整块阻挡格的外边合成一个闭合多边形，消除逐格碰撞。"""
    edges: dict[tuple[int, int], tuple[int, int]] = {}
    for x, y in cells:
        left, top, right, bottom = x * 2 - 1, y * 2 - 1, x * 2 + 1, y * 2 + 1
        if (x, y - 1) not in cells:
            edges[(left, top)] = (right, top)
        if (x + 1, y) not in cells:
            edges[(right, top)] = (right, bottom)
        if (x, y + 1) not in cells:
            edges[(right, bottom)] = (left, bottom)
        if (x - 1, y) not in cells:
            edges[(left, bottom)] = (left, top)
    start = min(edges)
    path = [start]
    current = start
    while True:
        current = edges[current]
        if current == start:
            break
        assert current not in path, "阻挡轮廓自交"
        path.append(current)
    assert len(path) == len(edges), "一个规划障碍必须对应单个连通碰撞轮廓"
    simplified = []
    for index, point in enumerate(path):
        before, after = path[index - 1], path[(index + 1) % len(path)]
        if (point[0] - before[0]) * (after[1] - point[1]) == (point[1] - before[1]) * (after[0] - point[0]):
            continue
        simplified.append([point[0] / 2, point[1] / 2])
    return simplified


def road_rows(routes: list, rows: list[str], main_width: int = 1) -> list[str]:
    """按参考路线逐段采样并只在可走格铺路；主路宽三格，支路宽一格。"""
    height, width = len(rows), len(rows[0])
    mask = [["0"] * width for _ in range(height)]
    for route_index, route in enumerate(routes):
        for a, b in zip(route, route[1:]):
            steps = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
            for step in range(steps + 1):
                t = step / steps
                x, y = round(a[0] + (b[0] - a[0]) * t), round(a[1] + (b[1] - a[1]) * t)
                radius = main_width if route_index == 0 else 0
                for yy in range(y - radius, y + radius + 1):
                    for xx in range(x - radius, x + radius + 1):
                        if 0 <= xx < width and 0 <= yy < height and rows[yy][xx] == "1":
                            mask[yy][xx] = "1"
    return ["".join(row) for row in mask]


def visual_cells(cells: set[tuple[int, int]], map_id: str) -> list[list[int]]:
    """为同一个大型实体取少量内部视觉段，仍只输出一条实体记录。"""
    ordered = sorted(cells, key=lambda cell: (cell[0], cell[1]))
    if map_id in ("camp", "corruption_source"):
        xs = [cell[0] for cell in ordered]
        span = max(xs) - min(xs)
        count = min(5, max(1, span // 7 + 1))
        positions = []
        middle_y = sum(y for _, y in ordered) / len(ordered)
        for index in range(count):
            target_x = min(xs) + round(span * (index + 0.5) / count)
            candidate = min(ordered, key=lambda cell: (abs(cell[0] - target_x), abs(cell[1] - middle_y)))
            if list(candidate) not in positions:
                positions.append(list(candidate))
        return positions
    xs, ys = [cell[0] for cell in ordered], [cell[1] for cell in ordered]
    positions = []
    for row_index, target_y in enumerate(range(min(ys) + 2, max(ys) + 1, 9)):
        for target_x in range(min(xs) + 2 + (row_index % 2) * 4, max(xs) + 1, 9):
            candidate = min(ordered, key=lambda cell: abs(cell[0] - target_x) + abs(cell[1] - target_y))
            if abs(candidate[0] - target_x) + abs(candidate[1] - target_y) <= 5 and list(candidate) not in positions:
                positions.append(list(candidate))
            if len(positions) >= 16:
                return positions
    if not positions:
        positions.append(list(ordered[len(ordered) // 2]))
    return positions


def build_map(map_id: str, title: str, block_assets: list[str]) -> dict:
    """校验版本和格掩码，并生成一图的路面及整体多格实体数据。"""
    reference = json.loads((REFERENCE / f"{title}-布局参考.json").read_text())
    layout = json.loads((ROOT / f"data/layouts/{map_id}.json").read_text())
    assert reference["layoutVersion"] == layout["layoutVersion"]
    width, height = layout["grid_size"]
    rows = layout["walkable_rows"]
    roads = road_rows(reference["routes"], rows)
    entities = []
    claimed = set()
    for index, (vertices, asset) in enumerate(zip(reference["blocks"], block_assets, strict=True)):
        cells = {(x, y) for y in range(height) for x in range(width)
                 if rows[y][x] == "0" and inside_polygon(x + 0.5, y + 0.5, vertices)}
        assert cells and not claimed.intersection(cells), (map_id, index)
        claimed.update(cells)
        left, top = min(x for x, _ in cells), min(y for _, y in cells)
        right, bottom = max(x for x, _ in cells), max(y for _, y in cells)
        visuals = visual_cells(cells, map_id)
        record = {"instance_id": f"{map_id}_block_{index:02d}", "asset_id": asset,
                         "grid_position": [left, top], "footprint": [right - left + 1, bottom - top + 1],
                         "anchor": "bottom_center", "blocking": True,
                         "visual_cells": visuals, "collision_polygon": outline(cells)}
        if map_id == "wild_trial":
            record["visual_assets"] = ["dead_tree" if i % 4 == 3 else asset for i in range(len(visuals))]
        elif map_id == "ash_land":
            record["visual_assets"] = ["collapsed_house" if asset == "ruin_wall" and i % 4 == 3
                                       else "ruin_wall" if asset == "collapsed_house" and i % 3 == 2
                                       else asset for i in range(len(visuals))]
        entities.append(record)
    # The source reference blocks account for every solid tile; no hidden cell-level collisions remain.
    blocked = {(x, y) for y in range(height) for x in range(width) if rows[y][x] == "0"}
    assert claimed == blocked, (map_id, len(blocked - claimed))
    for asset, name, cell in LANDMARKS[map_id]:
        record = {"instance_id": f"{map_id}_{name}", "asset_id": asset,
                         "grid_position": list(cell), "footprint": [1, 1], "anchor": "bottom_center",
                         "blocking": False, "visual_cells": [list(cell)], "collision_polygon": [],
                         "visual_scale": 0.65 if asset not in ("campfire", "crate") else 1.0}
        if map_id == "camp":
            record["asset_path"] = f"res://assets/tiles/camp/{asset}.png"
        entities.append(record)
    theme, limit = SMALL_DECOR[map_id]
    protected = [tuple(point["cell"]) for point in reference["points"]]
    protected += [tuple(point["cell"]) for point in reference["exits"]]
    protected += [tuple(cell) for cell in reference["entrances"].values()]
    count = 0
    for y in range(2, height - 2):
        for x in range(2, width - 2):
            if count >= limit:
                break
            if rows[y][x] != "1" or roads[y][x] == "1" or (x * 73 + y * 37 + x * y * 11) % 331 != 0:
                continue
            if any(abs(x - px) <= 4 and abs(y - py) <= 4 for px, py in protected):
                continue
            variant = (x * 7 + y * 11) % 4
            asset = "crate" if theme == "camp" else f"prop_{variant}"
            entities.append({"instance_id": f"{map_id}_small_{count:03d}", "asset_id": asset,
                             "asset_path": f"res://assets/tiles/{theme}/{asset}.png",
                             "grid_position": [x, y], "footprint": [1, 1], "anchor": "bottom_center",
                             "blocking": False, "visual_cells": [[x, y]], "visual_scale": 0.42,
                             "collision_polygon": []})
            count += 1
    return {"map_id": map_id, "layoutVersion": layout["layoutVersion"], "grid_size": [width, height],
            "road_rows": roads, "entities": entities}


def main() -> None:
    """将四图正式摆放文件写入运行数据目录。"""
    TARGET.mkdir(parents=True, exist_ok=True)
    for map_id, (title, assets) in MAPS.items():
        result = build_map(map_id, title, assets)
        output = TARGET / f"{map_id}.json"
        output.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n")
        print(map_id, "entities", len(result["entities"]), "road", sum(row.count("1") for row in result["road_rows"]))


if __name__ == "__main__":
    main()
