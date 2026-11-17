# 右上背面行走首轮候选：未接入

内置image_gen参考已认可背面站姿生成，完整提示词见prompt.json。候选2048×768，四列512×768。第1、3帧重复了类似跨步，接触脚交替不清楚，不能作为已完成的四帧步态。当前背面继续使用单帧站姿，不改正式或样板行走。

使用tools/motion_review/launch.py --source art_source/actors/hero_walk_ne_trial_v1审片。后续应使用明确背面左右腿姿态约束重做接触帧，不能依靠裁切、镜像或代码晃动掩盖姿态问题。
