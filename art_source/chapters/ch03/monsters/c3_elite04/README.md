# 旱井吞砂兽八方向试玩稿

内置 `image_gen` 参考 `concept.png`，生成南、西南、西、西北、北、东北、东七张单体；东南向沿用原有运行图第一格。提示词固定巨型四足兽、赭色砂化皮肤、渠铜护颚、张开的齿口、背上的蓄沙圆井、包布带刺长尾与垂挂铜币。各图分别指定正侧背的朝向；北向以沙井与尾部为主要识别点。首版南向有褐色晕影，已重做为 `south_candidate_v2.png`，失败版本未入库。

`directional_preview.json` 记录七张透明源图及 112×112 帧、脚底 y=88 的构建参数。执行 `godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c3_elite04` 可重建 `assets/sprites/monsters/c3_elite04/directional_preview_atlas.png`。可在第三章 `c3_map03`「旱井旧坊」目视检查。此稿只有八方向单帧与受击、死亡变色；正式五状态逐帧动画仍待制作。
