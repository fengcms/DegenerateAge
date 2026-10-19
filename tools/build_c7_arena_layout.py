"""生成第七章循环 Boss 图 `c7_arena` 的运行时可行走掩码（写入 data/layouts/）。

职责：按**几何公式**（而非手绘多边形）栅格化一张环形回廊，逐项断言
「出口 / 车夫落点 / 20 个 Boss 格全部可走、全部可走格四邻接连通」后写出
`data/layouts/c7_arena.json`。产物只进 `data/layouts/`，不写 `assets/`。

适用场景：回廊几何或 Boss 坐标调整后重跑本脚本重建掩码。
脚本幂等：输入不变时重复运行产物字节一致，可作为漂移校验。

几何口径：
  · 环形走廊 = 外椭圆(a=72,b=38) 减 内椭圆(a=20,b=11)，中心 (80,45)；
  · 西门走廊 = 4 ≤ x ≤ 40 且 42 ≤ y ≤ 48，连接入口 (8,45) 与环；
  · 已移除原有的五个区厅部件。

固定格一律取自 `data/maps/ch07/c7_arena/map.json`（单一事实源），脚本不重复硬编码。
"""

import json
from collections import deque
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAP_PATH = ROOT / "data/maps/ch07/c7_arena/map.json"
DEST = ROOT / "data/layouts/c7_arena.json"

# 环形回廊几何（格坐标；中心与半轴）。
CENTER = (80.0, 45.0)
OUTER = (72.0, 38.0)
INNER = (20.0, 11.0)
# 西门走廊（矩形，闭区间）。
WEST_CORRIDOR = (4, 40, 42, 48)


def is_walkable(x, y):
    """单格是否可走：环形走廊 ∨ 西门走廊。

    外椭圆只用于界定环形走廊；西门走廊在外椭圆之外，因此不能把外椭圆当作
    西门走廊的先决条件。
    """
    dx = (x - CENTER[0]) / OUTER[0]
    dy = (y - CENTER[1]) / OUTER[1]
    if dx * dx + dy * dy <= 1.0:
        ix = (x - CENTER[0]) / INNER[0]
        iy = (y - CENTER[1]) / INNER[1]
        if ix * ix + iy * iy > 1.0:
            return True  # 外椭圆内、内椭圆外 ⇒ 环形走廊
    x0, x1, y0, y1 = WEST_CORRIDOR
    return x0 <= x <= x1 and y0 <= y <= y1


def fixed_cells(map_data):
    """所有必须落在掩码 "1" 上的固定格：出口 / 车夫落点 / 10 个 Boss 位。"""
    cells = {}
    for entry in map_data.get("exits", []):
        cells[entry["id"]] = entry["cell"]
    if map_data.get("carterArrival"):
        cells["carterArrival"] = map_data["carterArrival"]
    for index, spec in enumerate(map_data.get("bossSpawns", [])):
        cells["spawn%03d" % index] = spec["cell"]
    return cells


def reachable(rows, start):
    """四邻接洪泛：返回从 start 可达的全部可走格。"""
    height = len(rows)
    width = len(rows[0])
    seen = {start}
    queue = deque([start])
    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < width and 0 <= ny < height and rows[ny][nx] == "1" and (nx, ny) not in seen:
                seen.add((nx, ny))
                queue.append((nx, ny))
    return seen


def main():
    map_data = json.loads(MAP_PATH.read_text(encoding="utf-8"))
    width, height = map_data["size"]["w"], map_data["size"]["h"]

    rows = ["".join("1" if is_walkable(x, y) else "0" for x in range(width))
            for y in range(height)]
    total = sum(row.count("1") for row in rows)

    cells = fixed_cells(map_data)
    for name, (cx, cy) in cells.items():
        assert 0 <= cx < width and 0 <= cy < height, "%s 超出画布：%s" % (name, (cx, cy))
        assert rows[cy][cx] == "1", "%s 落在不可走格：%s" % (name, (cx, cy))

    start = tuple(map_data["exits"][0]["cell"])
    seen = reachable(rows, start)
    assert len(seen) == total, "可走格不连通：从 %s 只到 %d / %d" % (start, len(seen), total)

    result = {
        "id": map_data["id"],
        "layoutVersion": map_data["layoutVersion"],
        "grid_size": [width, height],
        "points": cells,
        "walkable_rows": rows,
    }
    DEST.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n",
                    encoding="utf-8")
    print(result["id"], result["grid_size"], "walkable", total,
          "连通", len(seen), "固定格", len(cells))


if __name__ == "__main__":
    main()
