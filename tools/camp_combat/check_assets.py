"""只读检查两怪八方向五状态运行图集、源清单与来源记录，禁止把缺方向或同图冒充方向计为完成。"""
from pathlib import Path
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parents[2]
DIRECTIONS = ('s','sw','w','nw','n','ne','e','se')
STATES = ('idle','walk','attack','hit','death')


def main():
    """核对全部80张图集的规格、独立内容和生成记录，输出理论RGBA8成本，不替代播放验收。"""
    folder = ROOT / 'assets/art_pilot/combat_monsters_v1'
    spec = json.loads((folder / 'manifest.json').read_text())
    assert spec['frameSize'] == [128,96] and spec['pivot'] == [64,80] and spec['frames'] == 4
    count = 0
    for kind in ('wolf','beetle'):
        assert set(spec['packs'][kind]) == set(DIRECTIONS) - {'sw'}
        for state in STATES:
            hashes = set()
            for direction in DIRECTIONS:
                path = ROOT / f'assets/art_pilot/{kind}_{state}_v1.png' if direction == 'sw' else folder / spec['packs'][kind][direction][state]
                data = path.read_bytes()
                assert data[:8] == b'\x89PNG\r\n\x1a\n'
                assert struct.unpack('>II',data[16:24]) == (128,384), path
                digest = hashlib.sha256(data).hexdigest()
                assert digest not in hashes, f'同一状态不同方向重复图集：{path}'
                hashes.add(digest)
                count += 1
                if direction != 'sw':
                    source = ROOT / f'art_source/actors/{kind}_{direction}_combat_v1'
                    build = json.loads((source / 'build.json').read_text())
                    assert (source / build['source']).exists() and (source / 'prompt.json').exists()
                    assert build['frameSize'] == [128,96] and build['pivot'] == [64,80]
    print(f'COMBAT_ASSETS_OK: {count} atlases, {count*128*384*4//1024} KiB RGBA8')


if __name__ == '__main__':
    main()
