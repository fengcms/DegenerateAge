# 哨塔寄藤八方向试玩稿

使用内置 `image_gen` 参考 `concept.png`，生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原有运行图第一格。造型锁定三叉藤柱、三个淡绿孢光球、树根脚、石牌和破红旗。作为定点远程怪，朝向变化主要体现在符牌与枝干背面；因近对称轮廓，部分方向差异较小，原生图集仍可区分正背。未用镜像代替反侧。

`directional_preview.json` 记录七张源图及 80×80 帧、脚底 y=64 的构建参数。执行 `godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c4_normal08` 可重建 `assets/sprites/monsters/c4_normal08/directional_preview_atlas.png`。可在第四章 `c4_map02`「失声哨林」目视检查朝向、孢光识别、受击与死亡变色。正式五状态逐帧动画仍待制作。
