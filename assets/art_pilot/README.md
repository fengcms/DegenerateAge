# 美术校准专用素材

由 tools/art_pilot/build.gd 从 art_source/style_pilot_20261117/layers 构建。营地1200×800，主角96像素高，狼和铜甲虫110像素宽；三种对象均为单方向单帧，不登记正式角色/怪物动画库。独立查看器按图片底边作为临时落点，正式脚底锚点仍待精修。

源稿使用内置image_gen，提示词见源稿目录prompts.json。铜甲虫补做一次去背景生成，最终仍有柔和半透明外围。PNG保留原始alpha；不使用黑色键抠图。素材仅供校准，不修改地图、怪物和存档ID。

## 模块化营地中的角色试装

新增beetle_v2.png（110×82），由tools/modular_camp/launch.py --build-assets构建，源稿位于art_source/actors/camp_pilot_v1。新稿为无光晕的六足铜甲虫，不覆盖worm.png。模块化营地只复制hero.png（77×96）、wolf.png（110×57）与beetle_v2.png，不加载camp.png或旧worm.png。

样板角色锚点与资源路径集中在tools/modular_camp/actors.json；pivot_ratio以图像左上角为原点归一化。主角暂用底部中心；狼为(0.5,0.87)，甲虫为(0.5,0.82)，四足/六足按接触区域中心排序，不能统一取最低足尖。名称位于图顶上方22px，可按N切换。角色碰撞仍为半径12，怪物仅展示，无碰撞、AI或血条，不映射正式怪物模板。三个形象都是单帧，尚无帧率、命中帧或死亡时序。
