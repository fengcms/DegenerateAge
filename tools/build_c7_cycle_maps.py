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
# 工程 83：聚金地脉 8 个怪种全部改成**近战**。
# 原 `c6_normal03 失序刻印偶` / `c6_normal06 断誓游魂` 是远程（射程 6 格 = 384px），
# 站在营里会被隔着半个战场射击，战士必须逐个追 —— 与「站桩刷」的产品定位冲突。
# 换成第五章两种**移速 3.1 的快速近战**（主动贴上来，不用等）：
#   c5_normal05 紫鳞潜猎者（原 index 2）/ c5_normal08 折翼掠兽（原 index 5）。
# 🔴 席位下标保持不变 ⇒ 每营的格位布局、`map.json` 其余 6 组逐字不动。
GOLD_NORMALS = [
    "c6_normal01", "c6_normal02", "c5_normal05", "c6_normal04",
    "c6_normal05", "c5_normal08", "c6_normal07", "c6_normal08",
]
# 换怪后仍必须满足的硬条件（换错就 assert 而不是静默出一张「远程刷图」）。
GOLD_FORBIDDEN_KINDS = ("ranged",)
# 工程 82：聚金地脉从「160×90 全图散布 6 堆」收成「64×48 单战场 6 营」。
# 营心格坐标 = CLUSTER_ORIGIN + 列步 (7,-7) × i + 行步 (-8,-8) × m（i∈0..2 列，m∈0..1 行）。
# 等距换算：列距 448 px、行距 256 px；营内 4×4、格间距 2。
CLUSTER_ORIGIN = (35, 29)
CLUSTER_COL_STEP = (7, -7)
CLUSTER_ROW_STEP = (-8, -8)
HEAP_SIDE = 4
HEAP_SPACING = 2
GOLD_SIZE = (64, 48)
GOLD_EXIT_Y = 24
# 工程 91：孤王绝域 —— 40×30 的小图，全场只有一席 Boss。
# 🔑 重生 1800 秒（半小时）是**产品定位**，不是配错：这张图不为「刷」，为「一次硬仗 + 一次爆爽」。
#    想让它变成刷图就改这个数字，但先读 docs/工程文档/91 §Q4。
SOLO_SIZE = (40, 30)
SOLO_EXIT_Y = 15
SOLO_BOSS = "boss_corrupted_beast"
SOLO_BOSS_CELL = [20, 15]
SOLO_RESPAWN = 1800
# 装备等级在击杀目标等级上 +10（= 比玩家高 10 级）由掉落表的 `levelOffset` 承担，不在这里配。
# 🔑 站桩判据：任意席位到战场中心的等距世界距离必须落在一个站位点的激活圈内。
# `MonsterSpawner.ACTIVE_DISTANCE` = 760 px，留 60 px 余量（约 1.7 格站位误差）。
MAX_SEAT_WORLD_DISTANCE = 700.0
# 席位两两最小世界距离（普通怪半径 13 px ⇒ 26 px 才不重叠，取 40 px 留余量）。
MIN_SEAT_WORLD_DISTANCE = 40.0
# 工程 82 方案 D：打金图普通怪单次命中伤害上限（占目标最大生命比例）。
GOLD_DAMAGE_CAP_PCT = 0.5
# 工程 82 方案 F：金脉守卫 —— 血 ×6 / 攻 ×1.5 / 金币 ×4，共 2 种 × 12 席 = 24 席。
# 🔴 这是**刻意的净亏配比**（单位时间金币 ≈ ×0.67）：守卫定位是「掉落更好、值得打一会儿」，
#    不是「刷钱更快」。下一个人按「收益应该更高」去改倍率，就把产品定位改掉了（R-10）。
GUARD_MONSTERS = ("c6_normal02", "c6_normal07")


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


def cluster_centers() -> list[tuple[int, int]]:
    """6 个营心：3 列 × 2 行，沿等距斜向排布，使整片战场在屏幕上呈矩形而不是菱形。"""
    cx, cy = CLUSTER_ORIGIN
    out = []
    for i in range(3):
        for m in range(2):
            out.append((cx + CLUSTER_COL_STEP[0] * i + CLUSTER_ROW_STEP[0] * m,
                        cy + CLUSTER_COL_STEP[1] * i + CLUSTER_ROW_STEP[1] * m))
    return out


def heap_cells(center: tuple[int, int]) -> list[list[int]]:
    """一营 = 4×4 网格、格间距 2，**以营心为中心对称**；行优先返回 16 格（第 k 席 → (k//4, k%4)）。"""
    cx, cy = center
    half = HEAP_SPACING * (HEAP_SIDE - 1) // 2
    return [[cx - half + HEAP_SPACING * (k // HEAP_SIDE), cy - half + HEAP_SPACING * (k % HEAP_SIDE)]
            for k in range(HEAP_SIDE * HEAP_SIDE)]


def field_center(centers: list[tuple[int, int]]) -> tuple[float, float]:
    """战场中心 = 6 个营心的算术平均（唯一自然的「站桩点」）。"""
    return (sum(c[0] for c in centers) / len(centers), sum(c[1] for c in centers) / len(centers))


def iso_world(col: float, row: float) -> tuple[float, float]:
    """与 scripts/systems/iso.gd::grid_to_world 一致（TILE_W 64、TILE_H 32）。"""
    return ((col - row) * 32.0, -(col + row) * 16.0)


def assert_seats_coverable(centers: list[tuple[int, int]],
                           heaps: list[list[list[int]]]) -> None:
    """固化「站桩即可全激活」：所有席位到战场中心的距离在激活圈内，且互不重叠。

    🔴 旧断言（`MIN_HEAP_WORLD_DISTANCE 858`）方向正好反了 —— 它保证「一次只激活一堆」，
    正是玩家必须跑来跑去的根因（工程 82 §2）。判据必须换成**单点覆盖**。
    """
    seats = [cell for heap in heaps for cell in heap]
    assert len(seats) == len({tuple(cell) for cell in seats}), "席位出现重复格"
    center_world = iso_world(*field_center(centers))
    far = max(math.dist(iso_world(*cell), center_world) for cell in seats)
    assert far <= MAX_SEAT_WORLD_DISTANCE, \
        f"有席位超出激活圈：最远 {far:.2f}px > 阈值 {MAX_SEAT_WORLD_DISTANCE:.0f}px（玩家仍需跑图）"
    worlds = [iso_world(*cell) for cell in seats]
    min_pair = min(math.dist(worlds[a], worlds[b])
                   for a in range(len(worlds)) for b in range(a + 1, len(worlds)))
    assert min_pair >= MIN_SEAT_WORLD_DISTANCE, \
        f"席位过密会互相挤：最小世界距离 {min_pair:.2f}px < 阈值 {MIN_SEAT_WORLD_DISTANCE:.0f}px"
    print(f"站桩自检：{len(seats)} 席，最远席距战场中心 {far:.2f}px"
          f"（阈值 {MAX_SEAT_WORLD_DISTANCE:.0f}），最小席距 {min_pair:.2f}px")


def load_monster_templates() -> dict[str, dict]:
    """读取全部章节的怪物模板（生成器做只读校验用；数据本身即判据）。"""
    out: dict[str, dict] = {}
    for path in sorted((ROOT / "data/monsters").glob("ch*/monsters.json")):
        for row in json.loads(path.read_text(encoding="utf-8")):
            out[str(row["id"])] = row
    return out


def assert_gold_normals_melee() -> None:
    """固化「打金图全近战」：任何远程怪混进来都直接 assert，而不是静默出一张刷不动的图。

    🔴 工程 83 的起因就是这里漏了判据：8 个怪种里混了 2 个 `attackRange.kind = ranged`
    （射程 6 格），玩家站在营里被隔着半个战场点名，必须逐个追。判据放在**生成器**
    这一侧，是为了让「换怪」这个动作本身不可能再换出远程；运行侧的看守在
    `EndgameCycleMapTest`（读 `map.json` 断言，防手改产物）。
    """
    templates = load_monster_templates()
    for mid in GOLD_NORMALS:
        tpl = templates.get(mid)
        assert tpl is not None, f"聚金地脉引用了未定义怪物 {mid}"
        assert str(tpl.get("kind", "")) == "normal", f"聚金地脉的 {mid} 不是普通怪"
        kind = str((tpl.get("attackRange") or {}).get("kind", "melee"))
        assert kind not in GOLD_FORBIDDEN_KINDS, \
            f"聚金地脉的 {mid}（{tpl.get('name', '')}）是远程怪 attackRange.kind={kind} —— 打金图必须全近战"
    print(f"近战自检：{len(GOLD_NORMALS)} 个怪种全部 melee（{', '.join(GOLD_NORMALS)}）")


def build_gold() -> dict:
    """配置 96 个普通怪固定席位：6 营 × 16 席，每个怪种在每营占 2 席。

    8 个怪种**全部近战**（工程 83）；其中 2 种怪为**金脉守卫**（24 席）：血 ×6 / 攻 ×1.5 /
    金币 ×4，其余 6 种 72 席保持割草手感。
    """
    assert_gold_normals_melee()
    data = base_map("c7_gold_field", "聚金地脉", GOLD_SIZE[0], GOLD_SIZE[1],
                    {"walkOnlyFrom": "c7_arena", "minLevel": 80}, GOLD_EXIT_Y)
    centers = cluster_centers()
    heaps = [heap_cells(center) for center in centers]
    assert_seats_coverable(centers, heaps)
    spawn_points = []
    for i, mid in enumerate(GOLD_NORMALS):
        cells = []
        for heap in heaps:
            cells.append(heap[i * 2])
            cells.append(heap[i * 2 + 1])
        spec = {"monsterId": mid, "kind": "normal", "respawnTime": 15,
                "count": 12, "cells": cells, "scaleStats": True,
                "xpFromCurve": True, "xpCurveDivisor": 10, "xpMultiplier": 0.1,
                "dropTableId": "DT_C7_Gold_Normal"}
        if mid in GUARD_MONSTERS:
            spec.update({"hpMultiplier": 6.0, "atkMultiplier": 1.5,
                         "dropTableId": "DT_C7_Gold_Guard"})
        spawn_points.append(spec)
    data.update({
        "spawnPoints": spawn_points, "normalCap": 32, "bossCap": 0,
        "damageCapPct": GOLD_DAMAGE_CAP_PCT,
        "desc": "80级开放的密集金币战场：96 席收在 6 营（3列×2行）内，全部落在一个站位点的激活圈里，"
                "站住即可连续刷；8 种普通怪全部近战（无远程），其中 2 种为金脉守卫（血厚、金币四倍）。",
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


def build_solo() -> dict:
    """孤王绝域：40×30、单席 Boss、重生 1800 秒、血 ×20、经验 ×5。

    与另两图的三处刻意差异（改之前先读工程 91）：
    1. `bossCap 1`：场上只有一只，没有轮转替班 ⇒ 重生时间直接决定出产节奏；
    2. `hpMultiplier 20.0`：**不加 `atkMultiplier`** —— 100 级满装防御 13,985，
       Boss 攻击 420×S(40)=3,159 根本破不了防，加倍也只走保底 60，等于白配；
    3. `unclaimedLootCap 600` + `preserveUnclaimedLoot`：一只爆 ~85 件装备，
       背包 40 格必然捡不完，剩下的必须留在地上不许 FIFO 淘汰。
    """
    data = base_map("c7_solo_boss", "孤王绝域", SOLO_SIZE[0], SOLO_SIZE[1],
                    {"walkOnlyFrom": "c7_arena", "minLevel": 100,
                     "allEquipmentQuality": "legendary"}, SOLO_EXIT_Y)
    data.update({
        "bossSpawns": [{
            "monsterId": SOLO_BOSS, "cell": SOLO_BOSS_CELL, "kind": "boss",
            "respawnTime": SOLO_RESPAWN, "tombstone": True, "scaleStats": True,
            "xpFromCurve": True, "hpMultiplier": 20.0, "xpMultiplier": 5.0,
            "dropTableId": "DT_C7_Solo_Boss", "group": "A",
        }],
        "spawnPoints": [], "normalCap": 0, "eliteCap": 0, "bossCap": 1,
        "unclaimedLootCap": 600, "preserveUnclaimedLoot": True,
        "desc": "100级且全身紫装开放的单王绝域：一只、半小时一遇、十倍掉落、比玩家高十级。",
    })
    return data


def main() -> None:
    """重新生成三图与布局，并逐图验证席位和入口的掩码连通性。"""
    for data in (build_gold(), build_boss(), build_solo()):
        layout = validate_and_layout(data)
        write_json(CHAPTER / data["id"] / "map.json", data)
        write_json(LAYOUT_DIR / f"{data['id']}.json", layout, compact=True)
        print(data["id"], data["size"], "固定格", len(layout["points"]))


if __name__ == "__main__":
    main()
