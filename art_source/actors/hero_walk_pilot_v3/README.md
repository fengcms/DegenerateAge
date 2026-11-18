# 守护者右下行走 V3：隔离试装

source.png由内置image_gen编辑生成。输入为V2姿态候选及已认可主角原画；完整提示词见prompt.json。本轮补回胸前圆环、斜背带、腰包及破损腰摆，保留四种已有落脚姿势。它是可在营地观察的单方向动作试装，尚非完整正式动画。

build.json是打包事实源：原稿2048×768、四列；统一缩放0.15，每格512×768缩为77×115，打包成一列四行112×128。源锚点(275,720)统一映射至运行锚点(56,112)。不按每帧包围盒重缩放，不逐帧吸附脚底，不镜像人物或武器。输出assets/art_pilot/hero_walk_se_v3.png和同名JSON。

运行只对屏幕右下方向播放，64px实际位移一循环；配置6fps是96px/s审片基准。配套idle_source.png用于右下停步；原静态主角用于其他方向与关闭试装对照。四帧步态较简化，仍需精修脚滑、步幅和站走过渡；攻击、受击、死亡与其他方向行走均未制作，本轮不登记正式CharacterLook。

查看：python3 tools/modular_camp/launch.py；P试走，H原静态图对照。

## 配套站姿

idle_source.png以同目录行走源稿为参考由内置image_gen生成，提示词见idle_prompt.json。双脚落地、右手低持剑，保留胸饰和腰包。按build.json缩放0.069并以源锚点(535,1410)放入同规格112×128帧，导出hero_idle_se_v3.png；未使用逐帧拉伸、透明度交叉混合或人物位置补偿掩盖切换。

## 右上背面站姿

rear_idle_source.png由内置image_gen参考idle_source.png生成，完整提示词见rear_idle_prompt.json；原创角色旋转成右上背面，不使用商业游戏素材或镜像前身。build.json的rearIdleSource定义1024×1536源尺寸、0.069缩放与源锚点(530,1390)，统一打包112×128/pivot(56,112)的hero_idle_ne_v3.png。idleDirections单独记录se/ne，directions仍只声明se行走，不能据此宣称八向动画完成。

I原地对照前后站姿。右上移动先使用背面静态图，未制作背面步态；正式CharacterLook仍不登记。前后材质与人物高度接近，披布形状仍需在后续多方向制作中保持一致。

## 右上行走扩展

现已补入../hero_walk_ne_pose_v2/candidate.png，由背面双色骨架约束生成。build.json的rearWalkSource定义四列512×768、0.14缩放与源锚点(275,710)，输出hero_walk_ne_v2.png，与既有站姿/右下行走共用112×128帧和(56,112)锚点。directions现为se/ne；右下源图未改。O复现右上试走，其他方向仍回退。前文“右上仅单帧”为上一阶段记录，当前仅两方向具备四帧试装，仍非完整八向。

## 左前扩展

leftWalkSource和leftIdleSource指向../hero_walk_sw_trial_v1；directions与idleDirections现为se/ne/sw。新增左前四帧与配套站姿，不覆盖旧图，运行U键试走。左后仍缺合格素材，当前非完整四向或八向。

现增加nw左后修正版，leftRearWalkSource/leftRearIdleSource指向../hero_walk_nw_trial_v2；四个斜向各自独立素材，没有镜像武器或接入正式CharacterLook。

frontWalkSource/frontIdleSource增加正前s方向，指向../hero_walk_s_trial_v1；运行清单现列出se/ne/sw/nw/s五方向。构建以方向映射选择源稿，原四斜向输出规格不变。
