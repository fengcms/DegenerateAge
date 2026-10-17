# 煤灰兽八方向试玩稿

内置 `image_gen` 根据 `concept.png` 逐方向生成七张透明单体，统一保留厚重四足兽身、暗色石棘、苍白骨甲、锈铜缰具、破红褐布片和少量紫晶。提示词逐向指定头尾与四足遮挡，背向不露完整獠牙面部；东南向沿用已接入的旧运行图第一格。按 `directional_preview.json` 锁定 80×80 画布、脚底 y=64 和七张源图。

构建：`godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_ash_beast`，输出 `assets/sprites/monsters/c2_ash_beast/directional_preview_atlas.png`。第二章「工坊下层」或「余烬炉房」可实窗检查。此稿仅具八方向单帧与受击/死亡变色，不改变冲锋、伤害或刷新逻辑，正式动画仍待制作。
