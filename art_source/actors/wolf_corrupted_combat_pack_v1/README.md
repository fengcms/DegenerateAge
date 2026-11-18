# wolf_corrupted正式四帧动画包

由tools/camp_combat/build_formal_monsters.gd将已验收的八向独立图集无损重排，不重新绘制、缩放或镜像。来源为assets/art_pilot/combat_monsters_v1与既有左前图集；原始生成记录见art_source/actors各方向combat_v1目录。

横轴四帧、纵轴s/sw/w/nw/n/ne/e/se，单帧128×96、锚点(64,80)，每张512×768 RGBA8。攻击接触帧2、死亡0.90秒；正式MonsterActorArt推进表现，伤害/掉落由宿主结算。--check逐像素核对所有方向和状态；正式运行复制与索引由统一build_monster_animation_assets.mjs生成。
