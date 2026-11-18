# 左前行走候选：待进一步验收

pose_guide.png与pose_checks.json由Blender四斜向姿态工具的sw方向生成。candidate.png由内置image_gen参考该姿态及原主角站姿生成，完整提示词见prompt.json。原稿2048×768、四列512×768；review.json以统一0.14倍率及(275,710)锚点显示，不逐帧缩放贴地。

已进行棋盘底、原尺寸、三倍和四帧条带检查，左前身体朝向与右手持剑可识别。仍需审查接触腿与足尖漂移，并制作配套左前站姿；当前under_review，不复制到运行资源或注册正式外观。

查看：python3 tools/motion_review/launch.py --source art_source/actors/hero_walk_sw_trial_v1。G切换姿态条带，方向键逐帧，B切换背景。
