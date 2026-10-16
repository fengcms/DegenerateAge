"""Complete chapter-two modified models and boss-specific legendary pools.

The script is idempotent so balance changes to the base models can be propagated.
It only updates chapter-two entries in the four gameplay data tables.
"""

import copy
import json
from pathlib import Path
from map_catalog import load_maps, save_maps
from monster_catalog import load_chapter, save_chapter


ROOT = Path(__file__).resolve().parents[1]


def read(name):
    return json.loads((ROOT / "data" / name).read_text())


def write(name, rows):
    (ROOT / "data" / name).write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n")


def upsert(rows, entry):
    for index, existing in enumerate(rows):
        if existing["id"] == entry["id"]:
            rows[index] = entry
            return
    rows.append(entry)


BASE_IDS = [
    "c2_road_blade", "c2_copper_shield", "c2_road_armor", "c2_road_helmet",
    "c2_road_shoes", "c2_road_bracer", "c2_road_knee", "c2_copper_bracelet",
    "c2_road_ring", "c2_warm_necklace",
]
MODIFIED_NAMES = [
    "淬炉长刃", "铆铜重盾", "耐热护甲", "巡炉头盔", "隔热战靴",
    "导灵护腕", "锻纹护膝", "蓄能手镯", "锻铜戒指", "余烬项链",
]
RELICS = [
    ("c2_foreman_gauntlet", "铁臂统领的臂刃", "c2_road_blade"),
    ("c2_devourer_heart", "炉渣吞噬者之心", "c2_warm_necklace"),
    ("c2_extractor_eye", "百臂汲灵主机之眼", "c2_road_ring"),
]


def strengthen(template, new_id, name, multiplier, quality):
    result = copy.deepcopy(template)
    result["id"] = new_id
    result["name"] = name
    result["price"] = round(int(template["price"]) * multiplier)
    result["desc"] = "第二章改装型号，等级、品质和星级按统一三轴规则计算。" if quality == "common" else "第二章首领专属传说型号，仅在对应首领追加槽中产出。"
    result["defaultQuality"] = quality
    result["tierBases"] = {
        level: {stat: max(1, round(value * multiplier)) for stat, value in base.items()}
        for level, base in template["tierBases"].items()
    }
    return result


def main():
    equipment = read("equipments.json")
    original = {entry["id"]: entry for entry in equipment}
    modified_ids = []
    for base_id, name in zip(BASE_IDS, MODIFIED_NAMES):
        new_id = base_id + "_modified"
        upsert(equipment, strengthen(original[base_id], new_id, name, 1.2, "common"))
        modified_ids.append(new_id)
    for new_id, name, base_id in RELICS:
        upsert(equipment, strengthen(original[base_id], new_id, name, 1.4, "legendary"))
    write("equipments.json", equipment)

    pools = read("lootPools.json")
    upsert(pools, {"id": "c2_modified", "desc": "工坊、炉房及井心的十种改装型号。", "includeIds": modified_ids})
    for suffix, relic in zip(("iron", "slag", "final"), RELICS):
        upsert(pools, {"id": "c2_legendary_" + suffix, "desc": "对应首领的独立传说追加槽。", "includeIds": [relic[0]]})
    write("lootPools.json", pools)

    drops = read("dropTables.json")
    original_drops = {entry["id"]: entry for entry in drops}
    for source, new_id in (("DT_C2_Normal", "DT_C2_Industrial_Normal"),
                           ("DT_C2_Elite", "DT_C2_Industrial_Elite")):
        table = copy.deepcopy(original_drops[source])
        table["id"] = new_id
        table["desc"] = "第二章工坊及炉房改装型号；其余金币和药品概率沿用同类怪。"
        for entry in table["entries"]:
            if entry["kind"] == "equip":
                entry["templatePool"] = "c2_modified"
        upsert(drops, table)
    for table in drops:
        if table["id"] in ("DT_C2_Core_Normal", "DT_C2_Core_Elite"):
            for entry in table["entries"]:
                if entry["kind"] == "equip":
                    entry["templatePool"] = "c2_modified"
        if table["id"] in ("DT_C2_Boss", "DT_C2_Boss_Final"):
            for entry in table["entries"]:
                if entry["kind"] == "equip" and entry.get("qualityWeight") == {"legendary": 100}:
                    entry["templatePool"] = "c2_legendary_iron" if table["id"] == "DT_C2_Boss" else "c2_legendary_final"
    slag = copy.deepcopy(next(table for table in drops if table["id"] == "DT_C2_Boss"))
    slag["id"] = "DT_C2_Boss_Slag"
    slag["desc"] = "炉渣吞噬者专属池，传说追加槽只掉吞噬者之心。"
    for entry in slag["entries"]:
        if entry["kind"] == "equip":
            entry["templatePool"] = "c2_legendary_slag" if entry.get("qualityWeight") == {"legendary": 100} else "c2_modified"
    upsert(drops, slag)
    write("dropTables.json", drops)

    monsters = load_chapter("ch02")
    for monster in monsters:
        if monster["id"] == "c2_boss_slag_devourer":
            monster["dropTableId"] = "DT_C2_Boss_Slag"
    save_chapter("ch02", monsters)

    maps = load_maps(ROOT)
    for map_data in maps:
        map_id = map_data["id"]
        if map_id not in ("c2_lower_works", "c2_ember_furnace"):
            continue
        for point in map_data["spawnPoints"]:
            point["dropTableId"] = "DT_C2_Industrial_Elite" if point.get("kind") == "elite" else "DT_C2_Industrial_Normal"
        if map_id == "c2_ember_furnace":
            map_data["bossSpawn"]["dropTableId"] = "DT_C2_Boss_Slag"
    save_maps(maps, ROOT)


if __name__ == "__main__":
    main()
