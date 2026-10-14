"""Add four deterministic chapter-two story reward models to the three-axis rules."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "data/equipments.json"
MODELS = [
    ("c2_inspector_armor", "巡检护甲", "armor", "armor_starter.png", "rare",
     {"1": {"def": 4, "hp": 14}, "10": {"def": 10, "hp": 30}, "20": {"def": 18, "hp": 54}}),
    ("c2_backup_blade", "备用炉之刃", "weapon", "weapon_starter.png", "rare",
     {"1": {"atk": 6}, "10": {"atk": 15}, "20": {"atk": 25}}),
    ("c2_apprentice_bracer", "隔热学徒护腕", "bracer", "bracer_basic.png", "uncommon",
     {"1": {"def": 2, "hp": 5}, "10": {"def": 5, "hp": 12}, "20": {"def": 9, "hp": 22}}),
    ("c2_slag_shield", "炉渣护盾", "shield", "shield_basic.png", "rare",
     {"1": {"def": 5, "hp": 10}, "10": {"def": 12, "hp": 25}, "20": {"def": 20, "hp": 45}}),
]
DROP_MODELS = [
    ("c2_road_blade", "守路长刃", "weapon", "weapon_starter.png", {"atk": 17}),
    ("c2_copper_shield", "铜面护盾", "shield", "shield_basic.png", {"def": 10, "hp": 15}),
    ("c2_road_armor", "守路夹甲", "armor", "armor_starter.png", {"def": 9, "hp": 25}),
    ("c2_road_helmet", "巡路帽", "helmet", "helmet_cloth.png", {"def": 5}),
    ("c2_road_shoes", "山路靴", "shoes", "shoes_cloth.png", {"def": 4, "mp": 10}),
    ("c2_road_bracer", "守路腕甲", "bracer", "bracer_basic.png", {"def": 4}),
    ("c2_road_knee", "守路护膝", "knee", "knee_basic.png", {"def": 4}),
    ("c2_copper_bracelet", "铜环手镯", "bracelet", "bracelet_basic.png", {"atk": 4}),
    ("c2_road_ring", "巡路戒", "ring", "ring_basic.png", {"atk": 3, "mp": 8}),
    ("c2_warm_necklace", "暖石项链", "necklace", "necklace_basic.png", {"hp": 25}),
]


def main():
    items = [item for item in json.loads(PATH.read_text()) if not item["id"].startswith("c2_")]
    for item_id, name, slot, icon, quality, bases in MODELS:
        items.append({
            "id": item_id, "name": name, "slot": slot, "price": 300,
            "icon": "res://assets/sprites/equip/" + icon,
            "desc": "第二章固定任务奖励。属性由等级、品质和星级三轴计算。",
            "tierBases": bases, "defaultQuality": quality,
            "affixPool": ["atk", "def", "hp", "mp", "hpPercent", "mpPercent"],
            "lootable": False,
        })
    for item_id, name, slot, icon, base in DROP_MODELS:
        items.append({
            "id": item_id, "name": name, "slot": slot, "price": 160,
            "icon": "res://assets/sprites/equip/" + icon,
            "desc": "第二章常见制式，品质与星级由统一三轴规则生成。",
            "tierBases": {
                "1": {key: max(1, round(value * 0.45)) for key, value in base.items()},
                "10": base,
                "20": {key: max(1, round(value * 1.65)) for key, value in base.items()},
            },
            "defaultQuality": "common",
            "affixPool": ["atk", "def", "hp", "mp", "hpPercent", "mpPercent"],
        })
    PATH.write_text(json.dumps(items, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
