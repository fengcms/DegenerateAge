"""按历史原画参考重建其余地图；正式营地白盒由 build_camp_whitebox.py 管理。"""

import json
from pathlib import Path
from map_catalog import load_maps, save_maps


ROOT = Path(__file__).resolve().parents[1]
REF_DIRS = (
    ROOT / "docs/游戏创意/第一章地图重设计示意图",
    ROOT / "docs/游戏创意/地图示意图",
)


def references():
    """读取历史十张地图的布局参考，供非营地地图重建使用。"""
    return {
        data["id"]: data
        for folder in REF_DIRS
        for path in folder.glob("*-布局参考.json")
        for data in [json.loads(path.read_text())]
    }


def npc(role, name, cell, npc_id="", shop_id=""):
    """把参考点转换为可装配的 NPC 规格。"""
    result = {"role": role, "npcName": name, "cell": cell}
    if role == "blacksmith":
        result["greeting"] = "炉火还亮着，带装备来看看吧。"
    if npc_id:
        result["npcId"] = npc_id
    if shop_id:
        result["shopId"] = shop_id
    return result


def first_chapter_npcs(map_id, old, points):
    """更新第一章非营地 NPC 格坐标；营地由白盒生成器负责。"""
    if map_id == "wild_trial":
        mapping = {"carter": "carter"}
    elif map_id == "ash_land":
        mapping = {"shop": "carter", "carter": "carter"}
    else:
        mapping = {"carter": "carter"}
    for entry in old["npcs"]:
        entry["cell"] = points[mapping[entry["role"]]]
        if map_id == "ash_land" and entry["role"] == "shop":
            entry["cell"] = [points["carter"][0] + 3, points["carter"][1]]


def chapter_two_npcs(map_id, points):
    """依据章节二参考点建立 NPC 列表，保留角色与商店 ID。"""
    if map_id == "c2_well_town":
        return [
            npc("quest", "陆衡", points["lu_heng"], "c2_lu_heng"),
            npc("shop", "白芷", points["bai_zhi"], "c2_bai_zhi", "c2_apothecary"),
            npc("blacksmith", "许铸", points["xu_zhu"], "c2_xu_zhu"),
            npc("warehouse", "米仓", points["mi_cang"], "c2_mi_cang"),
            npc("shop", "阿絮", points["a_xu"], "c2_a_xu", "c2_peddler"),
            npc("quest", "祁言", points["qi_yan"], "c2_qi_yan"),
            npc("quest", "苗苗", points["miao_miao"], "c2_miao_miao"),
            npc("carter", "老辙", points["carter"], "c2_lao_zhe"),
        ]
    out = [npc("carter", "驿站车夫", points["carter"])]
    if map_id == "c2_pipe_slope":
        out.append(npc("quest", "石岑", [points["carter"][0] + 4, points["carter"][1]], "c2_shi_cen"))
    return out


def main():
    """重建营地以外九张地图，保留现有营地白盒配置。"""
    refs = references()
    maps = load_maps(ROOT)
    assert len(refs) == 10 and [entry["id"] for entry in maps[:4]] == [
        "camp", "wild_trial", "ash_land", "corruption_source"]
    # 只重建第一、二章，保留后续章节地图配置及其索引顺序。
    later_maps = maps[10:]
    maps = maps[:4]
    for entry in maps:
        # 正式营地已迁至矩形白盒事实源，避免旧参考覆盖其入口、尺寸和 NPC。
        if entry["id"] == "camp":
            continue
        ref = refs[entry["id"]]
        points = {point["id"]: point["cell"] for point in ref["points"]}
        entry["size"] = {"w": ref["size"][0], "h": ref["size"][1]}
        entry["layoutVersion"] = ref["layoutVersion"]
        entry["layoutPath"] = f"res://data/layouts/{entry['id']}.json"
        entry["exits"] = ref["exits"]
        entry["entrances"] = ref["entrances"]
        entry["carterArrival"] = ref["carterArrival"]
        first_chapter_npcs(entry["id"], entry, points)
    ranges = {
        "c2_well_town": [11, 11], "c2_pipe_slope": [11, 13],
        "c2_old_well": [13, 15], "c2_lower_works": [15, 18],
        "c2_ember_furnace": [17, 19], "c2_well_core": [18, 20],
    }
    for map_id, (low, high) in ranges.items():
        ref = refs[map_id]
        points = {point["id"]: point["cell"] for point in ref["points"]}
        town = map_id == "c2_well_town"
        entry = {
            "id": map_id, "name": ref["name"],
            "size": {"w": ref["size"][0], "h": ref["size"][1]},
            "layoutVersion": ref["layoutVersion"],
            "layoutPath": f"res://data/layouts/{map_id}.json",
            "tierRange": [low, high], "recommendedLevel": low,
            "safeZone": town,
            "kind": "hub" if town else "spoke", "hubId": "c2_well_town",
            "requiresUnlock": "c2_backup_furnace" if map_id == "c2_well_core" else "chapter2",
            "exits": ref["exits"], "entrances": ref["entrances"],
            "carterArrival": ref["carterArrival"],
            "spawnPoints": [], "bossSpawn": None,
            "npcs": chapter_two_npcs(map_id, points),
        }
        if town:
            entry["safeArea"] = {"min": [0, 0], "max": [95, 53]}
            entry["hubLinks"] = ["camp"]
            entry["carterFare"] = {"spoke": 80, "hub": 200}
            entry["carterFares"] = {"camp": 200}
        maps.append(entry)
    save_maps(maps + later_maps, ROOT)


if __name__ == "__main__":
    main()
