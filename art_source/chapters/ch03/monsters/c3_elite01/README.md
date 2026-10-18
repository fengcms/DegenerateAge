# 背闸虫王八方向试玩稿

内置 `image_gen` 参考 `concept.png`，分别生成南、西南、西、西北、北、东北、东七张单体；东南向沿用原有运行图第一格。提示词固定六足重甲蟹形、渠铜双扇闸爪、裂开的铰接背壳、白色盐蚀痕和破白布，并逐方向指定正、侧、背视角。西南与东方向首版带不透明褐色晕影，已仅重做两张为 `v2`，未入库失败版本。

`directional_preview.json` 记录七张透明源图及 112×112 帧、脚底 y=88 的构建参数。执行 `godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c3_elite01` 可重建 `assets/sprites/monsters/c3_elite01/directional_preview_atlas.png`。可在第三章 `c3_map01`「渠铜前哨」目视检查精英怪移动、攻击朝向、受击和死亡。本稿只有八方向单帧与受击、死亡变色，正式五状态逐帧动画仍待制作。
