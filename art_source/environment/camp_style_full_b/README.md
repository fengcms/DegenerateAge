# 幸存者营地 B 全图源图

此目录的六张 PNG 是 2026-10-16 使用 OpenAI ImageGen 为本项目生成的透明整体实体或地表源图：`warehouse`（仓库）、`elder_tree`（长老树）、`guardian_lamp`（镇灵灯）、`caravan`（马车）、`training_fire`（训练火堆）和 `ground_variant`（地纹）。图像均用于本项目的游戏地图；没有引用第三方成品素材。它们仅作为制作源，不由游戏直接加载。

运行资源由 `python3 tools/build_camp_style_full_b.py` 用 ImageMagick 构建到 `assets/maps/camp_style_full_b/`。构建还复用已验收的 B 样板铁匠铺、货郎摊、北西围栏和西侧岩带，并依据 `data/map_art/camp_whitebox_v1.json` 制作其余整体围栏/岩带；原布局、NPC 和碰撞不由源图修改。
