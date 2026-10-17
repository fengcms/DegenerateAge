# 灰印书记八方向试玩稿

内置 `image_gen` 参考 `concept.png`，分别生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原运行图第一格。提示词保持高瘦双腿工衣游魂、旧铜矿帽、背负木制文册架、灰印垂旗、双手伸出两组文页及克制的紫色施法丝线；每向明确头、手、背架的遮挡。`directional_preview.json` 记录各源图及 112×112 帧、脚底 y=88 的构建参数。

执行 `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_elite_gray_scribe` 可重建 `assets/sprites/monsters/c2_elite_gray_scribe/directional_preview_atlas.png`。可在第二章「工坊下层」检查。此稿仅具八方向单帧与受击、死亡变色，正式逐帧动画仍待制作。
