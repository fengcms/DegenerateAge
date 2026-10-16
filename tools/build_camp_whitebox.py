"""将营地白盒原画布局编译为正式地图配置和等距通行掩码。

输入为 data/map_art/camp_whitebox_v2.json；输出仅覆盖 maps.json 的 camp 条目
及 data/layouts/camp.json。供布局调整后重建，不修改其他地图。
"""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/map_art/camp_whitebox_v2.json"
MAPS = ROOT / "data/maps.json"
LAYOUT = ROOT / "data/layouts/camp.json"
CLEARANCE = 14.0
VERSION = "2026-10-16-camp-open-perimeter-v2"


def canvas_to_world(point, source):
    """把原画像素映射到屏幕朝向的世界矩形，返回世界像素坐标。"""
    x, y, width, height = source["world_rect"]
    canvas_w, canvas_h = source["reference_canvas"]
    return x + point[0] * width / canvas_w, y + point[1] * height / canvas_h


def world_to_cell(point):
    """将世界像素取整到 64×32 等距格，与 Iso.world_to_grid 约定一致。"""
    x, y = point
    return [round((x / 32 - y / 16) / 2), round((-y / 16 - x / 32) / 2)]


def cell_to_world(col, row):
    """返回等距格中心世界像素，用于编译玩家半径留边。"""
    return (col - row) * 32, -(col + row) * 16


def near_polygon(point, polygon):
    """判断格中心是否在实体内或距边缘 14 像素内，避免路线擦碰。"""
    x, y = point
    inside = False
    for index, (ax, ay) in enumerate(polygon):
        bx, by = polygon[(index + 1) % len(polygon)]
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
            inside = not inside
        dx, dy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
        if (x - ax - t * dx) ** 2 + (y - ay - t * dy) ** 2 <= CLEARANCE ** 2:
            return True
    return inside


def nearest_open(point, rows, source):
    """将服务点吸附到最近可走格；目标绘制点仍保留在原画指定位置。"""
    x, y = world_to_cell(canvas_to_world(point, source))
    height, width = len(rows), len(rows[0])
    x, y = max(0, min(width - 1, x)), max(0, min(height - 1, y))
    if rows[y][x] == "1":
        return [x, y]
    for radius in range(1, max(width, height) + 1):
        for cy in range(max(0, y - radius), min(height - 1, y + radius) + 1):
            for cx in range(max(0, x - radius), min(width - 1, x + radius) + 1):
                if rows[cy][cx] == "1":
                    return [cx, cy]
    raise ValueError("营地无可走格")


def main():
    """从唯一实体多边形源重建掩码、NPC、出口和入口，并校验目标可走。"""
    source = json.loads(SOURCE.read_text())
    width, height = source["grid_size"]
    rx, ry, rw, rh = source["world_rect"]
    polygons = [
        [canvas_to_world(point, source) for point in entity["footprint"]]
        for entity in source["entities"]
    ] + [
        [canvas_to_world(point, source) for point in fence["polygon"]]
        for fence in source["fences"]
    ]
    rows = []
    for row in range(height):
        bits = []
        for col in range(width):
            x, y = cell_to_world(col, row)
            inside = rx + CLEARANCE <= x < rx + rw - CLEARANCE and ry + CLEARANCE <= y < ry + rh - CLEARANCE
            bits.append("1" if inside and not any(near_polygon((x, y), polygon) for polygon in polygons) else "0")
        rows.append("".join(bits))
    targets = {key: nearest_open(value, rows, source) for key, value in source["targets"].items()}
    spawn = nearest_open(source["spawn"], rows, source)
    camp_layout = {"id": "camp", "layoutVersion": VERSION, "grid_size": [width, height],
                   "points": targets | {"spawn": spawn}, "walkable_rows": rows}
    LAYOUT.write_text(json.dumps(camp_layout, ensure_ascii=False, separators=(",", ":")) + "\n")
    maps = json.loads(MAPS.read_text())
    camp = next(entry for entry in maps if entry["id"] == "camp")
    camp["size"] = {"w": width, "h": height}
    camp["worldRect"] = source["world_rect"]
    camp["layoutVersion"] = VERSION
    camp["safeArea"] = {"min": [43, 33], "max": [75, 79]}
    camp["spawnPoints"][0]["cells"] = [nearest_open(point, rows, source) for point in
                                       ([595, 665], [679, 680], [751, 665])]
    for npc in camp["npcs"]:
        npc["cell"] = targets[{"shop": "shop", "quest": "elder", "blacksmith": "blacksmith",
                               "warehouse": "warehouse", "carter": "carter"}[npc["role"]]]
    for exit_data in camp["exits"]:
        exit_data["cell"] = targets["east_exit" if exit_data["id"] == "to_wild" else "north_exit"]
    camp["entrances"] = {"from_wild": nearest_open([1540, 478], rows, source),
                         "from_c2": nearest_open([834, 110], rows, source)}
    # 外围开放只扩展可走区；原马车旅行落点仍可走时保留该格，避免重建时无意偏移。
    arrival = camp.get("carterArrival", [])
    if (isinstance(arrival, list) and len(arrival) == 2 and
            0 <= arrival[0] < width and 0 <= arrival[1] < height and
            rows[arrival[1]][arrival[0]] == "1"):
        camp["carterArrival"] = arrival
    else:
        camp["carterArrival"] = nearest_open([1044, 775], rows, source)
    MAPS.write_text(json.dumps(maps, ensure_ascii=False, indent=2) + "\n")
    print(f"营地白盒已编译：{width}×{height}，可走格 {sum(row.count('1') for row in rows)}")


if __name__ == "__main__":
    main()
