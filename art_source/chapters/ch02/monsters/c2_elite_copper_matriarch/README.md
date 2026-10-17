# 铜壳母虫八方向试玩稿

内置 `image_gen` 参考 `concept.png`，分别生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原运行图第一格。每向提示词保持宽矮六足虫体、斑驳旧铜厚壳、侧腹苍紫育囊、背上破红布、长触须、钩状口器和爪足，并明确头部朝向与背面遮挡。`directional_preview.json` 记录各源图及 112×112 帧、脚底 y=88 的构建参数。

执行 `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_elite_copper_matriarch` 可重建 `assets/sprites/monsters/c2_elite_copper_matriarch/directional_preview_atlas.png`。可在第二章「断管坡」「旧汲灵井」「余烬炉房」检查。此稿仅具八方向单帧与受击、死亡变色，正式逐帧动画仍待制作。
