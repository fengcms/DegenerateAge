"""把已确认的营地整图清洁源稿编译为运行底图和可排序的整体前景。

输入：art_source/environment/camp_final_v1/clean_plate.png 与
data/map_art/camp_whitebox_v1.json。输出只覆盖 assets/maps/camp_final_v1/。
依赖 ImageMagick；修改原画或白盒视觉轮廓后运行此脚本重建。
"""

import json
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art_source/environment/camp_final_v1/clean_plate.png"
LAYOUT = ROOT / "data/map_art/camp_whitebox_v1.json"
OUTPUT = ROOT / "assets/maps/camp_final_v1"


def run_magick(*arguments):
    """调用 ImageMagick 处理运行图像；失败时中止，避免留下半成品。"""
    subprocess.run(["magick", *map(str, arguments)], check=True)


def sprite_bounds(points, width, height):
    """按原画像素求整体精灵外框，额外留 3 像素供抗锯齿遮罩使用。"""
    x0 = max(0, min(point[0] for point in points) - 3)
    y0 = max(0, min(point[1] for point in points) - 3)
    x1 = min(width, max(point[0] for point in points) + 4)
    y1 = min(height, max(point[1] for point in points) + 4)
    return x0, y0, x1 - x0, y1 - y0


def extract_foreground(image, entity, canvas, scratch):
    """从同一压缩底图抠出一个多格实体视觉轮廓，保留透明边与脚底排序坐标。"""
    points = entity["visual"]
    left, top, width, height = sprite_bounds(points, *canvas)
    local = " ".join(f"{x - left},{y - top}" for x, y in points)
    crop = scratch / "crop.png"
    mask = scratch / "mask.png"
    run_magick(image, "-crop", f"{width}x{height}+{left}+{top}", "+repage", crop)
    run_magick("-size", f"{width}x{height}", "xc:black", "-fill", "white",
               "-draw", f"polygon {local}", "-blur", "0x0.7", mask)
    target = OUTPUT / f"{entity['id']}.png"
    run_magick(crop, mask, "-alpha", "off", "-compose", "CopyOpacity", "-composite",
               "-strip", target)
    return {"id": entity["id"], "path": f"res://assets/maps/camp_final_v1/{entity['id']}.png",
            "rect": [left, top, width, height],
            "foot_y": entity.get("visual_foot_y", max(point[1] for point in entity["footprint"]))}


def main():
    """验证源稿尺寸并重建六个整体实体前景和一张矩形底图。"""
    if shutil.which("magick") is None:
        raise RuntimeError("需要 ImageMagick 的 magick 命令")
    layout = json.loads(LAYOUT.read_text())
    canvas = layout["reference_canvas"]
    source_size = subprocess.check_output(["magick", "identify", "-format", "%w %h", str(SOURCE)], text=True)
    assert list(map(int, source_size.split())) == canvas, "营地源稿与布局画幅尺寸不一致"
    OUTPUT.mkdir(parents=True, exist_ok=True)
    image = OUTPUT / "ground.webp"
    run_magick(SOURCE, "-strip", "-quality", "93", "-define", "webp:method=6", image)
    with tempfile.TemporaryDirectory(prefix="camp-final-art-") as folder:
        scratch = Path(folder)
        sprites = [extract_foreground(image, entity, canvas, scratch)
                   for entity in layout["entities"] if "visual" in entity]
    manifest = {"source": "art_source/environment/camp_final_v1/clean_plate.png",
                "layout_id": layout["id"], "canvas": canvas,
                "ground": "res://assets/maps/camp_final_v1/ground.webp",
                "foreground": sprites}
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"营地正式美术已编译：1 张底图、{len(sprites)} 个整体实体前景")


if __name__ == "__main__":
    main()
