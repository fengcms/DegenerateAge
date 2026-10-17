# 汲灵侍虫八方向试玩稿

内置 `image_gen` 参考 `concept.png`，生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原有运行图第一格。方向提示词共同约束破旧头罩、铜制鸟嘴呼吸器、紫色独眼、双背罐、连接手持注射灯的紫色软管、两条细长鸟足。每个方向分别指定头朝向和躯干遮挡，背向不显示正脸。`directional_preview.json` 记录各源图及 80×80 帧、脚底 y=64 的构建参数。

执行 `godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_spirit_attendant` 可重建 `assets/sprites/monsters/c2_spirit_attendant/directional_preview_atlas.png`。可在第二章「工坊下层」及「井核」目视检查。此稿只有八方向单帧与受击、死亡变色，正式逐帧动画仍待制作。
