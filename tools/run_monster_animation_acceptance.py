"""Verify the monster integration in a stable snapshot without touching player saves."""
from pathlib import Path
import argparse
import io
import json
import shutil
import subprocess
import tarfile
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
GODOT = '/Applications/Godot.app/Contents/MacOS/Godot'
OWN = [
    'scripts/entities/monster.gd', 'scripts/entities/monster_actor_art.gd',
    'scripts/entities/monster_actor_art.gd.uid', 'scripts/entities/monster_animation_library.gd',
    'scripts/entities/monster_animation_library.gd.uid', 'scripts/world/game.gd',
    'tests/MonsterAnimationTest.tscn', 'tests/monster_animation_test.gd',
    'tests/monster_animation_test.gd.uid',
]
IDS = ['elite_wolf_king', 'elite_ash_wraith', 'elite_shellback_bug', 'boss_corrupted_beast']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture', action='store_true', help='Also render the main-game review screenshot')
    args = parser.parse_args()
    name = 'DegenerateAge-MonsterAcceptance-' + uuid.uuid4().hex[:10]
    user = Path.home() / 'Library/Application Support/Godot/app_userdata' / name
    try:
        with tempfile.TemporaryDirectory(prefix='degenerateage-monster-acceptance-') as directory:
            project = Path(directory)
            snapshot = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
            archive = subprocess.check_output(['git', 'archive', snapshot, '--', 'project.godot', 'icon.svg',
                                              'autoload', 'data', 'scenes', 'scripts', 'assets', 'tests'], cwd=ROOT)
            with tarfile.open(fileobj=io.BytesIO(archive)) as package:
                package.extractall(project, filter='data')
            for relative in OWN:
                target = project / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / relative, target)
            for monster in IDS:
                for item in (ROOT / 'assets/sprites/monsters' / monster).iterdir():
                    if item.suffix not in {'.png', '.json'}:
                        continue
                    target = project / item.relative_to(ROOT)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(item, target)
            config = (project / 'project.godot').read_text().replace(
                'config/name="末法纪元：最后的守护者"', f'config/name="{name}"', 1)
            assert f'config/name="{name}"' in config, 'Refuse to run against a non-isolated user directory'
            (project / 'project.godot').write_text(config)
            tests = ['MonsterAnimationTest', 'BossReviewTest', 'SkillCombatTest', 'ChapterOneAcceptance']
            checks = [['--headless', '--editor', '--quit']]
            checks += [['--headless', '--scene', f'res://tests/{test}.tscn', '--quit-after', '360'] for test in tests]
            if args.capture:
                checks.append(['--resolution', '1280x800', '--scene', 'res://tests/MonsterAnimationTest.tscn',
                               '--quit-after', '180'])
            evidence = []
            for options in checks:
                result = subprocess.run([GODOT, '--path', str(project), *options], capture_output=True,
                                        text=True, timeout=120)
                log = result.stdout + result.stderr
                selected = [line for line in log.splitlines() if 'PASS' in line or 'FAIL' in line or '全部通过' in line]
                print('\n'.join(selected), flush=True)
                evidence.extend(selected)
                if result.returncode or 'SCRIPT ERROR:' in log or 'FAIL' in log:
                    print(log[-4000:])
                    return 1
            output = ROOT / 'docs/素材/monsters/接入验收'
            output.mkdir(parents=True, exist_ok=True)
            (output / '快照测试记录.json').write_text(json.dumps({
                'snapshot': snapshot, 'overlay': OWN + ['assets/sprites/monsters/' + monster for monster in IDS],
                'results': evidence, 'player_saves': 'isolated random user directory; autosave disabled',
            }, ensure_ascii=False, indent=2) + '\n')
            if args.capture:
                shutil.copy2('/tmp/degenerateage_monster_animation_integration.png', output / '游戏实机.png')
            return 0
    finally:
        if user.exists():
            shutil.rmtree(user)


if __name__ == '__main__':
    raise SystemExit(main())
