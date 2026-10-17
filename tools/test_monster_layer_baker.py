#!/usr/bin/env python3
"""在系统临时目录测试怪物分层烘焙器的图集尺寸、姿势变化与坏层拦截。

测试不写入仓库素材或玩家存档。需本机 Godot 与 ImageMagick，使用当前项目脚本类缓存。
"""

import json
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")
DIRECTIONS = ["s", "sw", "w", "nw", "n", "ne", "e", "se"]


def run_baker(rig: Path) -> subprocess.CompletedProcess[str]:
    """以离线脚本模式执行烘焙器，返回状态和完整输出供断言。"""
    return subprocess.run(
        [str(GODOT), "--headless", "--path", str(ROOT), "--script",
         "tools/bake_monster_layered_animation.gd", "--", str(rig)],
        capture_output=True, text=True, timeout=30,
    )


def make_layer(path: Path, color: str, shape: str) -> None:
    """用 ImageMagick 生成测试专用透明部件；不用于正式怪物美术。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["magick", "-size", "80x80", "xc:none", "-fill", color,
                    "-draw", shape, str(path)], check=True, capture_output=True)


def png_size(path: Path) -> tuple[int, int]:
    """只读取 PNG 头判断行列像素尺寸，避免依赖第三方 Python 图像库。"""
    header = path.read_bytes()[:24]
    assert header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR"
    return struct.unpack(">II", header[16:24])


def main() -> None:
    """验证五状态八向合成与缺层失败时已生成图集不被覆盖。"""
    if not GODOT.is_file() or shutil.which("magick") is None:
        raise SystemExit("需要 Godot 和 ImageMagick")
    with tempfile.TemporaryDirectory(prefix="degenerateage-animation-baker-") as temporary:
        base = Path(temporary)
        for direction in DIRECTIONS:
            source = base / "directions" / direction
            make_layer(source / "body__base.png", "#bd8354", "circle 40,35 40,25")
            make_layer(source / "head__base.png", "#e7d3ad", "rectangle 36,28 44,40")
        frames = [{"parts": {}}, {"parts": {"head": {"offset": [2, 0]}}}]
        states = {name: {"fps": 8, "loop": name in ("idle", "walk"),
                         "visual_contact_frame": 1 if name == "attack" else 0,
                         "frames": frames} for name in ("idle", "walk", "attack", "hit", "death")}
        rig = {"id": "probe_monster", "frame_size": [80, 80], "pivot": [40, 64],
               "directions": DIRECTIONS, "layer_order": ["body", "head"], "states": states}
        rig_path = base / "rig.json"
        rig_path.write_text(json.dumps(rig), encoding="utf-8")
        result = run_baker(rig_path)
        assert result.returncode == 0, result.stdout + result.stderr
        output = base / "animations_v1"
        atlases = list(output.glob("*_atlas.png"))
        assert len(atlases) == 5 and all(png_size(path) == (160, 640) for path in atlases)
        first = base / "first.png"
        second = base / "second.png"
        subprocess.run(["magick", str(output / "idle_atlas.png"), "-crop", "80x80+0+0", "+repage", str(first)], check=True, capture_output=True)
        subprocess.run(["magick", str(output / "idle_atlas.png"), "-crop", "80x80+80+0", "+repage", str(second)], check=True, capture_output=True)
        difference = subprocess.run(["magick", "compare", "-metric", "AE", str(first), str(second), "null:"], capture_output=True, text=True)
        assert int(difference.stderr.split()[0]) > 0, "两个姿势帧没有实际像素变化"
        runtime = json.loads((output / "animation.json").read_text(encoding="utf-8"))
        assert runtime["directions"] == DIRECTIONS and runtime["states"]["attack"]["visual_contact_frame"] == 1
        before = {path.name: path.read_bytes() for path in atlases}
        rig["states"]["death"]["frames"][1]["parts"]["head"] = {"variant": "missing"}
        rig_path.write_text(json.dumps(rig), encoding="utf-8")
        result = run_baker(rig_path)
        assert result.returncode == 1 and "部件 PNG 缺失" in result.stderr
        assert before == {path.name: path.read_bytes() for path in atlases}, "坏输入覆盖了已生成图集"
        print("MonsterLayerBakerTest: PASS")


if __name__ == "__main__":
    main()
