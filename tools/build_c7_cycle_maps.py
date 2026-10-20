"""生成第七章两张循环地图配置和可通行布局。

运行 ``python3 tools/build_c7_cycle_maps.py``。刷新格和布局由本工具确定性生成；
地图 README 的人工说明仍须同步编辑，再运行 check_map_catalog.py --update。
"""

import json
import math
from collections import deque
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAPTER = ROOT / "data/maps/ch07"
LAYOUT_DIR = ROOT / "data/layouts"
BOSSES = [
    "c6_boss03", "c6_boss02", "boss_corrupted_beast", "c2_boss_iron_foreman",
    "c2_boss_slag_devourer", "c2_boss_hundred_arm_extractor", "c3_boss02",
    "c4_boss02", "c5_boss02", "c5_boss04",
]
NORMALS = [f"c6_normal{i:02d}" for i in range(1, 9)]
# 聚金地脉 6 堆的左上角（堆序 H0→H5）；每堆为 4×4 网格、格间距 3。
HEAP_ORIGINS = [(16, 10), (16, 62), (68, 10), (68, 62), (120, 30), (120, 74)]
HEAP_SIDE = 4
HEAP_SPACING = 3
MIN_HEAP_WORLD_DISTANCE = 858.0
MIN_HEAP_GRID_DISTANCE = 24.0


def write_json(path: Path, data: dict, compact: bool = False) -> None:
    """写入确定性 JSON；布局逐行较长，采用紧凑格式控制文件体积。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    kwargs = {"ensure_ascii": False, "separators": (",", ":")} if compact else {"ensure_ascii": False, "indent": 2}
    path.write_text(json.dumps(data, **kwargs) + "\n", encoding="utf-8")


def validate_and_layout(data: dict) -> dict:
    """验证所有固定格可走且四邻接连通；返回运行布局，避免入口或怪刷新在墙上。"""
    width, height = data["size"]["w"], data["size"]["h"]
    rows = ["".join("1" if 3 <= x < width - 3 and 3 <= y < height - 3 else "0" for x in range(width)) for y in range(height)]
    points = {edge["id"]: edge["cell"] for edge in data["exits"]}
    points["carterArrival"] = data["carterArrival"]
    for i, group in enumerate(data.get("spawnPoints", [])):
        for j, cell in enumerate(group["cells"]):
            points[f"normal{i:02d}_{j:02d}"] = cell
    for i, seat in enumerate(data.get("bossSpawns", [])):
        points[f"boss{i:03d}"] = seat["cell"]
    for name, (x, y) in points.items():
        assert 0 <= x < width and 0 <= y < height and rows[y][x] == "1", name
    start = tuple(data["exits"][0]["cell"])
    seen, queue = {start}, deque([start])
    while queue:
        x, y = queue.popleft()
        for near in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            nx, ny = near
            if 0 <= nx < width and 0 <= ny < height and rows[ny][nx] == "1" and near not in seen:
                seen.add(near)
                queue.append(near)
    assert len(seen) == sum(row.count("1") for row in rows)
    return {"id": data["id"], "layoutVersion": data["layoutVersion"],
            "grid_size": [width, height], "points": points, "walkable_rows": rows}


def base_map(map_id: str, name: str, width: int, height: int, gate: dict, exit_y: int) -> dict:
    """建立只可由回廊步行进入的地图；动态门槛与回廊解锁旗标分别管理。"""
    return {
        "id": map_id, "name": name, "size": {"w": width, "h": height},
        "layoutVersion": "2026-10-20-cycle-v1", "layoutPath": f"res://data/layouts/{map_id}.json",
        "recommendedLevel": gate["minLevel"], "safeZone": False,
        "kind": "spoke", "hubId": "c6_map00", "requiresUnlock": "campaign_complete",
        "entryGate": gate, "levelFromPlayer": {"enabled": True, "minLevel": gate["minLevel"]},
        "exits": [{"id": f"{map_id}_exit01", "label": "回无尽回廊", "cell": [6, exit_y],
                   "toMap": "c7_arena", "toEntrance": f"from_{map_id}"}],
        "entrances": {"from_c7_arena": [6, exit_y]}, "carterArrival": [8, exit_y],
        "bossSpawn": None, "npcs": [], "eliteCap": 0, "carterFares": {},
    }


def heap_cells(origin: tuple[int, int]) -> list[list[int]]:
    """一堆 = 4×4 网格、格间距 3；行优先返回 16 个格子（第 k 席 → (k//4, k%4) 行列）。"""
    bx, by = origin
    return [[bx + HEAP_SPACING * (k // HEAP_SIDE), by + HEAP_SPACING * (k % HEAP_SIDE)]
            for k in range(HEAP_SIDE * HEAP_SIDE)]


def heap_center(origin: tuple[int, int]) -> tuple[float, float]:
    """堆心 = 4×4 网格的几何中心（小数格坐标）。"""
    bx, by = origin
    return (bx + 4.5, by + 4.5)


def iso_world(col: float, row: float) -> tuple[float, float]:
    """与 scripts/systems/iso.gd::grid_to_world 一致（TILE_W 64、TILE_H 32）。"""
    return ((col - row) * 32.0, -(col + row) * 16.0)


def assert_heap_spacing() -> None:
    """固化堆约束：任意两堆心的世界像素距离 ≥ 858、网格欧氏距离 ≥ 24。"""
    centers = [heap_center(origin) for origin in HEAP_ORIGINS]
    worlds = [iso_world(*center) for center in centers]
    pairs = [(a, b) for a in range(len(centers)) for b in range(a + 1, len(centers))]
    min_world = min(math.dist(worlds[a], worlds[b]) for a, b in pairs)
    min_grid = min(math.dist(centers[a], centers[b]) for a, b in pairs)
    assert min_world >= MIN_HEAP_WORLD_DISTANCE, f"堆心世界距离过近：{min_world:.2f}px"
    assert min_grid >= MIN_HEAP_GRID_DISTANCE, f"堆心网格距离过近：{min_grid:.2f} 格"
    print(f"堆距自检：最小世界像素距离 {min_world:.2f}px（阈值 {MIN_HEAP_WORLD_DISTANCE:.0f}），"
          f"最小网格欧氏距离 {min_grid:.2f} 格（阈值 {MIN_HEAP_GRID_DISTANCE:.0f}）")


def build_gold() -> dict:
    """配置 96 个普通怪固定席位：6 堆 × 16 席，每个怪种在每堆占 2 席。"""
    data = base_map("c7_gold_field", "聚金地脉", 160, 90,
                    {"walkOnlyFrom": "c7_arena", "minLevel": 80}, 45)
    assert_heap_spacing()
    heaps = [heap_cells(origin) for origin in HEAP_ORIGINS]
    spawn_points = []
    for i, mid in enumerate(NORMALS):
        cells = []
        for heap in heaps:
            cells.append(heap[i * 2])
            cells.append(heap[i * 2 + 1])
        spawn_points.append({"monsterId": mid, "kind": "normal", "respawnTime": 15,
                             "count": 12, "cells": cells, "scaleStats": True,
                             "xpFromCurve": True, "xpCurveDivisor": 10, "xpMultiplier": 0.1,
                             "dropTableId": "DT_C7_Gold_Normal"})
    data.update({
        "spawnPoints": spawn_points, "normalCap": 32, "bossCap": 0,
        "desc": "80级开放的密集金币战场：96 席分为 6 堆，每堆 16 席；第六章普通怪复用外观，等级随玩家成长。",
    })
    return data


def build_boss() -> dict:
    """配置 100 个稳定 Boss 席位；每种 10 席，重生 600 秒。"""
    data = base_map("c7_boss_field", "百首禁域", 200, 120,
                    {"walkOnlyFrom": "c7_arena", "minLevel": 100,
                     "allEquipmentQuality": "legendary"}, 60)
    seats = []
    for i in range(100):
        column, row = i % 10, i // 10
        seats.append({"monsterId": BOSSES[(i * 7) % 10],
                      "cell": [20 + column * 18, 10 + row * 11],
                      "kind": "boss", "respawnTime": 600, "tombstone": True,
                      "scaleStats": True, "xpFromCurve": True,
                      "hpMultiplier": 2.0, "atkMultiplier": 1.5, "xpMultiplier": 0.25,
                      "dropTableId": "DT_C7_Boss_Field", "group": chr(ord("A") + row)})
    # 7 与 10 互素，十个外观在每一行各出现一次。
    data.update({"spawnPoints": [], "bossSpawns": seats, "normalCap": 0,
                 "bossCap": 18, "unclaimedLootCap": 2400, "preserveUnclaimedLoot": True,
                 "desc": "100级且全身紫装开放的百席循环首领战场。"})
    return data


def main() -> None:
    """重新生成两图与布局，并逐图验证席位和入口的掩码连通性。"""
    for data in (build_gold(), build_boss()):
        layout = validate_and_layout(data)
        write_json(CHAPTER / data["id"] / "map.json", data)
        write_json(LAYOUT_DIR / f"{data['id']}.json", layout, compact=True)
        print(data["id"], data["size"], "固定格", len(layout["points"]))


if __name__ == "__main__":
    main()
