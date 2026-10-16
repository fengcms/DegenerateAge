#!/usr/bin/env python3
"""从章节运行数据和已确认的美术梳理文档生成 11—60 级资产清单。

仅负责冻结 ID、造型主体与预期路径，不生成图片、不修改游戏数据。
执行 `python3 tools/build_chapter_art_manifest.py` 写入制作记录；`--check` 只核对现有清单。
"""

import argparse
import json
import re
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/游戏创意/21-60级内容规划/93-21-60级新增装备物品怪物梳理与美术提示词.md"
OUTPUT = ROOT / "docs/素材设计/制作记录/11-60级/asset_manifest.json"
CHAPTER_PALETTES = {
    2: "旧铜、铆钉铁、布革、炉灰；少量紫寄生",
    3: "渠铜、赭石、白布、盐痕",
    4: "深绿藤衬、灰白测量石、褪红信旗",
    5: "关卫铁、灰石、褪红军旗、局部紫潮",
    6: "灰白旧石、暖金分流、紫黑侵入",
}
KIND_NAMES = {"normal": "普通", "elite": "精英", "boss": "Boss"}


def read_json(path: Path) -> list[dict]:
    """读取仓库内数组格式的运行数据，失败时直接报错以免生成缺项清单。"""
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError(f"不是数组: {path}")
    return data


def table_rows(section: str, columns: int) -> list[list[str]]:
    """提取 Markdown 表格的数据行；只供当前已确认的 93 号梳理文档使用。"""
    result = []
    for line in section.splitlines():
        if not line.startswith("|"):
            continue
        parts = [part.strip() for part in line.strip().strip("|").split("|")]
        if len(parts) == columns and not all(re.fullmatch(r":?-+:?", part) for part in parts):
            result.append(parts)
    return result


def source_details() -> tuple[dict[str, str], dict[str, str], dict[str, str]]:
    """按中文名读取装备主体、任务锚点和怪物档次；名称仅用于核对，运行主键仍是 ID。"""
    source = SOURCE.read_text(encoding="utf-8")
    equip_section = source.split("## 2. 装备表：", 1)[1].split("## 3. 怪物与物品清单", 1)[0]
    monster_section = source.split("### 3.1 新增怪物", 1)[1].split("### 3.2 新增物品", 1)[0]
    item_section = source.split("### 3.2 新增物品", 1)[1].split("## 4. 装备图标", 1)[0]
    equipment = {row[0]: row[3] for row in table_rows(equip_section, 4) if row[1].isdigit()}
    monsters = {row[0]: row[1] for row in table_rows(monster_section, 4) if row[2].isdigit()}
    items = {row[0]: row[2] for row in table_rows(item_section, 3) if row[1].endswith("章") and row[0] != "名称"}
    if (len(equipment), len(items), len(monsters)) != (50, 21, 79):
        raise ValueError(f"93 号文档数量异常: {len(equipment)}, {len(items)}, {len(monsters)}")
    return equipment, items, monsters


def make_manifest() -> dict:
    """用真实数据 ID 建立制作队列，并对照文档名称与档次，防止静默错配。"""
    equipment_details, item_details, monster_details = source_details()
    rows = []
    for chapter in range(2, 7):
        prefix = f"c{chapter}_"
        chapter_dir = f"ch{chapter:02d}"
        palette = CHAPTER_PALETTES[chapter]
        for entry in read_json(ROOT / "data/equipments.json"):
            if not entry["id"].startswith(prefix):
                continue
            name = entry["name"]
            if name not in equipment_details:
                raise ValueError(f"装备未对应造型主体: {entry['id']} {name}")
            rows.append({
                "data_id": entry["id"], "chapter": chapter, "type": "equipment",
                "name": name, "tier": entry["slot"], "level": entry["requiredLevel"],
                "visual_brief": equipment_details[name], "palette": palette,
                "source_data": "data/equipments.json",
                "source_art": f"art_source/chapters/{chapter_dir}/equip/{entry['id']}/",
                "runtime_art": f"assets/sprites/equip/{entry['id']}.png",
                "status": "planned", "integration": "pending",
            })
        for entry in read_json(ROOT / "data/miscItems.json"):
            if not entry["id"].startswith(prefix):
                continue
            name = entry["name"]
            if name not in item_details:
                raise ValueError(f"任务物未对应任务锚点: {entry['id']} {name}")
            rows.append({
                "data_id": entry["id"], "chapter": chapter, "type": "quest_item",
                "name": name, "tier": "quest_count", "visual_brief": item_details[name],
                "palette": palette, "source_data": "data/miscItems.json",
                "source_art": f"art_source/chapters/{chapter_dir}/quest_items/{entry['id']}/",
                "runtime_art": f"assets/sprites/items/{entry['id']}.png",
                "status": "planned", "integration": "pending",
            })
        for entry in read_json(ROOT / f"data/monsters/{chapter_dir}/monsters.json"):
            name = entry["name"]
            kind = entry["kind"]
            if monster_details.get(name) != KIND_NAMES.get(kind):
                raise ValueError(f"怪物名称或档次不一致: {entry['id']} {name} {kind}")
            rows.append({
                "data_id": entry["id"], "appearance_id": entry["id"],
                "chapter": chapter, "type": "monster", "name": name,
                "tier": kind, "level": entry["level"], "visual_brief": name,
                "palette": palette,
                "source_data": f"data/monsters/{chapter_dir}/monsters.json",
                "source_art": f"art_source/chapters/{chapter_dir}/monsters/{entry['id']}/",
                "runtime_art": f"assets/sprites/monsters/{entry['id']}/",
                "status": "planned", "integration": "pending",
                "existing_partial": entry["id"] == "c2_spirit_larva",
            })
    ids = [row["data_id"] for row in rows]
    counts = {kind: sum(row["type"] == kind for row in rows) for kind in ("equipment", "quest_item", "monster")}
    if counts != {"equipment": 50, "quest_item": 21, "monster": 79} or len(ids) != len(set(ids)):
        raise ValueError(f"数量或 ID 重复: {counts}")
    return {"schema_version": 1, "source": SOURCE.relative_to(ROOT).as_posix(),
            "notes": "本文件只冻结计划，不代表图片或动画已完成；幼虫目录为未接入的局部帧。",
            "counts": counts, "assets": rows}


def check_exported_icons(existing: dict) -> None:
    """核对已审查图标的源稿、48×48 RGBA 运行图、数据路径及导出预载入口。"""
    equipment = {row["id"]: row for row in read_json(ROOT / "data/equipments.json")}
    items = {row["id"]: row for row in read_json(ROOT / "data/miscItems.json")}
    preloads = (ROOT / "scripts/systems/sample_art.gd").read_text(encoding="utf-8")
    for row in existing["assets"]:
        if row["type"] == "monster" or row["status"] == "planned":
            continue
        asset_id = row["data_id"]
        runtime = ROOT / row["runtime_art"]
        source = ROOT / row["source_art"] / "source.png"
        if not runtime.is_file() or not source.is_file():
            raise ValueError(f"源稿或运行图不存在: {asset_id}")
        with runtime.open("rb") as file:
            header = file.read(26)
        if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
            raise ValueError(f"不是 PNG: {asset_id}")
        width, height = struct.unpack(">II", header[16:24])
        if (width, height, header[25]) != (48, 48, 6):
            raise ValueError(f"不是 48×48 RGBA: {asset_id}: {width}×{height}, type {header[25]}")
        data_row = equipment[asset_id] if row["type"] == "equipment" else items[asset_id]
        res_path = "res://" + row["runtime_art"]
        if data_row.get("icon") != res_path or f'preload("{res_path}")' not in preloads:
            raise ValueError(f"运行数据或导出预载未指向正式图标: {asset_id}")


def main() -> None:
    """写入或只读校验清单；存在人工进度时拒绝覆盖，避免丢失后续状态。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="核对已保存清单，不写文件")
    args = parser.parse_args()
    generated = make_manifest()
    if args.check:
        existing = json.loads(OUTPUT.read_text(encoding="utf-8"))
        expected_ids = [row["data_id"] for row in generated["assets"]]
        actual_ids = [row["data_id"] for row in existing["assets"]]
        if expected_ids != actual_ids:
            raise ValueError("清单与运行数据 ID/顺序不一致")
        check_exported_icons(existing)
        print(f"通过：{len(actual_ids)} 个稳定 ID，{existing['counts']}")
        return
    if OUTPUT.exists():
        raise FileExistsError(f"清单已存在，不自动覆盖人工进度: {OUTPUT}")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(generated, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"已生成 {OUTPUT}：{generated['counts']}")


if __name__ == "__main__":
    main()
