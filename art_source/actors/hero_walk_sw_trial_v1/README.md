# 左前行走候选：隔离试装

pose_guide.png与pose_checks.json由Blender四斜向姿态工具的sw方向生成。candidate.png由内置image_gen参考该姿态及原主角站姿生成，完整提示词见prompt.json。原稿2048×768、四列512×768；review.json以统一0.14倍率及(275,710)锚点显示，不逐帧缩放贴地。

已进行棋盘底、原尺寸、三倍和四帧条带检查，左前身体朝向与右手持剑可识别。仍需精修接触腿与足尖漂移；现已补配套站姿并进入隔离样板，不注册正式外观。

查看：python3 tools/motion_review/launch.py --source art_source/actors/hero_walk_sw_trial_v1。G切换姿态条带，方向键逐帧，B切换背景。

配套idle_source.png由内置image_gen参考本目录行走稿生成，完整提示词见idle_prompt.json。build.json事实源位于../hero_walk_pilot_v3：行走统一0.14、源锚点(275,710)；站姿0.066、源锚点(520,1410)。运行均112×128、pivot(56,112)，不镜像、不逐帧贴地。U复现左前试走，停步回此站姿。
