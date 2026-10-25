#!/usr/bin/env python3
"""构建 look_06 单方向二维试验的审稿产物，需要 Pillow。

输入为 art_source/player/look_06/2d_walk_pilot_v1 的两张选定源稿及既有图集。
仅裁格、固定尺度采样和排版，不绘制或补造动作；输出覆盖同目录审稿 PNG/GIF/统计。
不写 assets，不登记角色外观。运行：python3 tools/player_2d/build_look_06_walk_review.py。
"""

from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art_source/player/look_06/2d_walk_pilot_v1"
RUNTIME = ROOT / "assets/sprites/player/stage_looks/look_06"
NEAREST = Image.Resampling.NEAREST
BACKGROUND = "#25282d"


def font(size):
    """优先使用本机中文字体，缺失时明确失败，避免输出缺字审稿板。"""
    candidates = ["/System/Library/Fonts/STHeiti Light.ttc",
                  "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"]
    for name in candidates:
        if Path(name).exists():
            return ImageFont.truetype(name, size)
    raise RuntimeError("需要安装中文字体，或为审稿工具补充实际字体路径")


def opaque_copy(source):
    """按现有构建器的 0.6 alpha 门槛清除采样噪点；原始生成图保持不变。"""
    image = source.convert("RGBA").copy()
    image.putalpha(image.getchannel("A").point([255 if a >= 153 else 0 for a in range(256)]))
    return image


def existing(state, count):
    """从既有图集方向索引 1（第二列）读取 sw，行索引为时间帧。"""
    atlas = Image.open(RUNTIME / f"look_06_{state}_atlas.png").convert("RGBA")
    return [atlas.crop((64, i * 80, 128, (i + 1) * 80)) for i in range(count)]


def static_frame():
    """单张候选按 48 px 高标定一次，放入脚底锚点 (32,64) 的审稿格。"""
    image = opaque_copy(Image.open(OUT / "static_sw_source.png"))
    image = image.crop(image.getbbox())
    image = image.resize((round(image.width * 48 / image.height), 48), NEAREST)
    frame = Image.new("RGBA", (64, 80))
    frame.alpha_composite(image, (32 - image.width // 2, 16))
    frame.save(OUT / "static_sw_64x80.png")
    return frame


def walking_frames():
    """等分 4×2 源图，用全序列同一缩放系数及每排固定注册点采样。

    原图两排有排版高度差，注册点来自源图人工检查；不逐帧归一包围盒，
    不改变各帧肢体位置。注册点仅用于审稿对齐，不能证明脚掌真实接地。
    """
    source = opaque_copy(Image.open(OUT / "walk_sw_source.png"))
    assert source.size == (1586, 992), "源稿变更后必须重新人工标定，不能静默适配"
    factor = 48 / 440
    roots = [(198, 480), (198, 448)]
    frames = []
    for i in range(8):
        row, col = divmod(i, 4)
        cell = source.crop((round(col * source.width / 4), row * 496,
                            round((col + 1) * source.width / 4), (row + 1) * 496))
        resized = cell.resize((round(cell.width * factor), round(cell.height * factor)), NEAREST)
        frame = Image.new("RGBA", (64, 80))
        x, y = roots[row]
        frame.alpha_composite(resized, (32 - round(x * factor), 64 - round(y * factor)))
        frames.append(frame)
    atlas = Image.new("RGBA", (64, 640))
    for i, frame in enumerate(frames):
        atlas.alpha_composite(frame, (0, i * 80))
    atlas.save(OUT / "walk_sw_review_strip.png")
    return frames


def paste_scaled(board, frame, xy, scale):
    """用最近邻整数或指定倍率放大审稿图片，不改变原帧。"""
    scaled = frame.resize((round(frame.width * scale), round(frame.height * scale)), NEAREST)
    board.paste(scaled, xy, scaled)


def contact_sheet(frames):
    """生成八帧 4 倍逐帧板，标出参考落点而不把它误称脚掌位置。"""
    board = Image.new("RGB", (1056, 760), BACKGROUND)
    draw = ImageDraw.Draw(board)
    draw.text((20, 12), "候选逐帧板 · 4 倍 · 尚未通过动作验收", font=font(22), fill="#efc786")
    for i, frame in enumerate(frames):
        x, y = 16 + i % 4 * 260, 60 + i // 4 * 340
        draw.text((x + 10, y), f"{i + 1:02d}", font=font(18), fill="white")
        paste_scaled(board, frame, (x, y + 10), 4)
        draw.line((x + 124, y + 266, x + 132, y + 266), fill="#6bb7aa")
    board.save(OUT / "walk_contact_sheet.png")


def static_board(candidate):
    """并排展示原画、候选源稿及两者运行尺寸对照，分清身份与像素尺度。"""
    board = Image.new("RGB", (1000, 470), BACKGROUND)
    draw = ImageDraw.Draw(board)
    for x, label in [(20, "已定稿形象"), (260, "sw 静态候选"), (490, "现有 sw ×4"), (750, "候选 sw ×4")]:
        draw.text((x, 18), label, font=font(20), fill="white")
    approved = Image.open(ROOT / "docs/素材设计/样板/11-51级角色形象/look_06_lv51_final.png").convert("RGBA")
    selected = Image.open(OUT / "static_sw_source.png").convert("RGBA")
    for image, x in [(approved, 20), (selected, 260)]:
        image.thumbnail((215, 360), Image.Resampling.LANCZOS)
        board.paste(image, (x, 60), image)
    paste_scaled(board, existing("idle", 1)[0], (470, 60), 4)
    paste_scaled(board, candidate, (730, 60), 4)
    draw.text((490, 415), "同为 64×80 帧格，人物高 48 px", font=font(18), fill="#aeb9c5")
    board.save(OUT / "static_comparison.png")


def comparison_gif(frames):
    """以同一调色板输出 10 FPS 新旧对照，避免逐帧量化造成额外颜色闪烁。"""
    old = existing("walk", 8)
    rendered = []
    for i, frame in enumerate(frames):
        board = Image.new("RGB", (880, 460), BACKGROUND)
        draw = ImageDraw.Draw(board)
        draw.text((30, 18), "现有行走 ×4", font=font(22), fill="white")
        draw.text((330, 18), "二维候选 ×4", font=font(22), fill="white")
        draw.text((640, 18), "尺寸检查", font=font(22), fill="white")
        paste_scaled(board, old[i], (20, 50), 4)
        paste_scaled(board, frame, (320, 50), 4)
        paste_scaled(board, frame, (645, 90), 1)
        paste_scaled(board, frame, (740, 90), 1.5)
        draw.text((638, 220), "原尺寸    玩家 ×1.5", font=font(16), fill="#aeb9c5")
        draw.text((30, 395), f"10 FPS · 第 {i + 1}/8 帧 · 候选仍有步态与形状跳变", font=font(20), fill="#efc786")
        rendered.append(board)
    palette_source = Image.new("RGB", (880, 460 * 8))
    for i, board in enumerate(rendered):
        palette_source.paste(board, (0, i * 460))
    palette = palette_source.quantize(colors=256)
    quantized = [board.quantize(palette=palette, dither=Image.Dither.NONE) for board in rendered]
    quantized[0].save(OUT / "walk_comparison.gif", save_all=True, append_images=quantized[1:],
                      duration=100, loop=0, disposal=2, optimize=False)
    rendered[0].save(OUT / "walk_comparison_still.png")


def main():
    """重建全部审稿文件并核对帧格边缘、不同帧数量和 GIF 时长；不判定美术通过。"""
    candidate = static_frame()
    frames = walking_frames()
    static_board(candidate)
    contact_sheet(frames)
    comparison_gif(frames)
    bounds = [frame.getbbox() for frame in frames]
    assert all(b and b[0] > 0 and b[1] > 0 and b[2] < 64 and b[3] < 80 for b in bounds)
    gif = Image.open(OUT / "walk_comparison.gif")
    assert gif.n_frames == 8
    for i in range(8):
        gif.seek(i)
        assert gif.info["duration"] == 100
    metrics = {"status": "review_sample_not_approved", "direction": "sw", "frame_size": [64, 80],
               "pivot": [32, 64], "fps": 10, "source_scale": 48 / 440,
               "source_row_roots": [[198, 480], [198, 448]], "alpha_threshold": 153,
               "static_bbox": candidate.getbbox(), "walk_bboxes": bounds,
               "distinct_pixel_frames": len({hashlib.sha256(f.tobytes()).hexdigest() for f in frames}),
               "runtime_integrated": False, "actual_map_validated": False}
    (OUT / "metrics.json").write_text(json.dumps(metrics, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(metrics, ensure_ascii=False))


if __name__ == "__main__":
    main()
