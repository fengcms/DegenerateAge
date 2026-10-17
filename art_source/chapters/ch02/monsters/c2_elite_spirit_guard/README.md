# 汲灵护卫八方向试玩稿

内置 `image_gen` 参考 `concept.png`，分别生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原运行图第一格。提示词保持低伏六肢虫体、两只厚重钩状装甲前爪、背部紫色供灵玻璃罐、环绕铜管、暗红破布与紫眼虫首；每向明确头朝向及背罐与前爪的遮挡。`directional_preview.json` 记录各源图及 112×112 帧、脚底 y=88 的构建参数。

执行 `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_elite_spirit_guard` 可重建 `assets/sprites/monsters/c2_elite_spirit_guard/directional_preview_atlas.png`。可在第二章「旧汲灵井」「井核」检查。此稿仅具八方向单帧与受击、死亡变色，正式逐帧动画仍待制作。
