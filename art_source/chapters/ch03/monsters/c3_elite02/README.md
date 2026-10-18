# 巡渠铜卫八方向试玩稿

使用内置 `image_gen` 参考 `concept.png`，生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原有运行图第一格。造型重点为锈蚀渠铜甲、城垛状头盔、盐痕长条铜盾、赭色与白色破布。逐方向检查面向与背向，未用镜像代替反侧。

`directional_preview.json` 记录七张源图及 112×112 帧、脚底 y=88 的构建参数。执行 `godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c3_elite02` 可重建 `assets/sprites/monsters/c3_elite02/directional_preview_atlas.png`。可在第三章 `c3_map01`「渠铜前哨」目视检查移动转向、受击与死亡变色。正式五状态逐帧动画仍待制作。
