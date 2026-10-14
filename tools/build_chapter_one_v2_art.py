"""把第一章四张 AI 原画分格、去透明边并缩放为可重复构建的运行素材。

源图位于 art_source/environment/chapter1_v2；每张为四个互不重叠的物件。
脚本只覆盖 assets/tiles/chapter1_v2 下列出的输出，不改旧素材与地图数据。
"""

from __future__ import annotations

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art_source/environment/chapter1_v2"
DEST = ROOT / "assets/tiles/chapter1_v2"

SHEETS = {
    "wild_trial": (1254, 1254, "32%", "12%", ("moss_ridge", "dead_tree", "insect_stone", "broken_cart")),
    "camp": (1536, 1024, "30%", "55%", ("merchant_stall", "forge_shelter", "warehouse", "guardian_lamp")),
    "ash_land": (1536, 1024, "30%", "14%", ("ruin_wall", "collapsed_house", "spirit_trench", "ash_memorial")),
    "corruption_source": (1254, 1254, "32%", "12%", ("cave_buttress", "seal_arch", "ritual_altar", "arena_edge")),
}
ROAD_DIRECTIONS = {"n": (1,), "e": (2,), "s": (4,), "w": (8,),
                   "ne": (1, 2), "se": (2, 4), "sw": (4, 8), "nw": (8, 1)}


def build_sheet(map_id: str, spec: tuple) -> None:
    """按源图已审核的四格排版导出一图一物；要求本机安装 ImageMagick。"""
    width, height, scale, alpha_cutoff, names = spec
    source = SOURCE / f"{map_id}_objects_sheet.png"
    half_w, half_h = width // 2, height // 2
    target_dir = DEST / map_id
    target_dir.mkdir(parents=True, exist_ok=True)
    for index, name in enumerate(names):
        x, y = (index % 2) * half_w, (index // 2) * half_h
        output = target_dir / f"{name}.png"
        subprocess.run(
            ["magick", str(source), "-crop", f"{half_w}x{half_h}+{x}+{y}", "+repage",
             "-channel", "A", "-threshold", alpha_cutoff, "+channel", "-trim", "+repage",
             "-filter", "Lanczos", "-resize", scale, "-colors", "48",
             "-channel", "A", "-threshold", "50%", "+channel", "-strip", f"PNG32:{output}"],
            check=True,
        )
        print(f"{map_id}/{name}: {output}")


def raw_rgba(path: Path) -> bytes:
    """通过 ImageMagick 读取 64×32 原地砖的直通 RGBA 字节，避免额外库依赖。"""
    result = subprocess.run(["magick", str(path), "-depth", "8", "RGBA:-"],
                            check=True, capture_output=True)
    assert len(result.stdout) == 64 * 32 * 4, path
    return result.stdout


def build_road_transitions(map_id: str, base: Path, road: Path) -> None:
    """保留旧砖像素和菱形透明边，生成四边与四角的单格道路过渡。"""
    ground_pixels, road_pixels = raw_rgba(base), raw_rgba(road)
    for name, directions in ROAD_DIRECTIONS.items():
        pixels = bytearray(ground_pixels)
        for y in range(32):
            for x in range(64):
                offset = (y * 64 + x) * 4
                if ground_pixels[offset + 3] == 0:
                    continue
                u, v = (x - 31.5) / 32.0, (y - 15.5) / 16.0
                col, row = (u - v) * 0.5, (-u - v) * 0.5
                proximity = {1: -row, 2: col, 4: row, 8: -col}
                nearest = max(proximity[direction] for direction in directions)
                # 半格边缘保留约 1/3 路面，轻微像素缺口让土/灰自然过渡。
                coarse = (x * 17 + y * 29) % 7
                if nearest > 0.18 or (nearest > 0.12 and coarse < 2):
                    pixels[offset:offset + 4] = road_pixels[offset:offset + 4]
        output = DEST / map_id / f"road_edge_{name}.png"
        subprocess.run(["magick", "-size", "64x32", "-depth", "8", "RGBA:-", "-strip",
                        f"PNG32:{output}"], input=bytes(pixels), check=True)


def main() -> None:
    """验证四张源图尺寸后导出固定命名的运行贴图。"""
    for map_id, spec in SHEETS.items():
        source = SOURCE / f"{map_id}_objects_sheet.png"
        result = subprocess.run(["magick", "identify", "-format", "%wx%h", str(source)],
                                check=True, capture_output=True, text=True)
        assert result.stdout == f"{spec[0]}x{spec[1]}", (source, result.stdout)
        build_sheet(map_id, spec)
    # 灰烬旧路砖亮度高于危险提示，保留纹理与透明边并降低 RGB 亮度。
    subprocess.run(
        ["magick", str(ROOT / "assets/tiles/ash/tile_3.png"), "-channel", "RGB",
         "-evaluate", "multiply", "0.78", "+channel",
         "-strip",
         f"PNG32:{DEST / 'ash_land/road_soft.png'}"],
        check=True,
    )
    for map_id, theme in (("camp", "camp"), ("wild_trial", "wild"),
                          ("ash_land", "ash"), ("corruption_source", "cave")):
        road = DEST / "ash_land/road_soft.png" if theme == "ash" else ROOT / f"assets/tiles/{theme}/tile_3.png"
        build_road_transitions(map_id, ROOT / f"assets/tiles/{theme}/tile_0.png", road)


if __name__ == "__main__":
    main()
