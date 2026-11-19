# 幸存者营地 B 第二版美术源图

三张 PNG 于 2026-10-16 使用 OpenAI ImageGen 为本项目生成。`ground_diagonal.png` 参考旧营地地面的斜向石纹及已认可的 B 风格地表；`fence_horizontal.png` 与 `fence_vertical.png` 参考已认可的铁匠铺木材质，作为内部训练场围栏的像素源。均为本项目原创生成图，不直接由游戏加载。

`tools/build_camp_style_full_b_v2.py` 用这些源图和 `data/map_art/camp_whitebox_v2.json` 生成 `assets/maps/camp_style_full_b_v2/`。保留的建筑、长老树、马车和中央灯仍从 `art_source/environment/camp_style_full_b/` 制作。原生成图保留在此目录；脚本输出的循环地纹、碎石路与分层整体实体是唯一正式运行素材。

`training_fire.png` 为内置 imagegen 生成的灰石火塘。原营火前层仅用于占地和视角参考，完整提示见 `training_fire_prompt.txt`。构建器从透明源稿裁出主体，再按原火塘宽 48 像素及底边第 57 像素定位到 76×68 的运行画幅。按原第 50 像素分为背层和前沿，输出 `training_fire_back.png` 与 `training_fire_front.png`。火苗为静态图像。
