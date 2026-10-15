"""从用户确认的统一面板 SVG 色值重建可复用的按钮局部素材。

只输出按钮底板与标题圆钮，不包含动态文字；运行时由 Godot 的 Button 管理交互。
"""

from pathlib import Path


DESTINATION = Path(__file__).resolve().parents[1] / "assets" / "ui" / "panel_chrome"


def header_svg() -> str:
    """制作可横向伸展的标题带，保留确认稿从旧铁灰到深色的三段渐变。"""
    return '''<svg xmlns="http://www.w3.org/2000/svg" width="8" height="52" viewBox="0 0 8 52">
<defs><linearGradient id="header" x1="0" y1="0" x2="0" y2="1">
<stop stop-color="#30383B"/><stop offset="0.5" stop-color="#1B252A"/><stop offset="1" stop-color="#131A1E"/>
</linearGradient></defs>
<rect width="8" height="52" fill="url(#header)"/>
</svg>
'''


def action_svg(top: str, middle: str, bottom: str, border: str, shine: str) -> str:
    """制作宽度可九宫格拉伸的操作按钮；渐变沿用确认稿的三段明暗。"""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="32" height="34" viewBox="0 0 32 34">
<defs><linearGradient id="metal" x1="0" y1="0" x2="0" y2="1">
<stop stop-color="{top}"/><stop offset="0.45" stop-color="{middle}"/><stop offset="1" stop-color="{bottom}"/>
</linearGradient></defs>
<rect x="0.65" y="0.65" width="30.7" height="32.7" rx="3" fill="url(#metal)" stroke="{border}" stroke-width="1.3"/>
<path d="M4 3.5H28" stroke="{shine}" stroke-opacity="0.42" stroke-linecap="round"/>
<path d="M4 30.5H28" stroke="#070d10" stroke-opacity="0.52"/>
</svg>
'''


def circle_svg(symbol: str, top: str, middle: str, bottom: str, border: str, symbol_color: str) -> str:
    """制作包含符号的正圆标题按钮；图案与圈体一起缩放，不受文字倍率改变。"""
    if symbol == "close":
        mark = f'<path d="M15 15L25 25M25 15L15 25" stroke="{symbol_color}" stroke-width="2" stroke-linecap="round"/>'
    else:
        mark = (f'<path d="M16.4 16.5C16.4 14.3 17.9 13 20 13C22.4 13 23.7 14.3 23.7 16.3'
                f'C23.7 18.1 22.4 19 20.5 20.2C19.3 21 19.1 21.7 19.1 22.6" '
                f'fill="none" stroke="{symbol_color}" stroke-width="1.9" stroke-linecap="round"/>'
                f'<circle cx="19.1" cy="26" r="1.1" fill="{symbol_color}"/>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">
<defs><linearGradient id="metal" x1="0" y1="0" x2="0" y2="1">
<stop stop-color="{top}"/><stop offset="0.45" stop-color="{middle}"/><stop offset="1" stop-color="{bottom}"/>
</linearGradient></defs>
<circle cx="20" cy="20" r="17.5" fill="#101719" stroke="#253034" stroke-width="1"/>
<circle cx="20" cy="20" r="16" fill="url(#metal)" stroke="{border}" stroke-width="1.4"/>
<path d="M8.8 14.2C10.8 9.9 14.8 7.1 19.5 6.8" fill="none" stroke="#f2dcaa" stroke-opacity="0.34" stroke-width="1"/>
{mark}
</svg>
'''


def main() -> None:
    """写入可直接由 Godot 导入的 SVG；每次运行覆盖同名派生素材。"""
    DESTINATION.mkdir(parents=True, exist_ok=True)
    (DESTINATION / "header_strip.svg").write_text(header_svg(), encoding="utf-8")
    action_states = {
        "normal": ("#404440", "#242B2D", "#151C20", "#817653", "#F2DCAA"),
        "primary": ("#645B3C", "#38372A", "#1A2020", "#B69A63", "#FFF0C5"),
        "hover": ("#58615B", "#303C3D", "#1B2528", "#D6BA7F", "#FFF0C5"),
        "primary_hover": ("#7A6C48", "#4D4730", "#222923", "#E3C17C", "#FFF0C5"),
        "pressed": ("#191F20", "#30352F", "#424131", "#A58B5C", "#C8B582"),
        "disabled": ("#292E2D", "#202629", "#151C20", "#485052", "#8B938D"),
    }
    for name, colors in action_states.items():
        (DESTINATION / f"action_{name}.svg").write_text(action_svg(*colors), encoding="utf-8")
    circle_states = {
        "normal": ("#404440", "#242B2D", "#151C20", "#776D59"),
        "hover": ("#59605A", "#354043", "#1B2528", "#D6BA7F"),
        "pressed": ("#1B2223", "#2F3531", "#333126", "#A58B5C"),
    }
    for symbol in ("close", "help"):
        for state, colors in circle_states.items():
            color = "#E3D3AD" if symbol == "close" else "#DCCCA7"
            (DESTINATION / f"{symbol}_{state}.svg").write_text(
                circle_svg(symbol, *colors, color), encoding="utf-8"
            )


if __name__ == "__main__":
    main()
