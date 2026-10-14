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
    PATH.write_text(json.dumps(items, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
