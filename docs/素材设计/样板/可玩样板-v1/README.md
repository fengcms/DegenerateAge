# 守护者＋腐化野狼＋营地局部：可玩美术样板 v1

日期：2026-10-13。状态：已接入，可试玩；少帧动画原型，尚非完整正式美术包。

## 如何试玩

Godot 中打开 `scenes/ArtSample.tscn`，按 **F6（运行当前场景）**。F5仍运行原来的主场景；主场景也已显示新的玩家、野狼、营地地面和对应物品图标。

也可以在项目根目录执行：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --scene res://scenes/ArtSample.tscn
```

样板直接进入试炼野外，使用营地地面主题，角色附近摆放6只真实野狼。地图名仍为试炼野外，以保持安全区、战斗和出行规则真实。营地美术用于展示，不把安全区变成敌袭场景。角色初始包内含短刃、8瓶小红药和3块灵能碎片。WASD移动、点击野狼攻击、Space普攻、Tab切目标、I背包、F自动战斗。背包双击短刃穿戴；红药也可从背包使用。

样板关闭自动存档且无活动槽，不自动写入已有角色。主动打开存档管理并手动存档仍是原游戏功能；样板不需要这样操作。

## 已制作并接入

| 资源 | 路径 | 尺寸/锚点 |
|---|---|---|
| 守护者八向关键姿态 | `assets/sprites/player/guardian/guardian_atlas.png` | 图集512×640；单帧64×80；脚底(32,64) |
| 腐化野狼八向关键姿态 | `assets/sprites/monsters/wolf_corrupted/wolf_atlas.png` | 图集640×640；单帧80×80；接地(40,64) |
| 营地地砖4种 | `assets/tiles/camp/tile_0.png`至`tile_3.png` | 每张64×32，中心(32,16) |
| 营火 | `assets/tiles/camp/campfire.png` | 64×80；(32,64) |
| 补给箱 | `assets/tiles/camp/crate.png` | 64×64；(32,48) |
| 守护者短刃图标 | `assets/sprites/equip/weapon_starter.png` | 48×48 |
| 小红药、灵能碎片图标 | `assets/sprites/items/potion_hp_small.png`、`spirit_shard.png` | 48×48 |
| 上述三种世界物品 | `assets/sprites/items/*_ground.png` | 32×32；主体脚底(16,24) |

营火和箱子仅为装饰，不是可开启宝箱，不新增碰撞或玩法奖励。主体仍使用原碰撞和伤害判定；仅野狼的鼠标选择范围增加了精灵身体区域，使点击图像上半身也能选中。玩家与野狼按脚底世界Y排列，阴影独立程序绘制。

背包/装备位/交易托盘/仓库通用格/快捷栏以及对应地面掉落使用图标映射。未制作物品仍显示原文字/程序图形；品质边框、数量、冷却、提示与飞行时序保留原规则。HUD其他框架、NPC、虫、精英、Boss仍为原占位表现，后续批次再替换。

## 玩家显示尺寸调整

根据试玩反馈，玩家精灵在原尺寸基础上放大25%（`PlayerCharacter.ART_SCALE = 1.25`），阴影和刀光起点同步适配。以脚底为中心缩放，帧画布、脚底锚点、碰撞半径12px、移速、攻击与拾取范围保持原值；野狼和地图不额外放大。此调整同时作用于主游戏与可玩样板。现有审阅截图记录的是调整前版本。

## 动画元数据与当前限制

- 图集8列×8行；列顺序：s、sw、w、nw、n、ne、e、se，均为屏幕朝向。
- 行顺序：idle_a、idle_b、walk_a、walk_b、attack_a、attack_b、hit、death。
- 待机2关键帧约3FPS；行走2关键帧约10FPS；攻击2关键帧按实际攻击间隔适配0.12–0.36秒；受击1帧0.12秒；死亡1帧沿用现有淡出/复活时序。
- 伤害在原战斗调用中结算；表现从命中姿态开始再收势，动画没有扣血回调，不新增攻击蓄力或延迟。
- 守护者原始图集中缺少独立hit行，因此暂复用其回缩姿态；death取最后一行。野狼具备独立hit姿态。
- 这批未达到设计规范的4/8/6/2/6完整逐帧数量。待机、步态和武器动作仍有少帧跳变，下一轮需要补间与人工逐帧修整。
- 打坐保留真实恢复逻辑与脚底灵能提示，独立坐姿尚未制作。营火目前静态，后续可补火焰循环。
- 图片源头是内置image_gen生成；`tools/build_art_sample.gd`仅做透明阈值整理、分割、最近邻尺寸规范化、锚点排版与导出。没有手工像素分层源文件，原始生成PNG可作为后续重绘参考。
- 单帧以包围盒对齐脚底，严格固定帧格，动作中心与步态仍需人工打磨；不能把自动排版等同于动画质量最终验收。

## 制作记录与可复现流程

原始图像保存在 `art_source/playable_sample/`，由 `.gdignore`排除Godot资源扫描；完整生成提示词和参考路径见 [prompts.json](prompts.json)。均使用内置image_gen，未使用CLI/API密钥流程。生成样板延续此前批准造型，不引入第三方角色或品牌素材；分发前授权与来源登记仍沿用项目统一流程。

重新整理资源：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/build_art_sample.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import
```

导出实机审阅截图（暂停野狼AI，仅用于拍摄，完成后进程退出）：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --scene res://scenes/ArtSample.tscn --resolution 1440x900 -- --art-capture
```

## 验证记录

- Godot 4.7.2本机导入与运行通过。
- `tests/ArtSampleTest.tscn`验证图集尺寸、8向映射、行走/攻击/受击/死亡状态、3物品图标、背包格显示、原碰撞半径、单次扣血与样板禁用自动存。
- 既有 `tests/SmokeTest.tscn` 全部通过；日志中损坏存档JSON报错为该测试主动模拟的恢复场景，最终断言通过。
- `tests/HotbarUiTest.tscn`与`tests/InputFeedbackTest.tscn`全部通过；快捷栏拖放、药品使用和输入反馈回归正常。
- 实际1440×900渲染记录：[100%地图](world.png)、[背包图标](inventory.png)、[150%地图](world_150.png)、[80%地图](world_80.png)。截图已目视核对主体比例、地砖连续性、数量角标与图标透明边缘。
- 当前不是发布性能验收：尚未完成30敌人＋完整特效、所有UI极端缩放组合或低配设备评测。

下一轮重点：补齐动画帧、固定每方向更准确的脚部参考点，降低地面高频纹理，再替换教学木桩与营地NPC。
