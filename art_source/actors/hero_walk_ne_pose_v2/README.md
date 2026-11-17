# 背面骨架约束行走 V2：隔离试装

pose_guide.png与pose_checks.json由tools/motion_review/build_pose_guide.py --direction ne在Blender生成。左右骨架与原se版相同，切换相机到背面，蓝色左肢/红色右肢不镜像；数值验证交替接触、骨长和身体前方的屏幕投影。

candidate.png由内置image_gen参考姿态图和原背面站姿生成，完整提示词见prompt.json。相较hero_walk_ne_trial_v1，第1/3帧接触腿姿态已有区别，允许进入隔离营地观察。布料、脚滑、步幅与站走切换仍需精修，不代表完整正式动画验收。

源稿2048×768，四列512×768；构建事实源沿用../hero_walk_pilot_v3/build.json的rearWalkSource。统一0.14缩放、源锚点(275,710)，打包112×128帧格、pivot(56,112)，一列四行hero_walk_ne_v2.png。无逐帧重缩放、吸附足尖、镜像或代码形变。按实际位移64px循环，6fps仅对应96px/s审片基准。

review.json使用referencePivot(56,112)对齐配套站姿的接触区，避免审片时把透明帧底误当脚底。运行O键复现右上实际行走，P查看右下，I原地前后转向，H恢复旧图。其余方向仍缺失，正式CharacterLook不登记。
