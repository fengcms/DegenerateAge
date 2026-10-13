"""Render and validate the orthographic cave planning diagram (stdlib only)."""

import json
import math
from collections import deque
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/素材设计/样板/腐化源头洞穴布局-v2"
DATA = json.loads((ROOT / "data/cave_layout.json").read_text())
SIZE = 50


def walkable(x, y):
    px, py = x + 0.5, y + 0.5
    for chamber in DATA["chambers"]:
        cx, cy = chamber["center"]
        rx, ry = chamber["radius"]
        if ((px - cx) / rx) ** 2 + ((py - cy) / ry) ** 2 <= 1:
            return True
    for passage in DATA["passages"]:
        for (ax, ay), (bx, by) in zip(passage["points"], passage["points"][1:]):
            length_sq = (bx - ax) ** 2 + (by - ay) ** 2
            t = max(0, min(1, ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / length_sq))
            if math.hypot(px - ax - t * (bx - ax), py - ay - t * (by - ay)) <= passage["width"] / 2:
                return True
    return False


def validate():
    assert DATA["grid_size"] == [SIZE, SIZE]
    points = DATA["points"]
    for name, (x, y) in points.items():
        assert 0 <= x < SIZE and 0 <= y < SIZE and walkable(x, y), name
    start = tuple(points["ash_entrance"])
    queue = deque([start])
    seen = {start}
    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            p = (nx, ny)
            if 0 <= nx < SIZE and 0 <= ny < SIZE and p not in seen and walkable(nx, ny):
                seen.add(p)
                queue.append(p)
    for name, point in points.items():
        assert tuple(point) in seen, f"unreachable: {name}"
    total = sum(walkable(x, y) for y in range(SIZE) for x in range(SIZE))
    assert len(seen) == total, "disconnected cave floor"
    print(f"Cave layout: {len(seen)} reachable cells ({total / SIZE**2:.1%} floor); all key points connected")


def render():
    # The green shape itself is the traversable cave, surrounded by black void.
    floor = []
    for y in range(SIZE):
        for x in range(SIZE):
            if walkable(x, y):
                floor.append(f'<rect x="{285 + 8.6 * x:.1f}" y="{285 + 8.6 * y:.1f}" width="8.6" height="8.6"/>')
    dots = []
    for name in ("ash_exit", "future_exit"):
        x, y = DATA["points"][name]
        dots.append(f'<circle cx="{285 + 8.6 * (x + 0.5):.1f}" cy="{285 + 8.6 * (y + 0.5):.1f}" r="15.5"/>')
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">
<rect width="1000" height="1000" fill="#ffffff"/>
<polygon points="500,55 945,500 500,945 55,500" fill="#000000"/>
<g fill="#00ef21">{''.join(floor)}</g>
<g fill="#ff0000">{''.join(dots)}</g>
</svg>
'''
    (OUT / "洞穴行走草图.svg").write_text(svg)


def compile_rows():
    DATA["walkable_rows"] = ["".join("1" if walkable(x, y) else "0" for x in range(SIZE)) for y in range(SIZE)]
    (ROOT / "data/cave_layout.json").write_text(json.dumps(DATA, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    validate()
    compile_rows()
    render()
