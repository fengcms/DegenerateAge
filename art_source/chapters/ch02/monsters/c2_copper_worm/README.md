# 铜壳蠕虫八方向试玩稿

以本目录 `concept.png` 为造型参考，使用内置 `image_gen` 逐张生成 `s/sw/w/nw/n/ne/e` 七个透明方向源图；东南向沿用已接入的 `simplified_atlas.png` 原姿格。共同提示词要求：单体、等距游戏视角、旧铜节甲与铆钉、破旧红褐布片、白灰色腹部、三对短爪、头部少量紫色寄生物、透明背景、无地面/文字；方向提示词分别指定头和尾在画面上的相反指向，北与西北/东北明确隐藏正面口器。生成方式为内置工具逐方向单图，不是整张图集一次生成。原图只供制作和复核，运行时只加载 80×80 格的图集。

构建：`godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_copper_worm`。`directional_preview.json` 记录方向文件、格尺寸和脚底；输出到 `assets/sprites/monsters/c2_copper_worm/directional_preview_atlas.png`（3 列 × 8 行，80×80）。游戏中使用 `directional_preview`，按移动/攻击方向切换，受击/死亡保留变色反馈。正式五状态逐帧动画仍为 `pending`。
