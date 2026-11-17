# 营地模块化写实首批运行素材

来源为 `art_source/environment/camp_modular_v1`，内置image_gen原创生成。构建入口 `python3 tools/modular_camp/launch.py --build-assets`。正式地图尚未引用；隔离样板通过launch.py复制本目录。

- terrain_atlas.png：1024×1536，RGBA8理论6MiB，不含导入压缩和mipmap；16列为4×4材质相位，48行为基础地面与47种道路连接。每格64×32。不能随机打乱相位，否则材质共边不连续。
- 每格由同一256×256周期母版映射到等距地面。母版对向8px边带共同收口，运行不加载源稿或整幅地图。此过程只做技术投影/接缝处理，没有从概念图切地图。
- tree.png、shelter.png、wall.png为独立透明物件；实际尺寸及临时底部中心锚点见manifest.json。墙使用wall_short源稿，长墙候选未接入。
- 图集使用nearest过滤防止紧排图集串色；物件按现有精灵过滤显示。后续如切换图集线性过滤，需要增加挤出边和UV内缩。
- 当前只含一个墙轴方向，缺另一轴、转角/端帽、树冠分层、屋檐分层、草土族和贴花，不能称完整营地素材包。
