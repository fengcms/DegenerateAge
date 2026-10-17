# 喷渣蛭八方向试玩稿

以内置 `image_gen`、现有 `concept.png` 为固定参考，逐张绘制 `s/sw/w/nw/n/ne/e` 七个透明方向。共用提示词锁定：柔软分节长体、锈铜束带与吊环、破旧褐布、短小支撑足、少量紫寄生、额顶漏火烟囱，以及齿圈内橙红色炉渣口器；每个方向指定头尾在画面上的位置。背向提示词要求只见背甲和烟囱、不见完整口器。东南向沿用原 `simplified_atlas.png` 原姿。

`directional_preview.json` 记录七张源图与 80×80 脚底规格。运行图由 `godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_slag_leech` 构建，输出 `assets/sprites/monsters/c2_slag_leech/directional_preview_atlas.png`。可在第二章「旧汲灵井」目视检查体量与转向。当前为八方向单帧试玩稿，不包含独立喷吐逐帧动作，`formal_animation` 仍为 `pending`。
