# 断链守卫八方向试玩稿

以本目录 `concept.png` 为形体参考，使用内置 `image_gen` 按 `s/sw/w/nw/n/ne/e` 七个方向分别制作透明单体。共同提示词要求：旧铜矿工帽与单头灯、铁栅面罩、灰色破披布和铁锈红裙片、左臂紫色腐化、腰间铁链、右手双刃矿镐、完整双足，等距游戏视角、透明背景、无场景/文字；每张另外指定朝向，并特别要求背向隐藏面罩、矿镐保持在角色右手。原东南向继续使用 `simplified_atlas.png` 第一格。AI 输出是方向源图而非动作帧。

构建：`godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_broken_guard`。输出为 `assets/sprites/monsters/c2_broken_guard/directional_preview_atlas.png`，80×80 格、八方向三状态。实窗可在第二章「断管坡」「旧汲灵井」查看。当前质量按用户已接受的汲灵幼虫试玩标准复核；没有独立步行或矿镐攻击逐帧画面，正式动画仍为 `pending`。
