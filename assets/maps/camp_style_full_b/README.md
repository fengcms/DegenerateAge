# 幸存者营地 B 全图运行素材

由 `python3 tools/build_camp_style_full_b.py` 从 `art_source/environment/camp_style_full_b/`、已验收的 B 样板和 `data/map_art/camp_whitebox_v1.json` 重建。需要 ImageMagick。游戏只加载 `manifest.json` 中引用的运行 PNG；源图与编辑预览不会进入场景依赖。

地面是一张 1024×1024 可循环地纹和一张 1672×941 的透明道路/贴地阴影。清单中的 22 条 `objects` 逐一对应原布局的 7 个整体实体与 15 段整体围栏/岩带。7 个可绕行实体有互斥的前沿与背层图片；前沿按原脚底位置排序遮挡玩家。围栏和岩带各是一张整体图，而非拆为 1×1 瓦片。
