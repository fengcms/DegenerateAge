# 孢灯蛾八方向试玩稿

使用内置 `image_gen` 参考 `concept.png`，生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原有运行图第一格。造型锁定白色单眼面罩、鹿角状触角、白与赭红破翼、藤蔓骨架、淡黄绿灯腹和悬垂根须。逐方向检查单体、透明度及背面翅膀与灯腹，未用镜像代替反侧。

`directional_preview.json` 记录七张源图及 80×80 帧、脚底 y=64 的构建参数。执行 `godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c4_normal02` 可重建 `assets/sprites/monsters/c4_normal02/directional_preview_atlas.png`。可在第四章 `c4_map01`「倒根驿路」目视检查转向、孢光识别、受击与死亡变色。正式五状态逐帧动画仍待制作。
