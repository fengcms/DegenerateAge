"""生成法师 6 条技能的占位图标（48×48 RGBA，透明背景）。

为什么需要这个脚本：工程 98 加法师时只写了 `skills.json` 的 `icon` 路径，**没有画图**。
后果不是报错，而是技能面板整行空白 + 快捷栏槽位没图标 —— 玩家看到「6 个空按钮」，
而 `--import` / 配置校验 / 契约测试全绿（`SkillProgressionTest` 只查 id 与阶数）。
`--all` 里的 `IconIntegrationTest` 是唯一会碰到这条路径的用例。

风格对齐现有 6 张武士图标：**24×24 像素画 ×2 最近邻放大到 48×48**、透明底、深色描边。
本脚本是**可重跑**的（改配色 / 改形状后重跑即可，输出确定、无随机），符合「生成器必须能
重现产物」那条规矩。真实美术到位后请删除本脚本并把图标换成成品。

跑法：python3 tools/build_mage_skill_icons.py
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets/sprites/skills"

## 画布按 24×24 设计再 ×2 放大 —— 与既有图标同一像素密度。
GRID = 24
SCALE = 2

CLEAR = (0, 0, 0, 0)
OUTLINE = (18, 20, 30, 235)


def new_image() -> list[list[tuple[int, int, int, int]]]:
    return [[CLEAR for _ in range(GRID)] for _ in range(GRID)]


def put(img, x: int, y: int, color) -> None:
    if 0 <= x < GRID and 0 <= y < GRID:
        img[y][x] = color


def disc(img, cx: float, cy: float, radius: float, color) -> None:
    r2 = radius * radius
    for y in range(GRID):
        for x in range(GRID):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r2:
                img[y][x] = color


def ring(img, cx: float, cy: float, radius: float, thickness: float, color) -> None:
    outer = radius * radius
    inner = max(0.0, radius - thickness) ** 2
    for y in range(GRID):
        for x in range(GRID):
            d = (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2
            if inner <= d <= outer:
                img[y][x] = color


def rect(img, x0: int, y0: int, x1: int, y1: int, color) -> None:
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(img, x, y, color)


def line(img, x0: int, y0: int, x1: int, y1: int, color, brush: int = 1) -> None:
    """Bresenham + 方形笔刷；像素画里够用，且结果完全确定。"""
    dx, dy = abs(x1 - x0), abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx - dy
    x, y = x0, y0
    while True:
        for oy in range(brush):
            for ox in range(brush):
                put(img, x + ox, y + oy, color)
        if x == x1 and y == y1:
            break
        e2 = err * 2
        if e2 > -dy:
            err -= dy
            x += sx
        if e2 < dx:
            err += dx
            y += sy


def triangle(img, apex, left, right, color) -> None:
    """实心三角形（用在火焰 / 冰锥这类方向性图形上）。"""
    ax, ay = apex
    lx, ly = left
    rx, ry = right
    min_y = max(0, min(ay, ly, ry))
    max_y = min(GRID - 1, max(ay, ly, ry))
    for y in range(min_y, max_y + 1):
        xs = []
        for (x0, y0), (x1, y1) in (((ax, ay), (lx, ly)), ((lx, ly), (rx, ry)), ((rx, ry), (ax, ay))):
            if y0 == y1:
                if y == y0:
                    xs += [x0, x1]
                continue
            if min(y0, y1) <= y <= max(y0, y1):
                t = (y - y0) / (y1 - y0)
                xs.append(round(x0 + (x1 - x0) * t))
        if len(xs) >= 2:
            for x in range(min(xs), max(xs) + 1):
                put(img, x, y, color)


def add_outline(img) -> None:
    """给不透明像素补一圈深色描边，颜色与既有图标一致。"""
    marked = []
    for y in range(GRID):
        for x in range(GRID):
            if img[y][x][3] != 0:
                continue
            for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + ox, y + oy
                if 0 <= nx < GRID and 0 <= ny < GRID and img[ny][nx][3] > 120:
                    marked.append((x, y))
                    break
    for x, y in marked:
        img[y][x] = OUTLINE


# ---- 六张图标 ----

def icon_basic_fireball(img) -> None:
    """火球术：亮橙球 + 黄色内核 + 左下拖尾。"""
    disc(img, 13.5, 11.5, 7.0, (214, 78, 32, 255))
    disc(img, 13.5, 11.5, 5.2, (255, 150, 46, 255))
    disc(img, 13.5, 11.5, 2.8, (255, 232, 150, 255))
    for i, (x, y) in enumerate(((6, 17), (4, 19), (7, 20))):
        put(img, x, y, (255, 168, 70, 200 - i * 40))
        put(img, x + 1, y, (255, 120, 50, 160 - i * 40))


def icon_lightning(img) -> None:
    """雷电术：青白折线 + 冷色辉光。"""
    pts = [(14, 2), (9, 11), (13, 11), (8, 21)]
    for i in range(len(pts) - 1):
        line(img, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], (86, 176, 240, 255), 2)
    line(img, 14, 2, 10, 10, (206, 240, 255, 255), 1)
    line(img, 10, 11, 8, 20, (206, 240, 255, 255), 1)
    for x, y in ((16, 6), (6, 14), (15, 18)):
        put(img, x, y, (140, 214, 255, 120))


def icon_flame_burst(img) -> None:
    """火焰喷发：正向火苗 + 脚下扇形。"""
    triangle(img, (11, 3), (4, 16), (18, 16), (208, 74, 30, 255))
    triangle(img, (11, 7), (7, 16), (15, 16), (255, 158, 52, 255))
    triangle(img, (11, 10), (9, 16), (13, 16), (255, 236, 168, 255))
    for x in range(3, 20):
        if x in (3, 19):
            continue
        put(img, x, 18, (255, 186, 90, 210))
    put(img, 3, 18, (255, 186, 90, 120))
    put(img, 19, 18, (255, 186, 90, 120))


def icon_magic_shield(img) -> None:
    """魔法盾：六边形轮廓 + 内侧微光。"""
    import math

    cx, cy, r = 11.5, 12.5, 8.0
    pts = [(round(cx + r * math.cos(math.radians(60 * i - 90))),
            round(cy + r * math.sin(math.radians(60 * i - 90)))) for i in range(6)]
    pts.append(pts[0])
    for i in range(len(pts) - 1):
        line(img, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], (96, 160, 240, 255), 2)
    triangle(img, (11, 7), (6, 15), (17, 15), (128, 190, 255, 90))
    put(img, 11, 9, (226, 240, 255, 220))
    put(img, 11, 10, (226, 240, 255, 220))
    put(img, 10, 12, (196, 226, 255, 170))
    put(img, 12, 12, (196, 226, 255, 170))


def icon_frost_roar(img) -> None:
    """冰咆哮：向右扩散的冰锥 + 碎冰点。"""
    triangle(img, (4, 11), (17, 5), (17, 18), (108, 186, 236, 255))
    triangle(img, (6, 11), (16, 8), (16, 15), (186, 234, 255, 255))
    line(img, 7, 11, 16, 11, (240, 252, 255, 230), 1)
    for x, y in ((19, 4), (20, 9), (19, 15), (18, 20), (21, 12)):
        put(img, x, y, (166, 222, 250, 200))


def icon_meteor(img) -> None:
    """陨石术：暗色石核 + 亮的熔金边缘 + 右上拖尾。"""
    disc(img, 12.5, 14.5, 6.4, (74, 62, 66, 255))
    disc(img, 12.5, 14.5, 4.4, (104, 88, 92, 255))
    ring(img, 12.5, 14.5, 6.4, 1.8, (255, 132, 48, 255))
    for x, y in ((10, 12), (14, 16), (13, 11)):
        put(img, x, y, (58, 48, 52, 255))
    line(img, 17, 9, 21, 3, (255, 150, 60, 220), 1)
    line(img, 18, 10, 22, 5, (255, 96, 40, 150), 1)


ICONS = {
    "basic_fireball": icon_basic_fireball,
    "lightning": icon_lightning,
    "flame_burst": icon_flame_burst,
    "magic_shield": icon_magic_shield,
    "frost_roar": icon_frost_roar,
    "meteor": icon_meteor,
}


def to_png(img) -> bytes:
    """24×24 → 48×48 最近邻放大，再编码成 PNG（无第三方依赖）。

    🔴 放大只做两步，别把整行再乘一次：
    ① 横向：`bytes(pixel) * SCALE` 把 1 个像素复制成 SCALE 个；
    ② 纵向：**整条扫描行（含 filters 字节）** 重复 SCALE 次。
    早期版本把 `bytes(row) * SCALE` 写在 ① 之后，结果是「横向乘了两次（384 字节/行，
    而 48 宽只需 192）+ 只有 24 个扫描行（48 高需要 48 个）」—— PNG 结构非法，
    `file` 照样识别成 48×48 RGBA，Godot 却建不出 `.ctex`：`.import` 里 `valid=false`、
    `--import` 不报错、`preload` 到运行时才炸。判据不是「文件多大」，是
    `zlib.decompress(IDAT)` 的长度 == height * (1 + width * 4)。
    """
    raw = bytearray()
    for y in range(GRID):
        row = bytearray()
        for x in range(GRID):
            row += bytes(img[y][x]) * SCALE
        raw += (b"\x00" + bytes(row)) * SCALE
    size = GRID * SCALE
    assert len(raw) == size * (1 + size * 4), \
        f"PNG 原始数据长度不对：{len(raw)}，应为 {size * (1 + size * 4)}"

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for skill_id, draw in ICONS.items():
        img = new_image()
        draw(img)
        add_outline(img)
        path = OUT_DIR / f"{skill_id}.png"
        path.write_bytes(to_png(img))
        print(f"[ICON] {path.relative_to(ROOT)}")
    print("生成完毕：6 张 48×48 RGBA 占位图标 ✅")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
