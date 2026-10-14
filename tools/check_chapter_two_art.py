"""Audit the optional chapter-two actor manifest before an art integration release."""

import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ("idle", "walk", "attack", "hit", "death")


def png_size(path):
    with path.open("rb") as file:
        head = file.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def main():
    data = json.loads((ROOT / "data/chapter2_art_manifest.json").read_text())
    actors = data.get("actors", {})
    expected = [monster["id"] for monster in json.loads((ROOT / "data/monsters.json").read_text())
                if monster["id"].startswith("c2_")]
    issues = []
    for actor_id in expected:
        spec = actors.get(actor_id)
        if not isinstance(spec, dict):
            issues.append(f"{actor_id}: 未登记正式资源")
            continue
        size = spec.get("frame_size", [])
        anchor = spec.get("foot_anchor", [])
        if len(size) != 2 or min(size) <= 0 or len(anchor) != 2 or spec.get("directions") != 8:
            issues.append(f"{actor_id}: frame_size / foot_anchor / directions 元数据无效")
            continue
        for state in REQUIRED:
            row = spec.get("states", {}).get(state)
            if not isinstance(row, dict) or not str(row.get("path", "")).startswith("res://"):
                issues.append(f"{actor_id}/{state}: 路径未登记")
                continue
            path = ROOT / row["path"][6:]
            actual = png_size(path) if path.is_file() else None
            frames = row.get("frames", 0)
            fps = row.get("fps", 0)
            if not isinstance(frames, int) or frames <= 0 or not isinstance(fps, (int, float)) or fps <= 0:
                issues.append(f"{actor_id}/{state}: 帧数或帧率无效")
            elif actual != (size[0] * frames, size[1] * 8):
                issues.append(f"{actor_id}/{state}: 图集缺失或尺寸不符，实际 {actual}")
    print(f"第二章正式角色资源：{len(expected) - len({issue.split(':')[0].split('/')[0] for issue in issues})}/{len(expected)} 已齐备")
    for issue in issues:
        print("- " + issue)
    return int(bool(issues))


if __name__ == "__main__":
    raise SystemExit(main())
