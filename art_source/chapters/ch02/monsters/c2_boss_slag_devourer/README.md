# 炉渣吞噬者八方向试玩稿

内置 `image_gen` 参考 `concept.png`，分别生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原运行图第一格。提示词保持巨大低伏四足、厚旧铜壳、前方锯齿熔渣巨口、背部敞开熔炉与短烟囱、暗红灰印破布和少量紫寄生；明确背向露出炉膛、隐藏前嘴。`directional_preview.json` 记录各源图及 192×192 帧、脚底 y=152 的构建参数。

执行 `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_boss_slag_devourer` 可重建 `assets/sprites/monsters/c2_boss_slag_devourer/directional_preview_atlas.png`。可在第二章「余烬炉房」检查技能预警、头顶 UI、转向、受击和死亡。此稿仅具八方向单帧与受击、死亡变色，正式逐帧动画仍待制作。
