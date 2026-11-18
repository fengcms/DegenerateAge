# 正前方向行走与独立站姿

pose_guide.png和pose_checks.json由八视角骨架工具的s方向生成，身体前方投影为屏幕正下。candidate.png由内置image_gen参考骨架和已有主角生成，首稿边缘alpha最大约0.698—0.749，拒绝直接使用；candidate_alpha_v2.png通过背景提取后作为运行输入。完整提示词在prompt.json、alpha_prompt.json和idle_prompt.json。

行走2048×768，四列512×768，以0.135缩放、源锚点(260,715)打包。独立站姿1024×1536，以0.065缩放、源锚点(510,1460)打包。运行帧112×128、共用锚点(56,112)，配置唯一来源为../hero_walk_pilot_v3/build.json。

隔离营地G试走正下，WASD中的S也可直接查看对应方向。四帧仍有头身和衣物变化，正前视角的俯视程度仍需与斜向统一精修。骨架验证不能替代生成稿的人工审查，不登记正式CharacterLook，不用跨步帧充站姿。
