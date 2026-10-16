"""按开放边界营地布局生成 B 方案第二版地面、像素栅栏与整体实体。

输入是 B 样板、二版地表/栅栏源图、地面笔刷清单和 camp_whitebox_v2.json；输出只写
assets/maps/camp_style_full_b_v2/。需要 ImageMagick；布局、通行由白盒编译器负责。
"""

import json
import math
import random
import shutil
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path

from build_camp_style_sample import magick


ROOT = Path(__file__).resolve().parents[1]
LAYOUT = ROOT / "data/map_art/camp_whitebox_v2.json"
SOURCE = ROOT / "art_source/environment/camp_style_full_b"
SOURCE_V2 = ROOT / "art_source/environment/camp_style_full_b_v2"
SAMPLE = ROOT / "assets/maps/camp_style_sample/b"
OUTPUT = ROOT / "assets/maps/camp_style_full_b_v2"
GROUND_PALETTE = ROOT / "data/map_art/camp_ground_palette.json"
CANVAS = (1672, 941)
LARGE_ENTITIES = {
    "elder_tree": 130,
    "warehouse": 164,
    "guardian_lamp": 116,
    "caravan": 97,
    "training_fire": 25,
}


def write_ground_tile(output, scratch):
    """将原图裁片同向铺成循环地纹，只柔和接缝窄带，避免下半区草丛倒置。"""
    source = SOURCE_V2 / "ground_diagonal.png"
    tile = scratch / "tile.png"
    magick(source, "-crop", "1024x1024+115+115", "+repage", "-strip", tile)
    result = subprocess.run(["magick", str(tile), "-depth", "8", "rgba:-"],
                            check=True, capture_output=True)
    pixels = bytearray(result.stdout)
    side, seam = 1024, 48
    assert len(pixels) == side * side * 4, "地表源图裁片必须是 1024×1024 RGBA"
    # 两侧对应像素渐变到相同颜色；内部原生像素不变，草与石块不做任何翻转。
    for y in range(side):
        for x in range(seam):
            left = (y * side + x) * 4
            right = (y * side + side - 1 - x) * 4
            strength = 0.5 * (1.0 - x / float(seam))
            for channel in range(3):
                a, b = pixels[left + channel], pixels[right + channel]
                pixels[left + channel] = round(a * (1.0 - strength) + b * strength)
                pixels[right + channel] = round(b * (1.0 - strength) + a * strength)
    for y in range(seam):
        upper_y, lower_y = y, side - 1 - y
        strength = 0.5 * (1.0 - y / float(seam))
        for x in range(side):
            upper = (upper_y * side + x) * 4
            lower = (lower_y * side + x) * 4
            for channel in range(3):
                a, b = pixels[upper + channel], pixels[lower + channel]
                pixels[upper + channel] = round(a * (1.0 - strength) + b * strength)
                pixels[lower + channel] = round(b * (1.0 - strength) + a * strength)
    row_bytes = side * 4
    repeated = bytearray()
    for y in range(side):
        row = pixels[y * row_bytes:(y + 1) * row_bytes]
        repeated.extend(row)
        repeated.extend(row)
    write_rgba_png(output / "ground_tile.png", side * 2, side * 2, repeated * 2)
    return "res://assets/maps/camp_style_full_b_v2/ground_tile.png"


def write_rgba_png(path, width, height, rgba):
    """用标准库写真透明 PNG；仅供一次性道路构建，不在游戏运行时执行。"""
    def chunk(kind, payload):
        """封装一个 PNG 数据块并写入长度及 CRC，供本地运行素材构建。"""
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload)))
    stride = width * 4
    rows = b"".join(b"\x00" + rgba[y * stride:(y + 1) * stride] for y in range(height))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width,
                     height, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows, 7))
                     + chunk(b"IEND", b""))


def write_ground_stamps(output):
    """从同风格源图裁出带透明软边的 128 像素地面笔刷，供编辑器与正式图共用。"""
    palette = json.loads(GROUND_PALETTE.read_text())
    side = palette["cell_size"]
    if side != 128:
        raise ValueError("营地地面笔刷尺寸必须是 128 像素")
    stamps = {}
    for entry in palette["tiles"]:
        x, y, width, height = entry["source_rect"]
        if width != side or height != side:
            raise ValueError(f"地面笔刷尺寸错误：{entry['id']}")
        result = subprocess.run(["magick", str(SOURCE_V2 / "ground_diagonal.png"),
                                 "-crop", f"{side}x{side}+{x}+{y}", "+repage",
                                 "-depth", "8", "rgba:-"], check=True, capture_output=True)
        pixels = bytearray(result.stdout)
        if len(pixels) != side * side * 4:
            raise ValueError(f"地面笔刷裁切失败：{entry['id']}")
        for py in range(side):
            for px in range(side):
                distance = min(px, py, side - 1 - px, side - 1 - py)
                opacity = min(1.0, distance / 20.0)
                pixels[(py * side + px) * 4 + 3] = round(225 * opacity)
        path = output / f"ground_stamp_{entry['id']}.png"
        write_rgba_png(path, side, side, pixels)
        stamps[entry["id"]] = pixels
    return stamps


def write_ground_overlay(output, layout, stamps):
    """按画布网格合成已画笔刷，一张透明图供运行时单次绘制，空白格不改变原地面。"""
    width, height = CANVAS
    side = 128
    rgba = bytearray(width * height * 4)
    occupied = set()
    for patch in layout.get("ground_patches", []):
        tile_id = patch["tile"]
        col, row = patch["cell"]
        if tile_id not in stamps or (col, row) in occupied or not (0 <= col < 14 and 0 <= row < 8):
            raise ValueError(f"地面笔刷无效或重复：{patch}")
        occupied.add((col, row))
        stamp = stamps[tile_id]
        for py in range(min(side, height - row * side)):
            src = py * side * 4
            dst = ((row * side + py) * width + col * side) * 4
            length = min(side, width - col * side) * 4
            rgba[dst:dst + length] = stamp[src:src + length]
    write_rgba_png(output / "ground_patches.png", width, height, rgba)
    return "res://assets/maps/camp_style_full_b_v2/ground_patches.png"


def stamp_cobble(rgba, width, height, cx, cy, rx, ry, tone, alpha):
    """画一个扁平等距碎石；像素菱形在道路层独立铺排，不产生笔刷色带。"""
    for y in range(max(0, cy - ry - 1), min(height, cy + ry + 2)):
        for x in range(max(0, cx - rx - 1), min(width, cx + rx + 2)):
            distance = abs(x - cx) / max(rx, 1) + abs(y - cy) / max(ry, 1)
            if distance > 1.12:
                continue
            idx = (y * width + x) * 4
            shade = -20 if distance > 0.83 else (8 if y < cy else 0)
            rgba[idx:idx + 4] = bytes((max(0, tone[0] + shade),
                                       max(0, tone[1] + shade),
                                       max(0, tone[2] + shade),
                                       max(rgba[idx + 3], alpha // 2 if distance > 0.83 else alpha)))


def write_road_overlay(output, scratch, layout):
    """按原道路中线散铺小块等距石片；留出不规则土边且其余区域为真透明。"""
    width, height = CANVAS
    rgba = bytearray(width * height * 4)
    rng = random.Random(20261016)
    tones = [(187, 151, 104), (206, 170, 117), (160, 126, 83), (218, 181, 123)]
    paths = [(layout["main_road"], 37)] + [(path, 24) for path in layout["branches"]]
    for points, radius in paths:
        for (ax, ay), (bx, by) in zip(points, points[1:]):
            length = math.hypot(bx - ax, by - ay)
            steps = max(1, int(length / 1.9))
            nx, ny = -(by - ay) / length, (bx - ax) / length
            for step in range(steps):
                if rng.random() > 0.74:
                    continue
                t = (step + rng.random()) / steps
                spread = rng.triangular(-radius, radius, 0)
                cx = round(ax + (bx - ax) * t + nx * spread)
                cy = round(ay + (by - ay) * t + ny * spread)
                size = rng.randint(2, 6)
                alpha = rng.randint(90, 155)
                stamp_cobble(rgba, width, height, cx, cy, size, max(1, size // 2),
                             rng.choice(tones), alpha)
    write_rgba_png(output / "roads_and_shadows.png", width, height, rgba)
    return "res://assets/maps/camp_style_full_b_v2/roads_and_shadows.png"


def write_split_entity(name, entry, cut_y, output, scratch):
    """把大型精灵按前沿深度切成互斥背层与遮挡层，矩形为参考画布坐标。"""
    rect = entry["art_rect"]
    width, height = rect[2] * 2, rect[3] * 2
    cut = cut_y * 2
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
    return {"id": name, "rect": rect, "foot_y": entry["art_foot_y"],
            "back": f"res://assets/maps/camp_style_full_b_v2/{name}_back.png",
            "front": f"res://assets/maps/camp_style_full_b_v2/{name}_front.png"}


def polygon_bounds(points):
    """取原障碍多边形的整数画布边界，供单个整体视觉实体裁图。"""
    xs = [int(point[0]) for point in points]
    ys = [int(point[1]) for point in points]
    return min(xs), min(ys), max(xs), max(ys)


def write_fence(entry, output, scratch):
    """从像素木栅源图重复实景栏段；若已有美术矩形，碰撞顶点编辑不改变精灵。"""
    name = str(entry["id"])
    minx, miny, maxx, maxy = polygon_bounds(entry["polygon"])
    visual_rect = entry.get("art_rect")
    vertical = (visual_rect[3] > visual_rect[2]) if visual_rect else (maxy - miny > maxx - minx)
    if vertical:
        rect = entry.get("art_rect", [minx - 11, miny - 20, maxx - minx + 22, maxy - miny + 27])
        source = SOURCE_V2 / "fence_vertical.png"
        strip = scratch / f"{name}_strip.png"
        pair = scratch / f"{name}_pair.png"
        tiled = scratch / f"{name}_tiled.png"
        # 先去除生成图微弱的透明噪点，再以最近邻缩小，保留硬像素边缘。
        magick(source, "-channel", "A", "-threshold", "12%", "+channel", "-trim",
               "+repage", "-filter", "point", "-resize", "40x", strip)
        magick(strip, "(", strip, "-flop", ")", "-append", pair)
        width, height = rect[2] * 2, rect[3] * 2
        magick("-size", f"40x{height}", f"tile:{pair}", tiled)
        magick("-size", f"{width}x{height}", "xc:none", tiled,
               "-geometry", f"+{(width - 40)//2}+0", "-compose", "Over", "-composite",
               "-strip", output / f"{name}_front.png")
    else:
        rect = entry.get("art_rect", [minx, miny - 25, maxx - minx, maxy - miny + 36])
        source = SOURCE_V2 / "fence_horizontal.png"
        strip = scratch / f"{name}_strip.png"
        tiled = scratch / f"{name}_tiled.png"
        magick(source, "-channel", "A", "-threshold", "12%", "+channel", "-trim",
               "+repage", "-crop", "378x332+598+0", "+repage", "-filter", "point",
               "-resize", "x60", strip)
        width, height = rect[2] * 2, rect[3] * 2
        magick("-size", f"{width}x60", f"tile:{strip}", tiled)
        magick("-size", f"{width}x{height}", "xc:none", tiled,
               "-geometry", "+0+8", "-compose", "Over", "-composite",
               "-strip", output / f"{name}_front.png")
    return {"id": name, "rect": rect, "foot_y": entry.get("art_foot_y", maxy), "pixel_art": True,
            "front": f"res://assets/maps/camp_style_full_b_v2/{name}_front.png"}


def main():
    """重建开放边界营地美术；缺失源图或布局不匹配即失败。"""
    if shutil.which("magick") is None:
        raise RuntimeError("需要 ImageMagick")
    layout = json.loads(LAYOUT.read_text())
    assert layout["reference_canvas"] == list(CANVAS)
    assert len(layout["entities"]) == 7 and len(layout["fences"]) == 4
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="camp-full-b-") as folder:
        scratch = Path(folder)
        tile = write_ground_tile(OUTPUT, scratch)
        roads = write_road_overlay(OUTPUT, scratch, layout)
        stamps = write_ground_stamps(OUTPUT)
        ground_overlay = ""
        if layout.get("ground_patches", []):
            ground_overlay = write_ground_overlay(OUTPUT, layout, stamps)
        else:
            (OUTPUT / "ground_patches.png").unlink(missing_ok=True)
        sample_manifest = json.loads((SAMPLE / "manifest.json").read_text())
        by_id = {entry["id"]: entry for entry in layout["entities"]}
        objects = []
        for sample in sample_manifest["objects"]:
            if sample["id"] in ["blacksmith", "merchant"]:
                entry = by_id[sample["id"]]
                objects.append(sample | {"rect": entry["art_rect"],
                                         "foot_y": entry["art_foot_y"]})
        for name, cut_y in LARGE_ENTITIES.items():
            objects.append(write_split_entity(name, by_id[name], cut_y, OUTPUT, scratch))
        for entry in layout["fences"]:
            objects.append(write_fence(entry, OUTPUT, scratch))
    ids = [entry["id"] for entry in objects]
    assert len(ids) == 11 and len(set(ids)) == 11
    manifest = {"source": "art_source/environment/camp_style_full_b_v2/",
                "layout_id": layout["id"], "canvas": list(CANVAS),
                "ground_tile": tile, "road_overlay": roads, "objects": objects}
    if ground_overlay:
        manifest["ground_overlay"] = ground_overlay
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print("营地 B 第二版：1 张循环地纹、按需合成地面笔刷、1 张透明碎石路、7 个实体、4 段训练场像素木栅")


if __name__ == "__main__":
    main()
