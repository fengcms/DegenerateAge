# 千结根牙八方向试玩稿

使用内置 `image_gen` 参考 `concept.png`，生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原有运行图第一格。造型锁定巨型白骨叉颚、苔色四足根躯、背部竖立石碑、淡绿小菌和破红旗。逐方向检查背面石碑与侧向大颚，未用镜像代替反侧。东南向原运行图的绘制体量略小于新生成方向，保留为试玩稿限制；正式逐帧制作时须统一该方向体量。

`directional_preview.json` 记录七张源图及 112×112 帧、脚底 y=88 的构建参数。执行 `godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c4_elite01` 可重建 `assets/sprites/monsters/c4_elite01/directional_preview_atlas.png`。可在第四章 `c4_map01`「倒根驿路」目视检查转向、大颚识别、受击与死亡变色。正式五状态逐帧动画仍待制作。
