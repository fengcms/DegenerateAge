"""隔离运行单方向动作审片器，仅加载候选源稿，不启动正式游戏或读取存档。"""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    """复制固定审片输入至临时项目，导入后运行窗口或有成功标记的自动校验。"""
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--capture', type=Path)
    args = parser.parse_args()
    godot = shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot'
    with tempfile.TemporaryDirectory(prefix='motion-review-') as temp:
        project = Path(temp)
        for name in ['main.gd', 'main.gd.uid']:
            shutil.copy2(Path(__file__).with_name(name), project / name)
        source = ROOT / 'art_source/actors/hero_walk_trial_v1'
        for name in ['candidate.png', 'review.json']:
            shutil.copy2(source / name, project / name)
        shutil.copy2(ROOT / 'assets/art_pilot/hero.png', project / 'reference.png')
        (project / 'project.godot').write_text('''config_version=5
[application]
config/name="MotionReview-Isolated"
run/main_scene="res://Main.tscn"
[display]
window/size/viewport_width=1280
window/size/viewport_height=800
window/stretch/mode="canvas_items"
[rendering]
renderer/rendering_method="gl_compatibility"
''')
        (project / 'Main.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://main.gd" id="1"]\n[node name="Review" type="Node2D"]\nscript = ExtResource("1")\n')
        imported = subprocess.run([godot, '--headless', '--editor', '--path', temp, '--quit'], capture_output=True, text=True, timeout=60, check=True)
        if 'SCRIPT ERROR' in imported.stderr:
            raise RuntimeError(imported.stderr)
        command = [godot, '--path', temp]
        if args.verify and not args.capture:
            command += ['--headless']
        command += ['--']
        if args.verify:
            command += ['--verify']
        if args.capture:
            args.capture.mkdir(parents=True, exist_ok=True)
            command += ['--capture=' + str(args.capture.resolve())]
        if args.verify:
            result = subprocess.run(command, capture_output=True, text=True, timeout=30, check=True)
            print(result.stdout, end='')
            print(result.stderr, end='')
            if 'MOTION_REVIEW_VERIFY_OK' not in result.stdout or 'SCRIPT ERROR' in result.stderr:
                raise RuntimeError('审片工具未通过验证；此验证不代表美术质量合格')
        else:
            subprocess.run(command, check=True)


if __name__ == '__main__':
    main()
