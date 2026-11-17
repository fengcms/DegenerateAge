"""隔离启动模块化营地结构样板，复用现有投影、合批和导航源码，不访问游戏存档。"""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    """创建临时Godot项目，运行导入及窗口/自动验证，退出后删除缓存。"""
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--capture', type=Path)
    args = parser.parse_args()
    godot = shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot'
    with tempfile.TemporaryDirectory(prefix='modular-camp-') as temp:
        project = Path(temp)
        for source in Path(__file__).parent.glob('*.gd'):
            shutil.copy2(source, project / source.name)
        for relative in ['scripts/systems/iso.gd', 'scripts/systems/flat_tile_mesh.gd', 'scripts/world/cave_layout.gd']:
            shutil.copy2(ROOT / relative, project / Path(relative).name)
        shutil.copy2(Path(__file__).with_name('layouts.json'), project / 'layouts.json')
        for relative in ['assets/tiles/camp/tile_0.png', 'assets/tiles/camp/tile_3.png', 'assets/tiles/camp/crate.png', 'assets/tiles/chapter1_v2/camp/forge_shelter.png', 'assets/tiles/chapter1_v2/wild_trial/dead_tree.png', 'assets/tiles/chapter1_v2/ash_land/ruin_wall.png', 'assets/art_pilot/hero.png']:
            destination = project / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, destination)
        (project / 'project.godot').write_text('''config_version=5
[application]
config/name="ModularCamp-Isolated"
run/main_scene="res://Main.tscn"
[display]
window/size/viewport_width=1280
window/size/viewport_height=800
window/stretch/mode="canvas_items"
[rendering]
renderer/rendering_method="gl_compatibility"
''')
        (project / 'Main.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://main.gd" id="1"]\n[node name="Sample" type="Node2D"]\nscript = ExtResource("1")\n')
        subprocess.run([godot, '--headless', '--editor', '--path', temp, '--quit'], check=True, stdout=subprocess.DEVNULL)
        command = [godot, '--path', temp]
        if args.verify and not args.capture:
            command += ['--headless']
        command += ['--']
        if args.verify:
            command += ['--verify']
        if args.capture:
            args.capture.mkdir(parents=True, exist_ok=True)
            command += ['--capture=' + str(args.capture.resolve())]
        subprocess.run(command, check=True, timeout=120 if args.verify else None)


if __name__ == '__main__':
    main()
