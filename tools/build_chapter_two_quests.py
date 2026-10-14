"""Install editable chapter-two quest templates and deterministic quest items."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
QUESTS = ROOT / "data/quests.json"
MISC = ROOT / "data/miscItems.json"


def quest(qid, name, giver, turn_in, kind, target, count, maps, prev, gold, xp,
          desc, item="", unlocks=(), source="", side=False, talk_on_accept=False):
    objective = {"kind": kind, "targetId": target, "count": count}
    if source:
        objective["sourceMonster"] = source
    reward = {"gold": gold, "xp": xp}
    if item:
        reward["item"] = item
        reward["requiredLevel"] = 10
        reward["quality"] = "uncommon" if item == "c2_apprentice_bracer" else "rare"
    if unlocks:
        reward["unlocks"] = list(unlocks)
    target_markup = {"kill": f"{{monster:{target}}}", "collect": f"{{item:{target}}}", "talk": f"{{npc:{target}}}"}[kind]
    action = {"kill": "击败", "collect": "找回", "talk": "与"}[kind]
    suffix = "交谈" if kind == "talk" else ""
    map_markup = f"{{map:{maps[0]}}}" if maps else ""
    tracker = f"前往 {map_markup} {action} {count if count > 1 else ''} {target_markup}{suffix}（{{current}}/{{count}}）。"
    turn_map = {"elder": "camp", "c2_shi_cen": "c2_pipe_slope"}.get(turn_in, "c2_well_town")
    result = {
        "id": qid, "name": name, "type": "side" if side else "main",
        "giver": giver, "turnIn": turn_in, "objective": objective,
        "reward": reward, "mapScope": maps, "prev": prev,
        "abandonable": side, "desc": desc,
        "trackerText": tracker,
        "turnInText": f"回到 {{map:{turn_map}}} 找 {{npc:{turn_in}}} 交任务吧。",
    }
    if talk_on_accept:
        result["talkOnAccept"] = True
    return result


def main():
    existing = [entry for entry in json.loads(QUESTS.read_text()) if not entry["id"].startswith("C2")]
    rows = [
        quest("C2Q01", "井还在呼吸", "elder", "c2_lu_heng", "talk", "c2_lu_heng", 1,
              ["c2_well_town"], "Q005", 200, 300, "长老请你去沉井镇了解供暖危机。"),
        quest("C2Q02", "修路的人", "c2_shi_cen", "c2_shi_cen", "kill", "c2_spirit_larva", 12,
              ["c2_pipe_slope"], "C2Q01", 250, 600, "清理断管坡的汲灵幼虫，让维修队通过。"),
        quest("C2Q03", "关闭的安全阀", "c2_shi_cen", "c2_lu_heng", "collect", "c2_pressure_plate", 4,
              ["c2_pipe_slope"], "C2Q02", 0, 900, "从断链守卫身上找回四枚调压片。", "c2_inspector_armor", source="c2_broken_guard"),
        quest("C2Q04", "不得停机", "c2_lu_heng", "c2_lu_heng", "kill", "c2_boss_iron_foreman", 1,
              ["c2_old_well"], "C2Q03", 500, 1600, "击败铁臂，夺回旧井的安全锁。"),
        quest("C2Q05", "名单上的空格", "c2_qi_yan", "c2_qi_yan", "collect", "c2_worker_badge", 5,
              ["c2_lower_works"], "C2Q04", 300, 900, "在工坊找回失踪工人的工牌。", source="c2_badge_wraith"),
        quest("C2Q06", "另一种炉火", "c2_xu_zhu", "c2_xu_zhu", "collect", "c2_heat_component", 3,
              ["c2_ember_furnace"], "C2Q05", 0, 1200, "到余烬炉房取回耐热组件，修复备用炉。", "c2_backup_blade", source="c2_copper_worm"),
        quest("C2Q07", "为一个夜晚留煤", "c2_mi_cang", "c2_mi_cang", "kill", "c2_ash_beast", 10,
              ["c2_ember_furnace"], "C2Q06", 300, 1000, "清理燃料区，为病房留下一夜炉火。"),
        quest("C2Q08", "火先留在人间", "c2_bai_zhi", "c2_lu_heng", "talk", "c2_lu_heng", 1,
              ["c2_well_town"], "C2Q07", 300, 600, "告诉陆衡备用炉已经就绪。", unlocks=["c2_backup_furnace"]),
        quest("C2Q09", "放开主管", "c2_lu_heng", "c2_lu_heng", "kill", "c2_broken_guard", 8,
              ["c2_well_core"], "C2Q08", 400, 1200, "进入井心，清理主管附近的断链守卫。"),
        quest("C2Q10", "最后的巡检", "c2_lu_heng", "c2_lu_heng", "kill", "c2_elite_spirit_guard", 1,
              ["c2_well_core"], "C2Q09", 400, 1400, "击败汲灵护卫，打开主机场地安全锁。", unlocks=["c2_core_access"]),
        quest("C2Q11", "百臂止息", "c2_lu_heng", "c2_lu_heng", "kill", "c2_boss_hundred_arm_extractor", 1,
              ["c2_well_core"], "C2Q10", 800, 3500, "击败百臂汲灵机，终止灵能抽取。", unlocks=["c2_machine_stopped"]),
        quest("C2Q12", "送往无雨之城", "c2_qi_yan", "c2_qi_yan", "talk", "c2_qi_yan", 1,
              ["c2_well_town"], "C2Q11", 500, 1200, "读祁言的账簿，记下无雨之城的新线索。", unlocks=["chapter3"], talk_on_accept=True),
        quest("C2S01", "半碗汤", "c2_miao_miao", "c2_miao_miao", "kill", "c2_copper_worm", 8,
              ["c2_pipe_slope"], "C2Q01", 150, 500, "清理近镇蠕虫，让汤棚重新开张。", side=True),
        quest("C2S02", "不要把我写成失踪", "c2_qi_yan", "c2_qi_yan", "collect", "c2_named_badge", 3,
              ["c2_lower_works"], "C2Q04", 200, 700, "找回三枚有姓名的工牌。", source="c2_badge_wraith", side=True),
        quest("C2S03", "师父的旧钳子", "c2_xu_zhu", "c2_xu_zhu", "kill", "c2_elite_broken_inspector", 1,
              ["c2_lower_works"], "C2Q05", 0, 800, "击败工坊巡检长，替许铸取回旧工具。", "c2_apprentice_bracer", side=True),
        quest("C2S04", "炉房里的第二颗心", "c2_bai_zhi", "c2_bai_zhi", "kill", "c2_elite_copper_matriarch", 1,
              ["c2_ember_furnace"], "C2Q06", 250, 800, "调查内炉前的铜壳母虫。", side=True),
        quest("C2S05", "吞下去的炉火", "c2_bai_zhi", "c2_bai_zhi", "kill", "c2_boss_slag_devourer", 1,
              ["c2_ember_furnace"], "C2S04", 0, 1800, "可选挑战：击败炉渣吞噬者。", "c2_slag_shield", side=True),
        quest("C2S06", "老车不走空路", "c2_lao_zhe", "c2_lao_zhe", "kill", "c2_elite_broken_inspector", 1,
              ["c2_pipe_slope"], "C2Q08", 300, 700, "替老辙打通重新运煤的路。", side=True),
    ]
    for row in rows:
        if row["id"] == "C2S01":
            row["reward"]["items"] = [{"itemId": "potion_hp_mid", "count": 2}]
    QUESTS.write_text(json.dumps(existing + rows, ensure_ascii=False, indent=2) + "\n")
    misc = [entry for entry in json.loads(MISC.read_text()) if not entry["id"].startswith("c2_")]
    misc.extend({"id": item_id, "name": name, "useType": "quest", "animation": "", "desc": "第二章任务袋物品，不占背包格。"}
                for item_id, name in [
                    ("c2_pressure_plate", "调压片"), ("c2_worker_badge", "旧工牌"),
                    ("c2_heat_component", "耐热组件"), ("c2_named_badge", "具名工牌")])
    MISC.write_text(json.dumps(misc, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
