#!/usr/bin/env python3
"""核对正式怪物动画制作矩阵与运行数据、表现档案和原资产清单。

用法：python3 tools/check_formal_monster_animation.py。只读，不改动运行数据或玩家存档。
矩阵的形体族来自概念稿人工分型；移动、攻击与首领事件以现有怪物配置为准。
"""

import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RECORD = ROOT / "docs/素材设计/制作记录/11-60级"
STATUSES = {"pending", "source_ready", "baked", "reviewed", "integrated"}
DIRECTIONS = ["s", "sw", "w", "nw", "n", "ne", "e", "se"]


def read_json(path: Path):
    """读取当前仓库的 JSON；缺失或格式错误直接终止，避免错认制作进度。"""
    return json.loads(path.read_text(encoding="utf-8"))


def expected_events(monster: dict) -> list[str]:
    """从现有首领技能配置或第二章固定招式读取视觉事件，不引入新玩法。"""
    fixed = {
        "c2_boss_iron_foreman": ["sweep", "phase_summon"],
        "c2_boss_slag_devourer": ["line", "blasts"],
        "c2_boss_hundred_arm_extractor": ["circle", "line", "phase_summon"],
    }
    if monster["id"] in fixed:
        return fixed[monster["id"]]
    skill = monster.get("bossSkill") or {}
    if monster["kind"] == "boss":
        return [skill["shape"]] + (["phase_b"] if skill.get("phaseB") else [])
    return []


def main() -> None:
    """逐 ID 校验制作矩阵、临时运行外观和独立正式状态，并输出真实数量。"""
    matrix = read_json(RECORD / "formal_animation_worklist.json")
    manifest = read_json(RECORD / "asset_manifest.json")
    assert matrix["directions"] == DIRECTIONS, "方向行顺序错误"
    families = set(matrix["rig_families"])
    assert len(families) == 7 and len(matrix["rows"]) == 79, "形体族或怪物数量错误"
    source = {}
    for chapter in range(2, 7):
        rows = read_json(ROOT / f"data/monsters/ch{chapter:02d}/monsters.json")
        source.update({row["id"]: (chapter, row) for row in rows})
    assert len(source) == 79, "运行怪物 ID 不是 79 个"
    recorded = {row["data_id"]: row for row in manifest["assets"] if row["type"] == "monster"}
    registered_packs = {row["id"] for row in read_json(ROOT / "data/monster_animation_packs.json")}
    assert set(recorded) == set(source), "资产清单与运行怪物 ID 不一致"
    ids = [row["id"] for row in matrix["rows"]]
    assert len(ids) == len(set(ids)) and set(ids) == set(source), "动画矩阵 ID 不全或重复"
    kinds = Counter()
    statuses = Counter()
    ranged = 0
    stationary = 0
    for row in matrix["rows"]:
        monster_id = row["id"]
        chapter, actual = source[monster_id]
        moves = float(actual["moveSpeed"]) > 0
        attack_kind = actual["attackRange"]["kind"]
        expected_states = ["idle"] + (["walk"] if moves else []) + ["attack", "hit", "death"]
        assert row["name"] == actual["name"] and row["chapter"] == chapter and row["kind"] == actual["kind"], f"{monster_id} 身份错误"
        assert row["rig_family"] in families, f"{monster_id} 未分型"
        assert row["moves"] == moves and row["attack_kind"] == attack_kind, f"{monster_id} 动作条件与玩法不一致"
        assert row["required_states"] == expected_states and row["boss_events"] == expected_events(actual), f"{monster_id} 状态或首领视觉事件不一致"
        status = row["formal_status"]
        assert status in STATUSES and recorded[monster_id].get("formal_animation") == status, f"{monster_id} 正式进度不一致"
        source_dir = ROOT / f"art_source/chapters/ch{chapter:02d}/monsters/{monster_id}/animation"
        if status != "pending":
            assert (source_dir / "rig.json").is_file(), f"{monster_id} 缺少可编辑分层源稿"
        if status in {"baked", "reviewed", "integrated"}:
            assert (source_dir / "animations_v1/animation.json").is_file(), f"{monster_id} 缺少烘焙元数据"
        appearance = read_json(ROOT / f"data/monster_appearances/{actual['appearanceId']}.json")
        if status == "integrated":
            assert appearance["renderer"] == "animation_pack" and appearance.get("assetKey") == actual["appearanceId"], f"{monster_id} 未切换正式包"
            assert monster_id in registered_packs, f"{monster_id} 未登记已审核正式包"
        elif recorded[monster_id].get("integration") == "directional_preview":
            assert appearance["renderer"] == "directional_preview", f"{monster_id} 的方向试玩稿登记错误"
            assert (ROOT / f"assets/sprites/monsters/{monster_id}/directional_preview_atlas.png").is_file(), f"{monster_id} 缺少方向试玩图集"
            assert recorded[monster_id].get("runtime_variant") == "eight_direction_three_state_preview", f"{monster_id} 的运行规格标记错误"
        else:
            assert appearance["renderer"] == "static_atlas", f"{monster_id} 未验收却提前切换外观"
        assert (ROOT / f"art_source/chapters/ch{chapter:02d}/monsters/{monster_id}/concept.png").is_file(), f"{monster_id} 概念稿丢失"
        kinds[actual["kind"]] += 1
        statuses[status] += 1
        ranged += attack_kind == "ranged"
        stationary += not moves
    assert kinds == {"normal": 41, "elite": 22, "boss": 16}, f"档次数量错误：{kinds}"
    assert ranged == 17 and stationary == 1, f"攻击与可动数量错误：远程 {ranged}，定点 {stationary}"
    print(f"正式动画矩阵通过：79 ID，{dict(kinds)}，远程 {ranged}，定点 {stationary}，正式状态 {dict(statuses)}")


if __name__ == "__main__":
    main()
