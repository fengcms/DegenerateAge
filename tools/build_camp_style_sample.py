"""从八张营地局部源图重建 A/B 可运行样板贴图。

输入为 art_source/environment/camp_style_sample/ 与现有营地布局；只写
assets/maps/camp_style_sample/。地面不包含任何立体物件，整体实体拆成
互不重叠的背层与前沿遮挡层；依赖 ImageMagick，不改正式地图素材。
"""

import json
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art_source/environment/camp_style_sample"
OUTPUT = ROOT / "assets/maps/camp_style_sample"
LAYOUT = ROOT / "data/map_art/camp_whitebox_v1.json"
PATCH = [0, 60, 1250, 790]
OBJECTS = {
    "blacksmith": {"rect": [230, 120, 310, 190], "cut": 153, "foot_y": 310},
    "merchant": {"rect": [305, 315, 310, 165], "cut": 120, "foot_y": 482},
    "elder_tree": {"rect": [955, 225, 260, 195], "cut": 130, "foot_y": 418},
}


def magick(*args):
    """运行 ImageMagick；单步失败即停止，避免把不完整素材写入样板。"""
    subprocess.run(["magick", *map(str, args)], check=True)


def write_ground(style, scale, output, scratch, layout):
    """铺设可踩地面和贴地道路；局部边缘用透明渐隐标出样板边界。"""
    tile_source = SOURCE / f"ground_{style}.png"
    tile_size = 128 * scale
    tile = scratch / "tile.png"
    right = scratch / "right.png"
    top = scratch / "top.png"
    bottom = scratch / "bottom.png"
    seamless = scratch / "seamless.png"
    magick(tile_source, "-resize", f"{tile_size}x{tile_size}!", tile)
    magick(tile, "-flop", right)
    magick(tile, right, "+append", top)
    magick(top, "-flip", bottom)
    magick(top, bottom, "-append", seamless)
    width, height = PATCH[2] * scale, PATCH[3] * scale
    base = scratch / "base.png"
    magick("-size", f"{width}x{height}", f"tile:{seamless}", base)
    paths = [layout["main_road"], *layout["branches"]]
    road_solid = scratch / "roads_solid.png"
    road_png = scratch / "roads.png"
    roads_cmd = ["-size", f"{width}x{height}", "xc:none"]
    colors = [("#755c3d", 92), ("#b59b72", 76)] if style == "a" \
        else [("#826443", 92), ("#c09e6f", 76)]
    for color, stroke in colors:
        radius = stroke * scale / 2
        roads_cmd += ["-stroke", color, "-strokewidth", str(stroke * scale), "-fill", "none"]
        for points in paths:
            for (x1, y1), (x2, y2) in zip(points, points[1:]):
                ax, ay = (x1-PATCH[0])*scale, (y1-PATCH[1])*scale
                bx, by = (x2-PATCH[0])*scale, (y2-PATCH[1])*scale
                roads_cmd += ["-draw", f"line {ax},{ay} {bx},{by}"]
        roads_cmd += ["-stroke", "none", "-fill", color]
        for points in paths:
            for x, y in points:
                px, py = (x-PATCH[0])*scale, (y-PATCH[1])*scale
                roads_cmd += ["-draw", f"circle {px},{py} {px+radius},{py}"]
    magick(*roads_cmd, road_solid)
    magick(road_solid, "-channel", "A", "-evaluate", "multiply", "0.68", "+channel", road_png)
    painted = scratch / "painted.png"
    shadow = scratch / "shadows.png"
    shadow_cmd = ["-size", f"{width}x{height}", "xc:none", "-fill", "rgba(26,19,12,0.23)", "-stroke", "none"]
    for x, y, rx, ry in [(385, 301, 145, 20), (459, 469, 140, 12), (1080, 411, 33, 12)]:
        cx, cy = (x-PATCH[0])*scale, (y-PATCH[1])*scale
        shadow_cmd += ["-draw", f"ellipse {cx},{cy} {rx*scale},{ry*scale} 0,360"]
    magick(*shadow_cmd, "-blur", f"0x{4*scale}", shadow)
    magick(base, road_png, "-compose", "Over", "-composite", shadow,
           "-compose", "Over", "-composite", painted)
    inset = 18 * scale
    mask = scratch / "fade_mask.png"
    magick("-size", f"{width}x{height}", "xc:black", "-fill", "white", "-draw",
           f"rectangle {inset},{inset} {width-inset-1},{height-inset-1}",
           "-blur", f"0x{9*scale}", mask)
    magick(painted, mask, "-alpha", "off", "-compose", "CopyOpacity", "-composite",
           "-strip", output / "ground.png")


def write_split_object(style, scale, name, spec, output, scratch):
    """把独立物体按画面前沿切成透明背层和遮挡层，像素不在底图重复。"""
    width, height = spec["rect"][2] * scale, spec["rect"][3] * scale
    cut = spec["cut"] * scale
    full = scratch / f"{name}_full.png"
    magick(SOURCE / f"{name}_{style}.png", "-trim", "+repage", "-resize",
           f"{width}x{height}!", "-strip", full)
    magick(full, "-crop", f"{width}x{cut}+0+0", "+repage", "-background", "none",
           "-gravity", "northwest", "-extent", f"{width}x{height}", output / f"{name}_front.png")
    bottom = scratch / f"{name}_bottom.png"
    magick(full, "-crop", f"{width}x{height-cut}+0+{cut}", "+repage", bottom)
    magick("-size", f"{width}x{height}", "xc:none", bottom, "-geometry", f"+0+{cut}",
           "-compose", "Over", "-composite", output / f"{name}_back.png")
    return {"id": name, "rect": spec["rect"], "foot_y": spec["foot_y"],
            "back": f"res://assets/maps/camp_style_sample/{style}/{name}_back.png",
            "front": f"res://assets/maps/camp_style_sample/{style}/{name}_front.png"}


def write_fence(style, scale, output):
    """按既有北侧障碍轮廓制作单一连续栅栏贴图，避免每格一个物体。"""
    wood = "#51402f" if style == "a" else "#473728"
    light = "#9b7850" if style == "a" else "#ae8354"
    width, height = 760 * scale, 78 * scale
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
           f'viewBox="0 0 760 78">']
    centers = [(0, 55), (230, 42), (530, 57), (760, 49)]
    for (x1, y1), (x2, y2) in zip(centers, centers[1:]):
        for offset in [-23, 0]:
            top1, top2 = y1 + offset, y2 + offset
            svg.append(f'<polygon points="{x1},{top1} {x2},{top2} '
                       f'{x2},{top2+9} {x1},{top1+9}" fill="{wood}"/>')
            svg.append(f'<polygon points="{x1},{top1} {x2},{top2} '
                       f'{x2},{top2+2} {x1},{top1+2}" fill="{light}"/>')
    for x in range(8, 760, 32):
        y = 55 - 13*x/230 if x <= 230 else (42 + 15*(x-230)/300 if x <= 530 else 57-8*(x-530)/230)
        svg.append(f'<path d="M{x-5},{y+13:.1f} L{x-5},{y-24:.1f} L{x},{y-32:.1f} '
                   f'L{x+5},{y-24:.1f} L{x+5},{y+13:.1f} Z" fill="{wood}" '
                   f'stroke="{light}" stroke-width="2"/>')
    svg.append("</svg>")
    with tempfile.TemporaryDirectory(prefix="camp-fence-") as folder:
        path = Path(folder) / "fence.svg"
        path.write_text("\n".join(svg))
        magick("-background", "none", path, "-strip", output / "northwest_palisade_front.png")
    return {"id": "northwest_palisade", "rect": [0, 51, 760, 78], "foot_y": 120,
            "front": f"res://assets/maps/camp_style_sample/{style}/northwest_palisade_front.png"}


def write_western_rocks(style, scale, output):
    """只在现有西侧岩石障碍范围画立体岩面，避免新增可踩假障碍。"""
    dark = "#4f4942" if style == "a" else "#494b4b"
    mid = "#777267" if style == "a" else "#747673"
    light = "#a49a82" if style == "a" else "#aaa492"
    cliff = "M0 0 L30 0 L95 240 L55 370 L0 400 Z"
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{95*scale}" height="{400*scale}" viewBox="0 0 95 400">',
           f'<defs><clipPath id="cliff"><path d="{cliff}"/></clipPath></defs>',
           f'<path d="{cliff}" fill="{dark}"/>', '<g clip-path="url(#cliff)">']
    for row in range(12):
        y = row * 35 - 7
        offset = (row * 17) % 23 - 6
        svg.append(f'<polygon points="{offset},{y+8} {offset+39},{y} {offset+70},{y+13} '
                   f'{offset+61},{y+29} {offset+16},{y+36}" fill="{mid}"/>')
        svg.append(f'<polyline points="{offset+2},{y+9} {offset+39},{y+2} {offset+67},{y+14}" '
                   f'fill="none" stroke="{light}" stroke-width="3" opacity=".72"/>')
        svg.append(f'<polyline points="{offset+16},{y+36} {offset+60},{y+30} {offset+70},{y+13}" '
                   f'fill="none" stroke="{dark}" stroke-width="4"/>')
    svg += ['</g>', f'<path d="{cliff}" fill="none" stroke="{light}" stroke-width="2" opacity=".65"/>', '</svg>']
    with tempfile.TemporaryDirectory(prefix="camp-rocks-") as folder:
        path = Path(folder) / "rocks.svg"
        path.write_text("\n".join(svg))
        magick("-background", "none", path, "-strip", output / "western_rocks_front.png")
    return {"id": "western_rocks", "rect": [0, 450, 95, 400], "foot_y": 850,
            "front": f"res://assets/maps/camp_style_sample/{style}/western_rocks_front.png"}


def main():
    """重建同一坐标的 A/B 样板，并写入运行清单与透明层约定。"""
    if shutil.which("magick") is None:
        raise RuntimeError("需要 ImageMagick")
    layout = json.loads(LAYOUT.read_text())
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for style, scale in [("a", 1), ("b", 2)]:
        output = OUTPUT / style
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="camp-style-") as folder:
            scratch = Path(folder)
            write_ground(style, scale, output, scratch, layout)
            objects = [write_split_object(style, scale, name, spec, output, scratch)
                       for name, spec in OBJECTS.items()]
        objects.append(write_fence(style, scale, output))
        objects.append(write_western_rocks(style, scale, output))
        manifest = {"style": style.upper(), "layout_id": layout["id"], "canvas": layout["reference_canvas"],
                    "patch": PATCH, "ground": f"res://assets/maps/camp_style_sample/{style}/ground.png",
                    "objects": objects}
        (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        print(f"营地 {style.upper()} 局部样板：1 张纯地面、{len(objects)} 个整体实体")


if __name__ == "__main__":
    main()
