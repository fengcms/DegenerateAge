"""隔离运行器完成协议回归：防主场景日志、其他场景和中途信息冒充完成。"""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("runner", Path(__file__).resolve().parents[1] / "tools/run_isolated_tests.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

class CompletionTest(unittest.TestCase):
    """仅目标测试自己的最终成功标记允许通过。"""
    def test_identity(self):
        """无最终标记、外来标记和行中成功词都不能通过。"""
        for output in ["[Main] 配置校验通过 ✅", "[OtherTest] PASS", "prefix [FooTest] PASS", "[FooTest] PASS halfway", ""]:
            self.assertFalse(runner.has_completion_marker(output, "FooTest"))
        for output in ["[FooTest] PASS", "FooTest: PASS", "[FooTest] 全部通过 ✅"]:
            self.assertTrue(runner.has_completion_marker(output, "FooTest"))

class EnvironmentTest(unittest.TestCase):
    """平台目录与引擎覆盖参数不依赖当前开发机安装方式。"""
    def test_engine_override(self):
        """显式路径优先于环境变量。"""
        with patch.dict("os.environ", {"GODOT_BIN": "/custom/godot"}):
            self.assertEqual(runner.find_godot(), Path("/custom/godot"))
            self.assertEqual(runner.find_godot("/explicit/godot"), Path("/explicit/godot"))

    def test_platform_directories(self):
        """验证三平台隔离位置，并拒绝真实项目身份。"""
        name = "DegenerateAge-Test-012345abcdef"
        for platform, segment in [("darwin", "Library/Application Support/Godot"), ("win32", "Roaming/Godot"), ("linux", "data/godot")]:
            with patch.object(runner.sys, "platform", platform), patch.dict("os.environ", {"APPDATA": "/Roaming", "XDG_DATA_HOME": "/data"}):
                self.assertIn(segment, runner.isolated_user_data(name).as_posix())
        with self.assertRaises(ValueError):
            runner.isolated_user_data("末法纪元：最后的守护者")

if __name__ == "__main__":
    unittest.main()
