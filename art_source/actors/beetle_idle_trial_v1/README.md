# 铜甲虫四帧触须待机试装

内置image_gen参考camp_pilot_v1/beetle.png生成2×2四帧，prompt.json记录首轮提示词。首轮opaque_candidate.png带不透明背景，审片透明角断言失败；使用extraction_prompt.json通过内置image_gen去背景，得到candidate.png，原稿保留用于追溯。

candidate.png为1536×1024；源格768×512、固定缩放0.16、源锚点(384,410)，输出128×96帧格、运行锚点(64,80)，四行图集，3fps。锚点取多足接触区域中心，不取最低前足尖。build.json是构建事实源，review.json用于原尺寸和三倍审片。

触须和口器有小幅变化，六足/甲壳仍有轻微漂移，透明修正也改变了少量材质细节；仅允许隔离样板观察，不代表正式动作包验收。没有假移动、攻击伤害或镜像补方向。J键恢复beetle_v2.png；源稿不进入运行项目。
