"""隔离启动真实营地战斗样板；复制代码、数据和资产，仅使用随机user://并在退出清理。"""
from pathlib import Path
import argparse
import importlib.util
import os
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]


def main():
    """创建独立项目与存档身份，导入后运行交互或完整战斗验收；任何脚本错误拒绝通过。"""
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--controls', action='store_true')
    parser.add_argument('--route', action='store_true')
    parser.add_argument('--verify-route', action='store_true')
    parser.add_argument('--stress-route', action='store_true')
    parser.add_argument('--soak', action='store_true')
    parser.add_argument('--review', action='store_true')
    parser.add_argument('--capture', type=Path)
    args = parser.parse_args()
    if args.stress_route:
        if args.capture:
            parser.error('--stress-route 不与截图并用')
        args.verify_route = True
    if args.verify_route:
        args.route = True
        args.verify = True
    if args.route and (args.controls or args.soak or args.review):
        parser.error('--route 不可与controls/soak/review组合')
    if args.controls:
        if args.soak or args.review:
            parser.error('--controls 不可与soak/review组合')
        args.verify = True
    if args.review and (not args.capture or args.verify or args.soak):
        parser.error('--review 需独立配合 --capture 输出目录')
    if args.soak and (args.verify or args.capture):
        parser.error('--soak 必须独立运行，避免截图/无窗口影响性能样本')
    spec = importlib.util.spec_from_file_location('isolated', ROOT / 'tools/run_isolated_tests.py')
    isolated = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(isolated)
    name = 'DegenerateAge-Test-' + uuid.uuid4().hex[:12]
    godot = str(isolated.find_godot())
    try:
        with tempfile.TemporaryDirectory(prefix='camp-combat-') as temp:
            project = Path(temp)
            for item in ROOT.iterdir():
                if item.name.startswith('.') or item.name in {'project.godot','build','docs','art_source','tools'}:
                    continue
                if item.name in {'scripts','autoload','data','scenes','tests','addons','assets'}:
                    shutil.copytree(item, project / item.name)
                else:
                    (project / item.name).symlink_to(item, target_is_directory=item.is_dir())
            for folder in ['modular_camp','camp_combat']:
                shutil.copytree(ROOT / 'tools' / folder, project / 'tools' / folder,
                                ignore=shutil.ignore_patterns('__pycache__','benchmark.gd','benchmark.gd.uid'))
            for filename in ['layouts.json','actors.json','reveal.gdshader']:
                shutil.copy2(ROOT / 'tools/modular_camp' / filename, project / filename)
            if args.route:
                shutil.copy2(ROOT / 'tools/camp_combat/route_layout.json', project / 'layouts.json')
            config = (ROOT / 'project.godot').read_text().replace('config/name="末法纪元：最后的守护者"', f'config/name="{name}"', 1)
            assert f'config/name="{name}"' in config
            (project / 'project.godot').write_text(config)
            (project / 'Combat.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tools/camp_combat/main.gd" id="1"]\n[node name="Combat" type="Node2D"]\nscript = ExtResource("1")\n')
            if args.route:
                scene = project / 'Combat.tscn'
                scene.write_text(scene.read_text().replace('camp_combat/main.gd','camp_combat/stress.gd' if args.stress_route else 'camp_combat/route.gd'))
            if args.controls:
                scene = project / 'Combat.tscn'
                scene.write_text(scene.read_text().replace('camp_combat/main.gd','camp_combat/controls.gd'))
            if args.review:
                scene = project / 'Combat.tscn'
                scene.write_text(scene.read_text().replace('camp_combat/main.gd','camp_combat/review.gd'))
            env = dict(os.environ, DEGENERATE_CAMP_ISOLATED='1')
            imported = subprocess.run([godot,'--headless','--editor','--path',temp,'--quit'], capture_output=True,text=True,timeout=180,env=env)
            if imported.returncode or 'SCRIPT ERROR' in imported.stderr:
                raise RuntimeError(imported.stdout[-3000:]+imported.stderr[-6000:])
            # UID归属源码；首次导入生成后复制回工具目录，不修改正式游戏资源。
            for uid in (project / 'tools/camp_combat').glob('*.gd.uid'):
                target = ROOT / 'tools/camp_combat' / uid.name
                if not target.exists():
                    shutil.copy2(uid,target)
            command = [godot,'--path',temp,'--scene','res://Combat.tscn','--max-fps','120','--log-file',str(project / 'runtime.log')]
            if args.verify and not args.capture and not args.stress_route:
                command.append('--headless')
            command.append('--')
            if args.verify:
                command.append('--verify-route' if args.route else '--verify-combat')
            if args.soak:
                command.append('--soak-combat')
            if args.capture:
                args.capture.mkdir(parents=True,exist_ok=True)
                command.append('--capture='+str(args.capture.resolve()))
            if args.verify or args.soak or args.review:
                try:
                    result = subprocess.run(command, capture_output=True,text=True,timeout=360 if args.soak or args.route else 120,env=env)
                except subprocess.TimeoutExpired as error:
                    print(error.stdout or b'')
                    print(error.stderr or b'')
                    raise
                print(result.stdout)
                print(result.stderr)
                marker = 'CAMP_ROUTE_STRESS_OK' if args.stress_route else 'CAMP_ROUTE_OK' if args.route else 'CAMP_CONTROLS_OK' if args.controls else 'CAMP_ART_REVIEW_OK' if args.review else 'CAMP_COMBAT_VERIFY_OK'
                if result.returncode or 'SCRIPT ERROR' in result.stderr or marker not in result.stdout or (args.soak and 'CAMP_COMBAT_SOAK_OK' not in result.stdout):
                    raise RuntimeError('真实战斗验收未完整通过')
            else:
                subprocess.run(command,check=True,env=env)
    finally:
        shutil.rmtree(isolated.isolated_user_data(name),ignore_errors=True)


if __name__ == '__main__':
    main()
