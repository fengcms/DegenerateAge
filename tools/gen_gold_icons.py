#!/usr/bin/env python3
"""生成金条 / 金砖的 48×48 占位图标（工程 109）。

用途：功能落地不阻塞美术。等正式图标到齐时，**用同名文件覆盖**即可，
`SampleArt.ICONS` 的路径不用改。

风格与同目录其他物品图一致：48×48、透明底、硬边像素、无抗锯齿
（运行时用最近邻过滤，见 assets/sprites/items/README.md）。

用法：python3 tools/gen_gold_icons.py
"""

import os
import struct
import zlib

SIZE = 48
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sprites", "items")

OUTLINE = (92, 61, 13, 255)
GOLD_HI = (255, 233, 168, 255)
GOLD_MID = (217, 164, 65, 255)
GOLD_TOP = (242, 205, 106, 255)
GOLD_DARK = (169, 116, 28, 255)


def canvas():
    return [[(0, 0, 0, 0) for _ in range(SIZE)] for _ in range(SIZE)]


def put(px, x, y, color):
    if 0 <= x < SIZE and 0 <= y < SIZE:
        px[y][x] = color


def fill_rect(px, x0, y0, x1, y1, color):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(px, x, y, color)


def fill_poly(px, points, color):
    ys = [p[1] for p in points]
    for y in range(min(ys), max(ys) + 1):
        xs = []
        for i in range(len(points)):
            ax, ay = points[i]
            bx, by = points[(i + 1) % len(points)]
            if ay == by:
                continue
            if min(ay, by) <= y < max(ay, by):
                t = (y - ay) / float(by - ay)
                xs.append(ax + (bx - ax) * t)
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            for x in range(int(round(xs[i])), int(round(xs[i + 1])) + 1):
                put(px, x, y, color)


def stroke_poly(px, points, color):
    """四点以上的多边形描边走像素线（仅用于横平竖直 + 单段斜边的造型）。"""
    for i in range(len(points)):
        ax, ay = points[i]
        bx, by = points[(i + 1) % len(points)]
        steps = max(abs(bx - ax), abs(by - ay), 1)
        for s in range(steps + 1):
            t = s / float(steps)
            put(px, int(round(ax + (bx - ax) * t)), int(round(ay + (by - ay) * t)), color)


def write_png(path, px):
    raw = b"".join(b"\x00" + bytes(c for p in row for c in p) for row in px)

    def chunk(tag, data):
        body = struct.pack(">I", len(data)) + tag + data
        return body + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


def make_ingot():
    """金条：上窄下宽的梯形，顶面高光 + 一道压印。"""
    px = canvas()
    body = [(15, 17), (33, 17), (39, 31), (9, 31)]
    fill_poly(px, body, GOLD_MID)
    # 顶面（亮）
    fill_poly(px, [(15, 17), (33, 17), (35, 22), (13, 22)], GOLD_TOP)
    # 左上棱高光
    fill_poly(px, [(15, 17), (33, 17), (33, 19), (15, 19)], GOLD_HI)
    # 底面阴影
    fill_poly(px, [(10, 29), (38, 29), (39, 31), (9, 31)], GOLD_DARK)
    # 压印：中间一条短横线
    fill_rect(px, 19, 25, 29, 26, GOLD_DARK)
    stroke_poly(px, body, OUTLINE)
    return px


def make_brick():
    """金砖：立方体（顶面 + 正面 + 右侧面），比金条更"厚"。"""
    px = canvas()
    top = [(10, 20), (17, 12), (43, 12), (36, 20)]
    front = [(10, 20), (36, 20), (36, 36), (10, 36)]
    side = [(36, 20), (43, 12), (43, 28), (36, 36)]
    fill_poly(px, front, GOLD_MID)
    fill_poly(px, side, GOLD_DARK)
    fill_poly(px, top, GOLD_TOP)
    # 顶面高光条
    fill_poly(px, [(17, 12), (43, 12), (42, 14), (16, 14)], GOLD_HI)
    # 正面压印
    fill_rect(px, 14, 26, 32, 27, GOLD_DARK)
    fill_rect(px, 14, 30, 32, 31, GOLD_DARK)
    stroke_poly(px, top, OUTLINE)
    stroke_poly(px, front, OUTLINE)
    stroke_poly(px, side, OUTLINE)
    return px


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    write_png(os.path.join(OUT_DIR, "gold_ingot.png"), make_ingot())
    write_png(os.path.join(OUT_DIR, "gold_brick.png"), make_brick())
    print("已生成 gold_ingot.png / gold_brick.png（48×48）")


if __name__ == "__main__":
    main()
