# 幸存者营地v2 A/B对照样板

由tools/build_camp_style_sample_v2.py生成，源图继承art_source/environment/camp_style_sample/既有来源与许可，复用既有分层构建方式；不新增外部图片或更改正式地图。

A为1倍像素对照，B为2倍像素对照。两者共用camp_whitebox_v2的参考画布1672×941、三个实体艺术矩形及脚底深度；四段训练栅栏直接引用正式v2素材，像素边缘保持最近邻。已经取消障碍的外围岩带、连续外围木栅不再出现在对照样板中。

每版一张1250×790（B为2500×1580）的透明局部地面，加三组互斥背层/前沿PNG。清单中的碰撞/艺术坐标来自正式v2布局；脚底承重区域不另造第二份几何事实源。

本目录供tests/CampStyleSample.tscn使用，未接入正式Game地图入口。正式营地仍引用的旧B样板文件保留在camp_style_sample/b，本工具不覆盖它们。重建命令：python3 tools/build_camp_style_sample_v2.py，需要ImageMagick。

F1铁匠、F2长老树、F3货郎、F4训练场入口；F5/F6切A/B，F7/F8/F9切地图倍率。逐格承重、层像素互斥和真实行走验收位于CampStyleSampleTest/CampStyleTraversalTest。

构建代价：两版运行PNG合计约3.8MB目录体积，按RGBA尺寸估计未压缩纹理约24.97MiB（不含驱动额外开销）。这只属于开发对照场景；两个正式导出预设明确排除此目录a/b子项，不增加正式游戏贴图加载依赖。
