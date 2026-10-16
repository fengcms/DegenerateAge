"""Generate deterministic chapter-two encounter cells from approved zones."""

import json
import copy
from collections import defaultdict
from pathlib import Path
from map_catalog import load_maps, save_maps


ROOT = Path(__file__).resolve().parents[1]
MONSTERS = ROOT / "data/monsters.json"
TABLES = ROOT / "data/dropTables.json"
POOLS = ROOT / "data/lootPools.json"
MOUNTS = ROOT / "data/mounts.json"
REFS = ROOT / "docs/游戏创意/地图示意图"

NORMALS = {
    "c2_spirit_larva": ("汲灵幼虫", 11, 110, 17, 5, 3.8, "melee"),
    "c2_copper_worm": ("铜壳蠕虫", 12, 210, 15, 22, 1.9, "tank"),
    "c2_broken_guard": ("断链守卫", 13, 190, 20, 12, 2.2, "melee"),
    "c2_slag_leech": ("喷渣蛭", 14, 130, 22, 6, 2.1, "ranged"),
    "c2_badge_wraith": ("工牌游魂", 15, 180, 23, 8, 2.3, "ranged"),
    "c2_ash_beast": ("煤灰兽", 17, 240, 25, 11, 3.2, "melee"),
    "c2_spirit_attendant": ("汲灵侍虫", 17, 125, 16, 7, 2.6, "support"),
    "c2_purple_parasite": ("紫脉寄生体", 19, 260, 29, 13, 2.4, "melee"),
}
ELITES = {
    "c2_elite_copper_matriarch": ("铜壳母虫", 13, 1250, 28, 31, 1.8, "tank"),
    "c2_elite_broken_inspector": ("断链巡检长", 14, 1120, 31, 18, 2.2, "melee"),
    "c2_elite_gray_scribe": ("灰印书记", 17, 1050, 34, 12, 2.3, "ranged"),
    "c2_elite_spirit_guard": ("汲灵护卫", 16, 990, 37, 15, 3.6, "melee"),
    "c2_elite_ash_leader": ("煤灰头领", 18, 1280, 36, 17, 3.0, "melee"),
}
BOSSES = {
    "c2_boss_iron_foreman": ("镇井监工·铁臂", 15, 7800, 40, 24),
    "c2_boss_slag_devourer": ("炉渣吞噬者", 18, 10500, 48, 29),
    "c2_boss_hundred_arm_extractor": ("百臂汲灵机", 20, 15500, 55, 35),
}
COMPOSITION = {
    "c2_pipe_slope": {"c2_spirit_larva": 42, "c2_copper_worm": 21, "c2_broken_guard": 21},
    "c2_old_well": {"c2_spirit_larva": 30, "c2_copper_worm": 24, "c2_broken_guard": 24, "c2_slag_leech": 12},
    "c2_lower_works": {"c2_broken_guard": 40, "c2_badge_wraith": 32, "c2_slag_leech": 24, "c2_spirit_attendant": 16, "c2_ash_beast": 16},
    "c2_ember_furnace": {"c2_ash_beast": 24, "c2_copper_worm": 18, "c2_slag_leech": 12},
    "c2_well_core": {"c2_purple_parasite": 18, "c2_broken_guard": 12, "c2_spirit_attendant": 6},
}
ELITE_POINTS = {
    "c2_pipe_slope": {"elite_bug": "c2_elite_copper_matriarch", "elite_guard": "c2_elite_broken_inspector"},
    "c2_old_well": {"elite_bug": "c2_elite_copper_matriarch", "elite_guard": "c2_elite_broken_inspector", "elite_fast": "c2_elite_spirit_guard"},
    "c2_lower_works": {"elite_guard": "c2_elite_broken_inspector", "elite_scribe": "c2_elite_gray_scribe", "elite_beast": "c2_elite_ash_leader"},
    "c2_ember_furnace": {"elite_bug": "c2_elite_copper_matriarch"},
    "c2_well_core": {"elite_fast": "c2_elite_spirit_guard", "elite_beast": "c2_elite_ash_leader"},
}
BOSS_POINTS = {
    "c2_old_well": ("foreman", "c2_boss_iron_foreman"),
    "c2_ember_furnace": ("slag", "c2_boss_slag_devourer"),
    "c2_well_core": ("extractor", "c2_boss_hundred_arm_extractor"),
}


def template(monster_id, spec, kind):
    name, level, hp, attack, defense = spec[:5]
    speed = spec[5] if kind != "boss" else 1.6
    behavior = spec[6] if kind != "boss" else "melee"
    table = {"normal": "DT_C2_Normal", "elite": "DT_C2_Elite", "boss": "DT_C2_Boss"}[kind]
    result = {
        "id": monster_id, "name": name, "tier": 3, "level": level,
        "hpBase": hp, "mpBase": 0, "attack": attack, "defense": defense,
        "attackInterval": 1.5 if kind == "boss" else 1.35,
        "attackRange": {"kind": "ranged" if behavior == "ranged" else "melee", "range": 6.0 if behavior == "ranged" else 1.0},
        "moveSpeed": speed, "accuracy": 0, "dodge": 4, "resistType": "",
        "xpReward": 900 if kind == "boss" else 150 if kind == "elite" else 40,
        "goldReward": 0, "dropTableId": table, "kind": kind,
        "monsterType": behavior, "specialAttack": "", "bossSkill": None,
        "spawnWeight": 1.0, "desc": "第二章 %s；数值待实机校准。" % kind,
    }
    if kind == "elite":
        result["affixPool"] = ["hard", "fast", "frost", "rage"]
        result["affixCount"] = [1, 2]
    if monster_id == "c2_boss_hundred_arm_extractor":
        result["dropTableId"] = "DT_C2_Boss_Final"
    return result


def nearby_cells(layout, center, occupied, forbidden, count):
    width, height = layout["grid_size"]
    rows = layout["walkable_rows"]
    cx, cy = center
    candidates = []
    for dy in range(-18, 19):
        for dx in range(-18, 19):
            x, y = cx + dx, cy + dy
            if 3 <= x < width - 3 and 3 <= y < height - 3 and rows[y][x] == "1":
                candidates.append((dx * dx + dy * dy, abs(dx) + abs(dy), y, x))
    candidates.sort()
    chosen = []
    for _, _, y, x in candidates:
        if any((x - ax) ** 2 + (y - ay) ** 2 < 9 for ax, ay in occupied | forbidden):
            continue
        chosen.append([x, y])
        occupied.add((x, y))
        if len(chosen) == count:
            return chosen
    raise ValueError((layout["id"], center, count, len(chosen)))


def build_spawns(entry, ref):
    map_id = entry["id"]
    if map_id not in COMPOSITION:
        return
    layout = json.loads((ROOT / "data/layouts" / (map_id + ".json")).read_text())
    points = {point["id"]: point["cell"] for point in ref["points"]}
    forbidden = {tuple(cell) for cell in ref["entrances"].values()}
    forbidden.update(tuple(exit_entry["cell"]) for exit_entry in ref["exits"])
    forbidden.update(tuple(point["cell"]) for point in ref["points"])
    zones = ref["zones"]
    quota = [int(zone["normalCount"]) for zone in zones]
    allocations = [defaultdict(list) for _ in zones]
    occupied = set()
    zone_index = 0
    for monster_id, total in COMPOSITION[map_id].items():
        for _ in range(total):
            for attempt in range(len(zones)):
                candidate = (zone_index + attempt) % len(zones)
                if quota[candidate] > 0:
                    break
            else:
                raise ValueError("zone quotas exhausted")
            quota[candidate] -= 1
            allocations[candidate][monster_id].append(None)
            zone_index = (candidate + 1) % len(zones)
    assert sum(quota) == 0
    specs = []
    for zone, alloc in zip(zones, allocations):
        all_cells = nearby_cells(layout, zone["center"], occupied, forbidden, sum(map(len, alloc.values())))
        offset = 0
        for monster_id, items in alloc.items():
            cells = all_cells[offset:offset + len(items)]
            offset += len(items)
            specs.append({"monsterId": monster_id, "level": max(entry["tierRange"][0], NORMALS[monster_id][1]),
                          "respawnTime": 15, "count": len(cells), "cells": cells, "zone": zone["id"]})
            if map_id == "c2_well_core":
                specs[-1]["dropTableId"] = "DT_C2_Core_Normal"
    for point_id, monster_id in ELITE_POINTS[map_id].items():
        specs.append({"monsterId": monster_id, "level": max(entry["tierRange"][0], min(entry["tierRange"][1], ELITES[monster_id][1])),
                      "respawnTime": 120, "count": 1, "cell": points[point_id], "kind": "elite"})
        if map_id == "c2_well_core":
            specs[-1]["dropTableId"] = "DT_C2_Core_Elite"
    entry["spawnPoints"] = specs
    if map_id in BOSS_POINTS:
        point_id, monster_id = BOSS_POINTS[map_id]
        entry["bossSpawn"] = {"monsterId": monster_id, "level": BOSSES[monster_id][1],
                              "respawnTime": 300 if map_id != "c2_well_core" else 600,
                              "count": 1, "cell": points[point_id], "kind": "boss", "tombstone": True}
        if map_id == "c2_well_core":
            entry["bossSpawn"]["requiresUnlock"] = "c2_core_access"
            entry["bossSpawn"]["dropTableId"] = "DT_C2_Boss_Final"
    assert sum(s["count"] for s in specs if s.get("kind") != "elite") == sum(COMPOSITION[map_id].values())


def build_tables(existing):
    common = [
        {"kind": "coin", "chance": 1.0, "goldRange": [20, 36]},
        {"kind": "potion", "chance": 0.14, "itemId": "potion_hp_mid"},
        {"kind": "potion", "chance": 0.12, "itemId": "potion_mp_mid"},
        {"kind": "equip", "chance": 0.18, "levelRange": [11, 19], "requiredLevel": 10,
         "templatePool": "c2_normal", "qualityWeight": {"common": 55, "uncommon": 30, "rare": 13, "epic": 2}},
    ]
    elite = [
        {"kind": "coin", "chance": 1.0, "goldRange": [90, 150]},
        {"kind": "equip", "chance": 1.0, "countRange": [2, 3], "levelRange": [13, 19], "requiredLevel": 10,
         "templatePool": "c2_normal", "qualityWeight": {"common": 65, "uncommon": 35}},
        {"kind": "equip", "chance": 1.0, "countRange": [1, 1], "levelRange": [13, 19], "requiredLevel": 10,
         "templatePool": "c2_normal", "qualityWeight": {"uncommon": 70, "rare": 27, "epic": 3}},
        {"kind": "potion", "chance": 1.0, "itemId": "potion_hp_mid"},
        {"kind": "potion", "chance": 0.5, "itemId": "potion_mp_mid"},
    ]
    boss = [
        {"kind": "coin", "chance": 1.0, "goldRange": [800, 1100]},
        {"kind": "equip", "chance": 1.0, "countRange": [5, 8], "levelRange": [15, 20], "requiredLevel": 10,
         "templatePool": "c2_normal", "qualityWeight": {"common": 70, "uncommon": 30}},
        {"kind": "equip", "chance": 1.0, "countRange": [2, 2], "levelRange": [15, 20], "requiredLevel": 10,
         "templatePool": "c2_normal", "qualityWeight": {"rare": 75, "epic": 25}},
        {"kind": "equip", "chance": 0.05, "countRange": [1, 1], "levelRange": [15, 20], "requiredLevel": 10,
         "templatePool": "c2_legendary", "qualityWeight": {"legendary": 100}},
        {"kind": "potion", "chance": 1.0, "itemId": "potion_hp_large", "count": 2},
        {"kind": "potion", "chance": 1.0, "itemId": "potion_mp_large", "count": 2},
    ]
    existing.extend([
        {"id": "DT_C2_Normal", "desc": "第二章普通怪；三轴 Lv10 档。", "entries": common},
        {"id": "DT_C2_Elite", "desc": "第二章精英，含优秀以上保底。", "entries": elite},
        {"id": "DT_C2_Boss", "desc": "第二章 Boss，传说是独立追加品质槽。", "entries": boss},
    ])
    for table_id, source in (("DT_C2_Core_Normal", common), ("DT_C2_Core_Elite", elite),
                             ("DT_C2_Boss_Final", boss)):
        entries = copy.deepcopy(source)
        for item in entries:
            if item["kind"] == "equip":
                item["requiredLevel"] = 20
                item["levelRange"] = [20, 20]
        if table_id == "DT_C2_Boss_Final":
            entries.append({"kind": "mount", "chance": 0.03, "itemId": "mount_furnace_beast"})
        existing.append({"id": table_id, "desc": "第二章井心 Lv20 三轴掉落。", "entries": entries})


def build_pools(existing):
    existing = [pool for pool in existing if not pool["id"].startswith("c2_")]
    ids = [
        "c2_road_blade", "c2_copper_shield", "c2_road_armor", "c2_road_helmet",
        "c2_road_shoes", "c2_road_bracer", "c2_road_knee", "c2_copper_bracelet",
        "c2_road_ring", "c2_warm_necklace",
    ]
    existing.extend([
        {"id": "c2_normal", "desc": "第二章普通装备型号；品质独立抽取。", "includeIds": ids},
        {"id": "c2_legendary", "desc": "第二章独立传说追加槽，仍使用本章型号。", "includeIds": ids},
    ])
    return existing


def build_mounts(existing):
    existing = [mount for mount in existing if mount["id"] != "mount_furnace_beast"]
    existing.append({
        "id": "mount_furnace_beast", "name": "驮炉兽", "speedBonus": 0.3,
        "dropBossId": "c2_boss_hundred_arm_extractor", "levelReq": 20,
        "icon": "res://assets/sprites/mounts/corrupted_wing.svg",
        "desc": "井心残留的运炉兽。达到20级可骑乘，移动速度提高30%。",
    })
    return existing


def main():
    maps = load_maps(ROOT)
    monsters = [m for m in json.loads(MONSTERS.read_text()) if not m["id"].startswith("c2_")]
    tables = [t for t in json.loads(TABLES.read_text()) if not t["id"].startswith("DT_C2_")]
    refs = {d["id"]: d for path in REFS.glob("*-布局参考.json") for d in [json.loads(path.read_text())]}
    for kind, group in (("normal", NORMALS), ("elite", ELITES), ("boss", BOSSES)):
        monsters.extend(template(monster_id, spec, kind) for monster_id, spec in group.items())
    for entry in maps:
        if entry["id"] in refs:
            build_spawns(entry, refs[entry["id"]])
    build_tables(tables)
    save_maps(maps, ROOT)
    MONSTERS.write_text(json.dumps(monsters, ensure_ascii=False, indent=2) + "\n")
    TABLES.write_text(json.dumps(tables, ensure_ascii=False, indent=2) + "\n")
    POOLS.write_text(json.dumps(build_pools(json.loads(POOLS.read_text())), ensure_ascii=False, indent=2) + "\n")
    MOUNTS.write_text(json.dumps(build_mounts(json.loads(MOUNTS.read_text())), ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
