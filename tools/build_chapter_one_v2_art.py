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
             "-channel", "A", "-threshold", "50%", "+channel", f"PNG32:{output}"],
            check=True,
        )
        print(f"{map_id}/{name}: {output}")


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
         f"PNG32:{DEST / 'ash_land/road_soft.png'}"],
        check=True,
    )


if __name__ == "__main__":
    main()
