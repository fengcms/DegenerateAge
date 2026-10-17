#!/usr/bin/env python3
"""把已审查的章节怪物单体造型导出为临时三帧运行图，并同步外观引用。

按章执行 ``--chapter ch02`` 至 ``ch06``；仅生成简化静态表现，不宣称八向动画完成。
需要 Pillow；本工具不修改怪物身份、数值、碰撞、掉落或存档。
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageOps

from monster_catalog import load_chapter, save_chapter


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs/素材设计/制作记录/11-60级/asset_manifest.json"
APPEARANCE_DIR = ROOT / "data/monster_appearances"
PRELOAD_LIBRARY = ROOT / "scripts/entities/simplified_monster_library.gd"
KINDS = {"normal": (80, 64, -70), "elite": (112, 88, -96), "boss": (192, 152, -160)}


def read_manifest() -> dict:
    """读取稳定 ID 清单；只在已有概念稿的章节批次上修改进度字段。"""
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def prepare_pose(source: Path, side: int, foot_y: int) -> Image.Image:
    """按非空透明区域裁切单体，缩至原尺寸脚底锚点；不合成方向或伪造动作。"""
    image = Image.open(source).convert("RGBA")
    alpha = image.getchannel("A")
    bbox = alpha.point(lambda value: 255 if value > 64 else 0).getbbox()
    if bbox is None:
        raise ValueError(f"空白怪物概念稿：{source}")
    body = image.crop(bbox)
    body.thumbnail((round(side * 0.90), round(side * 0.76)), Image.Resampling.LANCZOS)
    frame = Image.new("RGBA", (side, side))
    frame.alpha_composite(body, ((side - body.width) // 2, foot_y - body.height))
    return frame


def make_atlas(base: Image.Image) -> Image.Image:
    """生成原姿、受击闪白、死亡褪色三格；状态由现有 Monster 生命周期切换。"""
    width, height = base.size
    atlas = Image.new("RGBA", (width * 3, height))
    atlas.alpha_composite(base, (0, 0))
    bright = Image.blend(base.convert("RGB"), Image.new("RGB", base.size, "#ffffff"), 0.56)
    bright.putalpha(base.getchannel("A"))
    atlas.alpha_composite(bright, (width, 0))
    gray = ImageOps.grayscale(base.convert("RGB")).convert("RGB")
    faded = ImageEnhance.Brightness(gray).enhance(0.48)
    faded.putalpha(base.getchannel("A"))
    atlas.alpha_composite(faded, (width * 2, 0))
    return atlas


def update_preload_library(manifest: dict) -> None:
    """从已登记临时图构建静态预载表，确保 Godot 导出包不会漏掉字符串路径资源。"""
    rows = [row for row in manifest["assets"] if row["type"] == "monster" and row.get("integration") == "temporary_static"]
    lines = [
        "class_name SimplifiedMonsterLibrary", "extends RefCounted",
        "## 由 tools/build_simplified_monster_art.py 生成；预载已接入的临时怪物静态图。",
        "## 三格为原姿、受击、死亡；后续八向动画可逐 ID 替换外观档案。",
        "const TEXTURES := {",
    ]
    for row in rows:
        lines.append(f'\t"{row["data_id"]}": preload("res://{row["temporary_sprite"]}"),')
    lines.append("}\n")
    PRELOAD_LIBRARY.write_text("\n".join(lines), encoding="utf-8")


def make_preview(chapter: str, entries: list[tuple[dict, Image.Image]]) -> None:
    """用深浅两种游戏常见底色拼版，供逐章肉眼检查轮廓和透明边。"""
    width, height = 248, 232
    columns = 4
    board = Image.new("RGB", (width * columns, height * ((len(entries) + columns - 1) // columns)))
    draw = ImageDraw.Draw(board)
    for i, (entry, frame) in enumerate(entries):
        col, row = i % columns, i // columns
        x, y = col * width, row * height
        background = "#202a2e" if col % 2 == 0 else "#b3aa96"
        draw.rectangle((x, y, x + width - 1, y + height - 1), fill=background)
        board.paste(frame, (x + (width - frame.width) // 2, y + 14 + (192 - frame.height) // 2), frame)
        draw.text((x + 8, y + height - 20), entry["data_id"], fill="#f2dfb8" if col % 2 == 0 else "#171f23")
    path = ROOT / "docs/素材设计/制作记录/11-60级" / f"{chapter}_monsters_runtime_preview.png"
    board.save(path)


def build_chapter(chapter: str) -> None:
    """仅处理指定章的 15—18 个稳定 ID，生成图、外观档案并同步章节 README。"""
    manifest = read_manifest()
    rows = load_chapter(chapter)
    records = {row["data_id"]: row for row in manifest["assets"] if row["type"] == "monster" and row["chapter"] == int(chapter[2:])}
    if len(rows) != len(records):
        raise ValueError(f"怪物 ID 数量不一致：{chapter}")
    previews: list[tuple[dict, Image.Image]] = []
    index = json.loads((APPEARANCE_DIR / "index.json").read_text(encoding="utf-8"))
    for monster in rows:
        key = monster["id"]
        record = records[key]
        # 已升级为方向试玩或正式包的外观不再由临时三格构建器覆盖。
        if record.get("integration") != "temporary_static":
            continue
        side, foot_y, head_y = KINDS[monster["kind"]]
        source = ROOT / record["concept_art"]
        base = prepare_pose(source, side, foot_y)
        sprite = ROOT / record["runtime_art"] / "simplified_atlas.png"
        sprite.parent.mkdir(parents=True, exist_ok=True)
        make_atlas(base).save(sprite, optimize=True)
        preview_entry = {"data_id": key}
        previews.append((preview_entry, base))
        spec = {
            "id": key, "renderer": "static_atlas",
            "texture": "res://" + sprite.relative_to(ROOT).as_posix(),
            "hframes": 3, "offset": [-side // 2, -foot_y], "headHpY": head_y,
            "desc": "临时简化表现：单个东南向造型，受击与死亡变色；八向五状态动画待补。",
        }
        filename = f"{key}.json"
        (APPEARANCE_DIR / filename).write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if filename not in index:
            index.append(filename)
        monster["appearanceId"] = key
        record["temporary_sprite"] = sprite.relative_to(ROOT).as_posix()
        record["runtime_variant"] = "single_direction_three_frame"
        record["status"] = "reviewed"
        record["integration"] = "temporary_static"
    save_chapter(chapter, rows)
    (APPEARANCE_DIR / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    update_preload_library(manifest)
    make_preview(chapter, previews)
    print(f"{chapter}: 导出并登记 {len(rows)} 个临时怪物表现")


def main() -> None:
    """解析一个章节批次参数；正式动画制作后可保留历史导出记录。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chapter", choices=[f"ch{n:02d}" for n in range(2, 7)], required=True)
    args = parser.parse_args()
    build_chapter(args.chapter)


if __name__ == "__main__":
    main()
