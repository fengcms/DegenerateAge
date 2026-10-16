"""按幸存者营地唯一布局源生成 B 方案全图分层素材与清单。

输入是 B 样板、美术源图及 camp_whitebox_v1.json；输出仅写
assets/maps/camp_style_full_b/。不改地图尺寸、NPC、通行与障碍；依赖 ImageMagick。
建筑作为整体透明实体，底层只含可踩地面、路和贴地阴影。
"""

import json
import shutil
import tempfile
from pathlib import Path

from build_camp_style_sample import magick, smooth_path


ROOT = Path(__file__).resolve().parents[1]
LAYOUT = ROOT / "data/map_art/camp_whitebox_v1.json"
SOURCE = ROOT / "art_source/environment/camp_style_full_b"
SAMPLE = ROOT / "assets/maps/camp_style_sample/b"
OUTPUT = ROOT / "assets/maps/camp_style_full_b"
CANVAS = (1672, 941)
LARGE_ENTITIES = {
    "elder_tree": {"rect": [925, 225, 260, 195], "cut": 130, "foot_y": 418},
    "warehouse": {"rect": [995, 100, 315, 201], "cut": 164, "foot_y": 301},
    "guardian_lamp": {"rect": [750, 276, 76, 170], "cut": 130, "foot_y": 446},
    "caravan": {"rect": [985, 510, 365, 200], "cut": 155, "foot_y": 710},
    "training_fire": {"rect": [637, 636, 38, 34], "cut": 25, "foot_y": 670},
}


def write_ground_tile(output, scratch):
    """生成一份 1024×1024 可重复 B 地纹图集，避免小样板重复纹显眼。"""
    source = SOURCE / "ground_variant.png"
    tile = scratch / "tile.png"
    top = scratch / "top.png"
    magick(source, "-resize", "512x512!", "-modulate", "100,72,100",
           "-brightness-contrast", "0x-16", "-blur", "0x1.4", "-strip", tile)
    magick(tile, "(", tile, "-flop", ")", "+append", top)
    magick(top, "(", top, "-flip", ")", "-append", "-strip", output / "ground_tile.png")
    return "res://assets/maps/camp_style_full_b/ground_tile.png"


def write_road_overlay(output, scratch, layout):
    """在参考画布尺寸生成透明道路与贴地阴影，路心仍只取布局控制点。"""
    width, height = CANVAS
    paths = [layout["main_road"], *layout["branches"]]
    layers = []
    for name, color, stroke, opacity, blur in [
        ("outer", "#ad9168", 112, 0.48, 5),
        ("inner", "#c6aa7f", 78, 0.59, 2),
    ]:
        path = scratch / f"road_{name}.png"
        cmd = ["-size", f"{width}x{height}", "xc:none", "-fill", "none",
               "-stroke", color, "-strokewidth", str(stroke)]
        for points in paths:
            cmd += ["-draw", f"path '{smooth_path(points, 1, (0, 0))}'"]
            for x, y in [points[0], points[-1]]:
                cmd += ["-draw", f"circle {x},{y} {x+stroke/2},{y}"]
        magick(*cmd, "-blur", f"0x{blur}", "-channel", "A", "-evaluate",
               "multiply", str(opacity), "+channel", path)
        layers.append(path)
    shadows = scratch / "shadows.png"
    shadow_cmd = ["-size", f"{width}x{height}", "xc:none", "-fill", "rgba(26,19,12,0.14)",
                  "-stroke", "none"]
    for x, y, rx, ry in [(385, 301, 145, 20), (1152, 290, 145, 17), (459, 469, 140, 12),
                         (790, 438, 28, 10), (1080, 411, 33, 12), (1160, 700, 172, 14)]:
        shadow_cmd += ["-draw", f"ellipse {x},{y} {rx},{ry} 0,360"]
    magick(*shadow_cmd, "-blur", "0x5", shadows)
    magick(*layers, "-compose", "Over", "-composite", shadows,
           "-compose", "Over", "-composite", "-strip", output / "roads_and_shadows.png")
    return "res://assets/maps/camp_style_full_b/roads_and_shadows.png"


def write_split_entity(name, spec, output, scratch):
    """把大型精灵按前沿深度切成互斥背层与遮挡层，矩形为参考画布坐标。"""
    width, height = spec["rect"][2] * 2, spec["rect"][3] * 2
    cut = spec["cut"] * 2
    source = SOURCE / f"{name}.png"
    full = scratch / f"{name}_full.png"
    back_crop = scratch / f"{name}_back_crop.png"
    magick(source, "-trim", "+repage", "-resize", f"{width}x{height}!", "-strip", full)
    magick(full, "-crop", f"{width}x{cut}+0+0", "+repage", "-background", "none",
           "-gravity", "northwest", "-extent", f"{width}x{height}", "-strip",
           output / f"{name}_front.png")
    magick(full, "-crop", f"{width}x{height-cut}+0+{cut}", "+repage", back_crop)
    magick("-size", f"{width}x{height}", "xc:none", back_crop, "-geometry", f"+0+{cut}",
           "-compose", "Over", "-composite", "-strip", output / f"{name}_back.png")
    return {"id": name, "rect": spec["rect"], "foot_y": spec["foot_y"],
            "back": f"res://assets/maps/camp_style_full_b/{name}_back.png",
            "front": f"res://assets/maps/camp_style_full_b/{name}_front.png"}


def polygon_bounds(points):
    """取原障碍多边形的整数画布边界，供单个整体视觉实体裁图。"""
    xs = [int(point[0]) for point in points]
    ys = [int(point[1]) for point in points]
    return min(xs), min(ys), max(xs), max(ys)


def _fence_svg(points, rect, vertical):
    """绘制一整段栅栏；每段仍只对应布局中的一个障碍多边形。"""
    x0, y0, width, height = rect
    body = "#51402f"
    edge = "#a98459"
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width*2}" height="{height*2}" '
           f'viewBox="0 0 {width} {height}">']
    if vertical:
        minx, miny, maxx, maxy = polygon_bounds(points)
        ax = (minx + maxx) / 2 - x0
        for offset in [-10, 2]:
            svg.append(f'<rect x="{ax+offset}" y="0" width="5" height="{height}" fill="{body}"/>')
        for local_y in range(22, height, 44):
            svg.append(f'<polygon points="{ax-12},{local_y+10} {ax-12},{local_y-13} '
                       f'{ax-6},{local_y-24} {ax},{local_y-13} {ax},{local_y+10}" '
                       f'fill="{body}" stroke="{edge}" stroke-width="1.4"/>')
    else:
        minx, miny, maxx, maxy = polygon_bounds(points)
        span = maxx - minx
        # 长围栏的顶部形状可有中间控制点；横向矩形直接走水平底线。
        upper = points[:len(points)//2] if len(points) > 4 else [[minx, miny], [maxx, miny]]
        upper = sorted(upper, key=lambda p: p[0])
        baseline = [(int(p[0])-x0, int(p[1])-y0+10) for p in upper]
        for offset in [-23, 0]:
            for (x1, y1), (x2, y2) in zip(baseline, baseline[1:]):
                svg.append(f'<polygon points="{x1},{y1+offset} {x2},{y2+offset} '
                           f'{x2},{y2+offset+8} {x1},{y1+offset+8}" fill="{body}"/>')
                svg.append(f'<polygon points="{x1},{y1+offset} {x2},{y2+offset} '
                           f'{x2},{y2+offset+2} {x1},{y1+offset+2}" fill="{edge}"/>')
        for x in range(8, span, 32):
            source_x = minx + x
            y = upper[0][1]
            for left, right in zip(upper, upper[1:]):
                if left[0] <= source_x <= right[0] and right[0] != left[0]:
                    mix = (source_x-left[0])/(right[0]-left[0])
                    y = left[1]*(1-mix)+right[1]*mix
                    break
            local_y = y-y0+10
            svg.append(f'<path d="M{x-5},{local_y+10:.1f} L{x-5},{local_y-22:.1f} '
                       f'L{x},{local_y-30:.1f} L{x+5},{local_y-22:.1f} '
                       f'L{x+5},{local_y+10:.1f} Z" fill="{body}" '
                       f'stroke="{edge}" stroke-width="1.6"/>')
    svg.append("</svg>")
    return "\n".join(svg)


def write_fence(entry, output, scratch):
    """从原多边形生成一段连续透明木栅，不拆成 1×1 瓦片。"""
    name = str(entry["id"])
    points = entry["polygon"]
    minx, miny, maxx, maxy = polygon_bounds(points)
    vertical = maxy-miny > maxx-minx
    rect = [minx-12 if vertical else minx, miny-16 if vertical else miny-46,
            maxx-minx+24 if vertical else maxx-minx, maxy-miny+44 if vertical else maxy-miny+74]
    svg = scratch / f"{name}.svg"
    svg.write_text(_fence_svg(points, rect, vertical))
    magick("-background", "none", svg, "-strip", output / f"{name}_front.png")
    return {"id": name, "rect": rect, "foot_y": maxy,
            "front": f"res://assets/maps/camp_style_full_b/{name}_front.png"}


def write_rocks(entry, output, scratch):
    """将整体岩石源按原边界裁成单段岩带，不在可走区添加承重碎石。"""
    name = str(entry["id"])
    points = entry["polygon"]
    minx, miny, maxx, maxy = polygon_bounds(points)
    width, height = maxx-minx, maxy-miny
    portrait = height > width
    source = SOURCE.parent / "camp_style_sample/western_rocks_b.png"
    rock = scratch / f"{name}_fitted.png"
    mask = scratch / f"{name}_mask.png"
    if portrait:
        magick(source, "-trim", "+repage", "-resize", f"{width*2}x{height*2}!", rock)
    else:
        rotated = scratch / f"{name}_rotated.png"
        magick(source, "-trim", "+repage", "-rotate", "90", "-resize", "400x120!", rotated)
        magick("-size", f"{width*2}x{height*2}", f"tile:{rotated}", rock)
    local = " ".join(f"{(int(x)-minx)*2},{(int(y)-miny)*2}" for x, y in points)
    magick("-size", f"{width*2}x{height*2}", "xc:none", "-fill", "white", "-draw",
           f"polygon {local}", mask)
    magick(rock, mask, "-compose", "DstIn", "-composite", "-strip",
           output / f"{name}_front.png")
    return {"id": name, "rect": [minx, miny, width, height], "foot_y": maxy,
            "front": f"res://assets/maps/camp_style_full_b/{name}_front.png"}


def main():
    """重建全营地 B 图层；缺失美术或布局不匹配即失败，不静默改碰撞。"""
    if shutil.which("magick") is None:
        raise RuntimeError("需要 ImageMagick")
    layout = json.loads(LAYOUT.read_text())
    assert layout["reference_canvas"] == list(CANVAS)
    assert len(layout["entities"]) == 7 and len(layout["fences"]) == 15
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="camp-full-b-") as folder:
        scratch = Path(folder)
        tile = write_ground_tile(OUTPUT, scratch)
        roads = write_road_overlay(OUTPUT, scratch, layout)
        sample_manifest = json.loads((SAMPLE / "manifest.json").read_text())
        objects = [entry for entry in sample_manifest["objects"]
                   if entry["id"] in ["blacksmith", "merchant",
                                      "northwest_palisade", "western_rocks"]]
        for name, spec in LARGE_ENTITIES.items():
            objects.append(write_split_entity(name, spec, OUTPUT, scratch))
        for entry in layout["fences"]:
            name = entry["id"]
            if name in ["northwest_palisade", "western_rocks"]:
                continue
            if "rocks" in name:
                objects.append(write_rocks(entry, OUTPUT, scratch))
            else:
                objects.append(write_fence(entry, OUTPUT, scratch))
    ids = [entry["id"] for entry in objects]
    assert len(ids) == 22 and len(set(ids)) == 22
    manifest = {"source": "art_source/environment/camp_style_full_b/",
                "layout_id": layout["id"], "canvas": list(CANVAS),
                "ground_tile": tile, "road_overlay": roads, "objects": objects}
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print("营地 B 全图：1 张循环地纹、1 张透明道路、7 个实体、15 段围栏/岩带")


if __name__ == "__main__":
    main()
