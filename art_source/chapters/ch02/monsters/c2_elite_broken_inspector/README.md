# 断链巡检长八方向试玩稿

内置 `image_gen` 参考 `concept.png`，分别生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原运行图第一格。每向提示词保持高大双腿重甲、锈铜肩甲、面罩紫色裂隙、头后巡检旗、白色徽记布条、破红布和右手长链尖刺铁灯锤。方向提示明确头部朝向、侧面层叠和背面遮挡。`directional_preview.json` 记录各源图及 112×112 帧、脚底 y=88 的构建参数。

执行 `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_elite_broken_inspector` 可重建 `assets/sprites/monsters/c2_elite_broken_inspector/directional_preview_atlas.png`。可在第二章「断管坡」「旧汲灵井」「工坊下层」检查。此稿仅具八方向单帧与受击、死亡变色，正式逐帧动画仍待制作。
