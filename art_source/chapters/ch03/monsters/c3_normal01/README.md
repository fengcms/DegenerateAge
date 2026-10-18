# 砂背螯虫八方向试玩稿

内置 `image_gen` 参考 `concept.png`，分别生成南、西南、西、西北、北、东北、东七张透明单体；东南向沿用原有运行图第一格。提示词约束赭色沙丘状层叠背甲、白色盐痕、渠铜立柱与残破白布、六条窄足及两只巨螯，并逐张指定正、侧、背视角。西北和东北方向对背甲的表现优先于面部细节，原生尺寸仍可见部分正面结构；属试玩稿可接受的方向误差，正式逐帧动画时需修正。`directional_preview.json` 记录源图和 80×80 帧、脚底 y=64 的参数。

曾尝试以北向图重做西北、东北，但结果自带不透明褐色晕影，因此未采用、未纳入资源。最终七张均为透明源图。

执行 `godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c3_normal01` 可重建 `assets/sprites/monsters/c3_normal01/directional_preview_atlas.png`。可在第三章 `c3_map01`「渠铜前哨」目视检查。此稿只有八方向单帧与受击、死亡变色，正式五状态逐帧动画仍待制作。
