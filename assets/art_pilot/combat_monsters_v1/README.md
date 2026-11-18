# 战斗样板怪物八方向运行补充包

本目录70张图集补充两类怪物的ne/nw/e/w/n/s/se七方向，每方向idle/walk/attack/hit/death五状态，各四帧；sw沿用assets/art_pilot现有十张图集。每帧128×96，图集128×384，脚底锚点(64,80)。共80张图集理论RGBA8为15360KiB，新增13440KiB，不含驱动开销。

manifest.json由tools/camp_combat/build_monsters.gd生成，唯一登记运行路径。源页、提示词、透明及留白修正版在art_source/actors/<种类>_<方向>_combat_v1。内置image_gen原创生成，参考项目原角色，未复制其他游戏素材。每页4列5行，固定等比缩放保留alpha，四边污染大于0.05则构建失败；不以程序抠图修补坏稿。

战斗场按正式SampleActorArt方向编号选择独立纹理，禁止镜像。实际位移64像素一个步态循环，待机3fps；受击沿用正式0.16秒，死亡0.90秒；即时近战从攻击接触阶段开始，只播放接触与收势，不新增伤害前摇。全部区域在装配期缓存，热路径只切引用。

`python3 tools/camp_combat/check_assets.py` 检查完整80张规格、方向独立内容和源记录，不替代实际播放与窗口检查。构建使用Godot headless脚本，最后参数为仓库绝对路径；可在空临时Godot工程中执行，不需要运行正式游戏。
