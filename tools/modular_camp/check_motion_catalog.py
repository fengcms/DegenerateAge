"""核对隔离营地主角动作覆盖与运行图集规格；只读文件，不加载正式游戏或存档。"""
from pathlib import Path
import json
import struct

ROOT = Path(__file__).resolve().parents[2]
DIRECTIONS = ('se', 'ne', 'sw', 'nw', 's', 'n', 'e', 'w')


def read_spec(path):
    """读取标准 JSON 清单；缺文件或无效格式直接失败，不能静默回退。"""
    return json.loads(path.read_text())


def check_png(path, expected):
    """只读 PNG 文件头核对实际尺寸，不解码或复制纹理。"""
    with path.open('rb') as stream:
        header = stream.read(24)
    assert header[:8] == b'\x89PNG\r\n\x1a\n' and header[12:16] == b'IHDR', path
    assert struct.unpack('>II', header[16:24]) == tuple(expected), path


def main():
    """核对八向站走及已接入单次动作；输出缺稿矩阵与 RGBA8 理论成本。"""
    assets = ROOT / 'assets/art_pilot'
    source = ROOT / 'art_source/actors'
    walk = read_spec(assets / 'hero_walk_se_v3.json')
    assert walk['directions'] == list(DIRECTIONS)
    assert walk['idleDirections'] == list(DIRECTIONS)
    assert walk['frameSize'] == [112, 128] and walk['pivot'] == [56, 112]
    versions = {'se': 'v3', 'ne': 'v2', 'nw': 'v2'}
    coverage = {direction: {'idle', 'walk'} for direction in DIRECTIONS}
    total = 0
    launcher = (Path(__file__).with_name('launch.py')).read_text()
    for direction in DIRECTIONS:
        for state, height, version in [('walk', 512, versions.get(direction, 'v1')), ('idle', 128, 'v3')]:
            name = f'hero_{state}_{direction}_{version}.png'
            check_png(assets / name, (112, height))
            assert name in launcher, f'隔离启动未包含 {name}'
            total += 112 * height * 4
    for state, directions in [('attack', ('se', 'ne', 'sw', 'nw')), ('hit', ('se',)), ('death', ('se',))]:
        for direction in directions:
            stem = f'hero_{state}_{direction}_v1'
            spec = read_spec(assets / f'{stem}.json')
            original = read_spec(source / f'hero_{state}_{direction}_trial_v1/build.json')
            assert spec == original, f'源清单与运行清单不同步：{stem}'
            assert spec['state'] == state and spec['direction'] == direction
            assert spec['frames'] == 4 and not spec['loop']
            assert spec['frameSize'] == walk['frameSize'] and spec['pivot'] == walk['pivot']
            assert len(spec['frameSeconds']) == 4 and all(t > 0 for t in spec['frameSeconds'])
            if state != 'attack':
                assert spec['holdLast'] == (state == 'death')
            check_png(assets / f'{stem}.png', (112, 512))
            assert f'{stem}.png' in launcher and f'{stem}.json' in launcher, stem
            total += 112 * 512 * 4
            coverage[direction].add(state)
    print('方向  待机 行走 攻击 受击 倒地（✓已接入，—缺稿）')
    for direction, states in coverage.items():
        print(direction.ljust(5), '  '.join('✓' if state in states else '—' for state in ('idle', 'walk', 'attack', 'hit', 'death')))
    print(f'HERO_MOTION_CATALOG_OK: {total // 1024} KiB RGBA8（仅主角动作，不含原图与怪物）')


if __name__ == '__main__':
    main()
