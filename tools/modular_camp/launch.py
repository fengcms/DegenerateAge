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
    parser.add_argument('--build-assets', action='store_true')
    parser.add_argument('--capture', type=Path)
    args = parser.parse_args()
    godot = shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot'
    with tempfile.TemporaryDirectory(prefix='modular-camp-') as temp:
        project = Path(temp)
        for source in list(Path(__file__).parent.glob('*.gd')) + list(Path(__file__).parent.glob('*.gdshader')):
            shutil.copy2(source, project / source.name)
        for relative in ['scripts/systems/iso.gd', 'scripts/systems/flat_tile_mesh.gd', 'scripts/world/cave_layout.gd']:
            shutil.copy2(ROOT / relative, project / Path(relative).name)
        for filename in ['layouts.json', 'actors.json']:
            shutil.copy2(Path(__file__).with_name(filename), project / filename)
        if args.build_assets:
            (project / 'project.godot').write_text('config_version=5\n')
            built = subprocess.run([godot, '--headless', '--path', temp, '--script', 'build_assets.gd', '--', str(ROOT)], check=True, capture_output=True, text=True, timeout=60)
            print(built.stdout, end='')
            print(built.stderr, end='')
            if any('MONSTER_'+state+'_BUILT' not in built.stdout for state in ['WALK','HIT','DEATH']) or 'HERO_REACTIONS_BUILT' not in built.stdout or 'MONSTER_ATTACK_BUILT' not in built.stdout or 'HERO_ATTACK_BUILT' not in built.stdout or 'MODULAR_ASSETS_BUILT' not in built.stdout or 'HERO_WALK_BUILT' not in built.stdout or 'MONSTER_IDLE_BUILT' not in built.stdout or 'CAMP_SUPPLIES_BUILT' not in built.stdout or 'SCRIPT ERROR' in built.stderr:
                raise RuntimeError('素材构建未完整成功')
            return
        for relative in ['assets/art_pilot/hero_hit_e_v1.png', 'assets/art_pilot/hero_hit_e_v1.json', 'assets/art_pilot/hero_death_e_v1.png', 'assets/art_pilot/hero_death_e_v1.json', 'assets/art_pilot/hero_hit_w_v1.png', 'assets/art_pilot/hero_hit_w_v1.json', 'assets/art_pilot/hero_death_w_v1.png', 'assets/art_pilot/hero_death_w_v1.json', 'assets/art_pilot/hero_hit_sw_v1.png', 'assets/art_pilot/hero_hit_sw_v1.json', 'assets/art_pilot/hero_death_sw_v1.png', 'assets/art_pilot/hero_death_sw_v1.json', 'assets/art_pilot/hero_hit_nw_v1.png', 'assets/art_pilot/hero_hit_nw_v1.json', 'assets/art_pilot/hero_death_nw_v1.png', 'assets/art_pilot/hero_death_nw_v1.json', 'assets/art_pilot/hero_hit_s_v1.png', 'assets/art_pilot/hero_hit_s_v1.json', 'assets/art_pilot/hero_death_s_v1.png', 'assets/art_pilot/hero_death_s_v1.json', 'assets/art_pilot/hero_hit_n_v1.png', 'assets/art_pilot/hero_hit_n_v1.json', 'assets/art_pilot/hero_death_n_v1.png', 'assets/art_pilot/hero_death_n_v1.json', 'assets/art_pilot/hero_hit_ne_v1.png', 'assets/art_pilot/hero_hit_ne_v1.json', 'assets/art_pilot/hero_death_ne_v1.png', 'assets/art_pilot/hero_death_ne_v1.json', 'assets/art_pilot/wolf_walk_v1.png', 'assets/art_pilot/wolf_walk_v1.json', 'assets/art_pilot/wolf_hit_v1.png', 'assets/art_pilot/wolf_hit_v1.json', 'assets/art_pilot/wolf_death_v1.png', 'assets/art_pilot/wolf_death_v1.json', 'assets/art_pilot/beetle_walk_v1.png', 'assets/art_pilot/beetle_walk_v1.json', 'assets/art_pilot/beetle_hit_v1.png', 'assets/art_pilot/beetle_hit_v1.json', 'assets/art_pilot/beetle_death_v1.png', 'assets/art_pilot/beetle_death_v1.json', 'assets/art_pilot/hero_attack_s_v1.png', 'assets/art_pilot/hero_attack_s_v1.json', 'assets/art_pilot/hero_attack_n_v1.png', 'assets/art_pilot/hero_attack_n_v1.json', 'assets/art_pilot/hero_attack_e_v1.png', 'assets/art_pilot/hero_attack_e_v1.json', 'assets/art_pilot/hero_attack_w_v1.png', 'assets/art_pilot/hero_attack_w_v1.json', 'assets/art_pilot/hero_attack_nw_v1.png', 'assets/art_pilot/hero_attack_nw_v1.json', 'assets/art_pilot/hero_attack_sw_v1.png', 'assets/art_pilot/hero_attack_sw_v1.json', 'assets/art_pilot/hero_attack_ne_v1.png', 'assets/art_pilot/hero_attack_ne_v1.json', 'assets/art_pilot/beetle_attack_v1.png', 'assets/art_pilot/beetle_attack_v1.json', 'assets/art_pilot/wolf_attack_v1.png', 'assets/art_pilot/wolf_attack_v1.json', 'assets/art_pilot/beetle_idle_v1.png', 'assets/art_pilot/beetle_idle_v1.json', 'assets/art_pilot/wolf_idle_v1.png', 'assets/art_pilot/wolf_idle_v1.json', 'assets/art_pilot/hero_walk_nw_v2.png', 'assets/art_pilot/hero_idle_nw_v3.png', 'assets/art_pilot/hero_attack_se_v1.png', 'assets/art_pilot/hero_attack_se_v1.json', 'assets/art_pilot/hero_walk_s_v1.png', 'assets/art_pilot/hero_idle_s_v3.png', 'assets/art_pilot/hero_walk_n_v1.png', 'assets/art_pilot/hero_idle_n_v3.png', 'assets/art_pilot/hero_walk_e_v1.png', 'assets/art_pilot/hero_idle_e_v3.png', 'assets/art_pilot/hero_walk_w_v1.png', 'assets/art_pilot/hero_idle_w_v3.png', 'assets/art_pilot/hero_hit_se_v1.png', 'assets/art_pilot/hero_hit_se_v1.json', 'assets/art_pilot/hero_death_se_v1.png', 'assets/art_pilot/hero_death_se_v1.json', 'assets/art_pilot/hero.png', 'assets/art_pilot/wolf.png', 'assets/art_pilot/beetle_v2.png', 'assets/art_pilot/hero_walk_sw_v1.png', 'assets/art_pilot/hero_idle_sw_v3.png', 'assets/art_pilot/hero_walk_ne_v2.png', 'assets/art_pilot/hero_walk_se_v3.png', 'assets/art_pilot/hero_idle_se_v3.png', 'assets/art_pilot/hero_idle_ne_v3.png', 'assets/art_pilot/hero_walk_se_v3.json']:
            destination = project / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, destination)
        shutil.copytree(ROOT / 'assets/environment/camp_modular_v1', project / 'assets/environment/camp_modular_v1')
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
        imported = subprocess.run([godot, '--headless', '--editor', '--path', temp, '--quit'], check=True, capture_output=True, text=True, timeout=60)
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
            try:
                # 八向攻击、两怪反应及逐方向主角反应增加固定验收时长；各阶段仍保留原局部截止与断言。
                result = subprocess.run(command, check=True, timeout=240, capture_output=True, text=True)
            except subprocess.TimeoutExpired as error:
                print(error.stdout or b'')
                print(error.stderr or b'')
                raise
            print(result.stdout, end='')
            print(result.stderr, end='')
            if 'MODULAR_CAMP_VERIFY_OK' not in result.stdout or 'SCRIPT ERROR' in result.stderr:
                raise RuntimeError('样板未输出成功标记或出现脚本错误')
        else:
            subprocess.run(command, check=True)


if __name__ == '__main__':
    main()
