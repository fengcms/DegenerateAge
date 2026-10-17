# 煤灰头领八方向试玩稿

内置 `image_gen` 参考 `concept.png`，分别生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原运行图第一格。提示词保持低伏四足黑灰兽、暗色长鬃、高肩铜制棘甲、头部一对前弯黑角、带紫眼的装甲口鼻、腿甲、两侧灰印红布及少量背棘紫寄生；各向指定头朝向及背面遮挡。`directional_preview.json` 记录各源图及 112×112 帧、脚底 y=88 的构建参数。

执行 `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_elite_ash_leader` 可重建 `assets/sprites/monsters/c2_elite_ash_leader/directional_preview_atlas.png`。可在第二章「工坊下层」「井核」检查。此稿仅具八方向单帧与受击、死亡变色，正式逐帧动画仍待制作。
