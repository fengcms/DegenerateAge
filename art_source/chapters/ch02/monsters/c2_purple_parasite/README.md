# 紫脉寄生体八方向试玩稿

内置 `image_gen` 参考 `concept.png`，生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原有运行图第一格。方向提示词共同约束佝偻双足、破布及皮革束带、暗色异界肉体、肩背紫晶、触须遮面的晶眼和右侧较长的晶爪。每个方向分别指定头朝向及左右肢体遮挡。`directional_preview.json` 记录各源图及 80×80 帧、脚底 y=64 的构建参数。

执行 `godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_purple_parasite` 可重建 `assets/sprites/monsters/c2_purple_parasite/directional_preview_atlas.png`。可在第二章「井核」目视检查。此稿只有八方向单帧与受击、死亡变色，正式逐帧动画仍待制作。
