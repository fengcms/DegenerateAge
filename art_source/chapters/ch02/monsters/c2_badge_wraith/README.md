# 工牌游魂八方向试玩稿

七张方向源图由内置 `image_gen` 以 `concept.png` 作参考逐向生成，锁定旧铜矿帽、胸前工牌、破旧工装、灰色雾状手与残缺烟缕、少量紫光及完整靴子。方向提示分别指定正面、侧面和真实背面；背向须隐藏胸前工牌与烟雾面纱。图片保留透明背景，不含地面、文字或影盘；东南向沿用旧 `simplified_atlas.png` 的原姿。

构建：`godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=c2_badge_wraith`。源图与帧规格见 `directional_preview.json`，运行图为 `assets/sprites/monsters/c2_badge_wraith/directional_preview_atlas.png`，每格 80×80。玩家可在第二章「工坊下层」目视验收。当前只具八方向单帧及受击/死亡变色，独立幽魂动作仍待制作。
