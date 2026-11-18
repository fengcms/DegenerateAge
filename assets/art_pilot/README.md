# 美术校准专用素材

由 tools/art_pilot/build.gd 从 art_source/style_pilot_20261117/layers 构建。营地1200×800，主角96像素高，狼和铜甲虫110像素宽；三种对象均为单方向单帧，不登记正式角色/怪物动画库。独立查看器按图片底边作为临时落点，正式脚底锚点仍待精修。

源稿使用内置image_gen，提示词见源稿目录prompts.json。铜甲虫补做一次去背景生成，最终仍有柔和半透明外围。PNG保留原始alpha；不使用黑色键抠图。素材仅供校准，不修改地图、怪物和存档ID。

## 模块化营地中的角色试装

新增beetle_v2.png（110×82），由tools/modular_camp/launch.py --build-assets构建，源稿位于art_source/actors/camp_pilot_v1。新稿为无光晕的六足铜甲虫，不覆盖worm.png。模块化营地只复制hero.png（77×96）、wolf.png（110×57）与beetle_v2.png，不加载camp.png或旧worm.png。

样板角色锚点与资源路径集中在tools/modular_camp/actors.json；pivot_ratio以图像左上角为原点归一化。主角暂用底部中心；狼为(0.5,0.87)，甲虫为(0.5,0.82)，四足/六足按接触区域中心排序，不能统一取最低足尖。名称位于图顶上方22px，可按N切换。角色碰撞仍为半径12，怪物仅展示，无碰撞、AI或血条，不映射正式怪物模板。三个形象都是单帧，尚无帧率、命中帧或死亡时序。

## 右下行走试装 V3

hero_walk_se_v3.png为112×512（四行，每格112×128），RGBA8理论224KiB；hero_walk_se_v3.json为构建清单副本。来源art_source/actors/hero_walk_pilot_v3/source.png，内置image_gen在V2姿态基础上修正原主角胸甲、背带和腰包。tools/modular_camp/launch.py --build-assets统一按0.15缩放并打包，固定pivot(56,112)，不逐帧拉伸、镜像或裁脚。

仅隔离营地引用：向屏幕右下、以(2,1)为中心约±22.5度范围播放四帧；循环按实际位移64px推进，配套站姿用于右下停步，原图保留给其他方向和关闭试装的对照。与正式CharacterLook一样采用帧尺寸、锚点及状态帧数约定，但不把缺失方向冒充完整八向登记。没有攻击命中、受击或死亡时序，怪物仍静态。

hero_idle_se_v3.png是新增配套单帧站姿，112×128、RGBA8理论56KiB，与行走同锚点。源稿及完整提示词为art_source/actors/hero_walk_pilot_v3/idle_source.png及idle_prompt.json；build.json的idleSource定义缩放0.069和源锚点(535,1410)，仅构建时处理。它不是呼吸动画，未改变角色碰撞、名字位置或正式外观登记。


hero_idle_ne_v3.png是独立右上背面站姿，112×128、pivot(56,112)，RGBA8理论56KiB；与右下站姿、四帧行走合计336KiB（不含旧回退图、导入和驱动开销）。来源art_source/actors/hero_walk_pilot_v3/rear_idle_source.png和rear_idle_prompt.json，按build.json的rearIdleSource构建。仅隔离营地加载，移动/停步均可显示这一背面单帧，尚无背面行走动画。前文“其他方向回退”现排除已补的右上背面方向。


wolf_idle_v1.png为128×384四帧待机图集，每帧128×96、pivot(64,80)、3fps、屏幕左下朝向，理论RGBA8为192KiB。源稿与提示词位于art_source/actors/wolf_idle_trial_v1，build.json构建、运行JSON为其副本。隔离营地J键恢复原wolf.png；新图集只加载一次，四个区域引用共享图集，热路径不生成新纹理。

beetle_idle_v1.png同为128×384四帧图集，每帧128×96、pivot(64,80)、3fps、屏幕左下；理论RGBA8为192KiB，两怪新增合计384KiB。源稿与两轮生成提示词在art_source/actors/beetle_idle_trial_v1；第一轮背景不透明，当前使用内置image_gen去背景修正版。两图集源稿不复制进运行项目，正式外观库不登记。

hero_walk_ne_v2.png新增右上四帧行走试装，112×512，一列四行112×128，pivot(56,112)，理论RGBA8为224KiB。源稿、骨架和提示词位于art_source/actors/hero_walk_ne_pose_v2，构建参数在hero_walk_pilot_v3/build.json；hero_walk_se_v3.json沿用旧文件名但现声明se/ne两个行走方向。两行走图集与两站姿理论合计560KiB。仅实际右上位移推进四帧，停步回原右上站姿，其他方向仍回退，不登记正式角色库。

hero_walk_sw_v1.png为112×512四帧图集，hero_idle_sw_v3.png为112×128站姿，共用(56,112)锚点，合计理论RGBA8 280KiB。来源hero_walk_sw_trial_v1，内置image_gen源稿与提示词可追溯，使用hero_walk_pilot_v3/build.json统一构建；旧清单文件名hero_walk_se_v3.json现描述三个方向，仅隔离样板使用。

左后第二版增加hero_walk_nw_v2.png（112×512）与hero_idle_nw_v3.png（112×128），每帧锚点(56,112)，理论RGBA8共280KiB。仅供隔离营地，源稿与提示词在art_source/actors/hero_walk_nw_trial_v2。

hero_attack_se_v1.png为右前挥剑112×512四帧，pivot(56,112)，理论RGBA8为224KiB。对应json保存四阶段秒制时长和视觉接触参考，不用于正式伤害结算；透明修正版源稿在art_source/actors/hero_attack_se_trial_v1。

wolf_attack_v1.png、beetle_attack_v1.png各128×384（四帧128×96），共用各自待机的(64,80)锚点。理论RGBA8各192KiB，共384KiB，隔离单次攻击无伤害事件。源稿与完整提示词分别在art_source/actors/wolf_attack_trial_v1和beetle_attack_trial_v1；狼使用透明修正版。

正前增加hero_walk_s_v1.png（112×512）和hero_idle_s_v3.png（112×128），锚点(56,112)，理论RGBA8共280KiB。源稿和提示词在art_source/actors/hero_walk_s_trial_v1，行走只采用透明修正版。

正后与左右侧向新增hero_walk_{n,e,w}_v1.png及hero_idle_{n,e,w}_v3.png，每方向224+56KiB，合计840KiB；八方向站走理论RGBA8共2240KiB。源稿和提示词在对应art_source/actors/hero_walk_{n,e,w}_trial_v1，w只采用修正版candidate_fixed_v2.png。

## 主角右前反应动作试装

hero_hit_se_v1 与 hero_death_se_v1 的 PNG/JSON 分别为四帧受击和倒地图集，112×512、单帧 112×128、锚点 (56,112)，RGBA8 合计 448 KiB。源稿与提示词在 art_source/actors/hero_hit_se_trial_v1、hero_death_se_trial_v1，由模块化营地构建工具生成。只供隔离样板 F/C/V 预览；倒地末帧保持，未接正式伤害或复活事件。

hero_attack_ne_v1.png/json：独立右后挥剑四阶段，112×512、帧 112×128、锚点 (56,112)，RGBA8 理论 224 KiB。源稿及构建参数在 art_source/actors/hero_attack_ne_trial_v1；隔离营地 4 键预览，正式角色外观不变。

hero_attack_sw_v1.png/json 为左前挥剑四阶段，112×512，共224KiB RGBA8；源和提示词在 art_source/actors/hero_attack_sw_trial_v1。仅隔离营地5键预览。
