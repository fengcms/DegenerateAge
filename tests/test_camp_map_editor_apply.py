"""营地编辑草稿应用规则测试：地面排布与单体碰撞可改，关卡固定数据须保留。"""

from __future__ import annotations

import copy
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import apply_camp_map_editor as editor_apply  # noqa: E402
import build_camp_style_full_b_v2 as art_builder  # noqa: E402


class CampMapEditorApplyTest(unittest.TestCase):
    """使用正式营地源的副本验证编辑边界，不写正式地图或玩家存档。"""

    @classmethod
    def setUpClass(cls) -> None:
        """只读载入当前正式营地源，所有测试在深拷贝上修改。"""
        cls.original = json.loads(editor_apply.SOURCE.read_text())

    def draft(self) -> dict:
        """模拟编辑器打开旧围栏布局时补齐固定美术锚点。"""
        result = copy.deepcopy(self.original)
        for fence in result["fences"]:
            rect, foot_y = editor_apply.fence_art_geometry(fence)
            fence["art_rect"] = rect.copy()
            fence["art_foot_y"] = foot_y
        return result

    def test_house_and_fence_collision_can_change_without_moving_art(self) -> None:
        """房屋与围栏顶点可调整，视觉矩形保持固定，通行仍可由新轮廓计算。"""
        draft = self.draft()
        draft["entities"][0]["footprint"][0][0] += 8
        draft["fences"][0]["polygon"][0][0] += 2
        editor_apply.validate_object_edits(self.original, draft)
        rows = editor_apply.compiled_rows(draft)
        editor_apply.validate_fixed_targets(draft, rows)

    def test_rejects_crossed_polygon_and_unrelated_map_changes(self) -> None:
        """交叉碰撞和地图尺寸篡改必须在重建前拒绝。"""
        draft = self.draft()
        draft["entities"][0]["footprint"] = [[100, 100], [200, 200], [100, 200], [200, 100]]
        with self.assertRaisesRegex(ValueError, "自交"):
            editor_apply.validate_object_edits(self.original, draft)
        draft = self.draft()
        draft["grid_size"][0] += 1
        with self.assertRaisesRegex(ValueError, "固定地图字段"):
            editor_apply.validate_object_edits(self.original, draft)

    def test_ground_patches_compile_to_transparent_overlay(self) -> None:
        """一格笔刷写入透明叠层，其他格仍完全透明且不会改变逻辑地图。"""
        draft = self.draft()
        draft["ground_patches"] = [{"cell": [3, 2], "tile": "grass"}]
        editor_apply.validate_ground_patches(draft)
        with tempfile.TemporaryDirectory(prefix="camp-ground-test-") as folder:
            output = Path(folder)
            stamps = art_builder.write_ground_stamps(output)
            overlay_path = output / "ground_patches.png"
            art_builder.write_ground_overlay(output, draft, stamps)
            self.assertTrue(overlay_path.is_file())
            center = subprocess.run(["magick", str(overlay_path), "-crop", "1x1+448+320",
                                     "+repage", "-depth", "8", "rgba:-"],
                                    check=True, capture_output=True).stdout
            untouched = subprocess.run(["magick", str(overlay_path), "-crop", "1x1+64+64",
                                        "+repage", "-depth", "8", "rgba:-"],
                                       check=True, capture_output=True).stdout
            self.assertEqual(len(center), 4)
            self.assertGreater(center[3], 0)
            self.assertEqual(untouched, b"\x00\x00\x00\x00")
        draft["ground_patches"].append({"cell": [3, 2], "tile": "pebbles"})
        with self.assertRaisesRegex(ValueError, "重复"):
            editor_apply.validate_ground_patches(draft)

    def test_apply_rebuilds_ground_and_collision_in_isolated_project(self) -> None:
        """在临时项目完整运行应用流程，确认画笔与房屋碰撞进入正式源和生成图。"""
        with tempfile.TemporaryDirectory(prefix="camp-editor-apply-") as folder:
            root = Path(folder)
            files = ["data/map_art/camp_whitebox_v2.json", "data/map_art/camp_ground_palette.json",
                     "data/maps.json", "data/layouts/camp.json", "tools/build_camp_whitebox.py",
                     "tools/build_camp_style_full_b_v2.py", "tools/build_camp_style_sample.py"]
            directories = ["art_source/environment/camp_style_full_b",
                           "art_source/environment/camp_style_full_b_v2",
                           "assets/maps/camp_style_sample/b", "assets/maps/camp_style_full_b_v2"]
            for relative in files:
                destination = root / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / relative, destination)
            for relative in directories:
                shutil.copytree(ROOT / relative, root / relative)
            source = root / "data/map_art/camp_whitebox_v2.json"
            draft = self.draft()
            draft["entities"][0]["footprint"][0][0] += 8
            draft["ground_patches"] = [{"cell": [3, 2], "tile": "grass"}]
            draft_path = root / "data/map_art/camp_editor_draft.json"
            draft_path.write_text(json.dumps({"base_hash": hashlib.sha256(source.read_bytes()).hexdigest(),
                                              "layout": draft}, ensure_ascii=False))
            with mock.patch.multiple(editor_apply, ROOT=root, SOURCE=source,
                                     MAPS=root / "data/maps.json", LAYOUT=root / "data/layouts/camp.json",
                                     ART=root / "assets/maps/camp_style_full_b_v2",
                                     GROUND_PALETTE=root / "data/map_art/camp_ground_palette.json"):
                editor_apply.apply(draft_path)
            applied = json.loads(source.read_text())
            self.assertEqual(applied["ground_patches"], draft["ground_patches"])
            self.assertEqual(applied["entities"][0]["footprint"][0][0],
                             self.original["entities"][0]["footprint"][0][0] + 8)
            self.assertFalse(draft_path.exists())
            output = root / "assets/maps/camp_style_full_b_v2"
            manifest = json.loads((output / "manifest.json").read_text())
            self.assertIn("ground_overlay", manifest)
            self.assertTrue((output / "ground_patches.png").is_file())


if __name__ == "__main__":
    unittest.main()
