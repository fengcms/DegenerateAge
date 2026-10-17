# 百臂汲灵机八方向试玩稿

内置 `image_gen` 参考 `concept.png`，分别生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原运行图第一格。提示词保持双腿重型机械体、四条主机械臂（钻、爪、汲灵灯、钳）、正面紫色寄生核心与封印、背后三根紫色供灵玻璃筒、交错铜管和红白破布。初版背向三帧仍像正面，已以背部供灵筒、背甲、管线和臂后关节为重点重做 `v2`；西北向局部多出一根供灵筒，缩到运行尺寸后仍可辨为同一主体，后续正式动画需统一筒数。`directional_preview.json` 记录最终源图及 192×192 帧、脚底 y=152 的构建参数。

执行 `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_boss_hundred_arm_extractor` 可重建 `assets/sprites/monsters/c2_boss_hundred_arm_extractor/directional_preview_atlas.png`。可在第二章「井核」检查技能预警、头顶 UI、转向、受击和死亡。此稿仅具八方向单帧与受击、死亡变色，正式逐帧动画仍待制作。
