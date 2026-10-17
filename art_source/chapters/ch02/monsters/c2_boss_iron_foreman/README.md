# 镇井监工·铁臂八方向试玩稿

内置 `image_gen` 参考 `concept.png`，分别生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原运行图第一格。提示词保持双机械腿、笼状头盔、右侧巨大液压钳臂、左手短锤、胸前工牌、暗红与白色破工裙、链条及少量紫寄生。初版背向三帧仍露出正面胸牌，已针对西北、北、东北重新生成 `v2`：明确背甲、管线、后脑和腿后侧，隐藏正脸与胸牌。`directional_preview.json` 记录最终七张源图及 192×192 帧、脚底 y=152 的构建参数。

执行 `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_boss_iron_foreman` 可重建 `assets/sprites/monsters/c2_boss_iron_foreman/directional_preview_atlas.png`。可在第二章「旧汲灵井」检查技能预警、头顶 UI、转向、受击和死亡。此稿仅具八方向单帧与受击、死亡变色，正式逐帧动画仍待制作。
