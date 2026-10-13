# 第一章基础角色：可玩美术样板 v1

日期：2026-10-13。已在主游戏和独立审阅场景接入。范围：营地木桩、野外裂壳虫、灰烬游魂、五类功能 NPC。

## 试玩

在 Godot 打开 `scenes/ChapterOneArtSample.tscn`，按 **F6** 进入营地，可看五类 NPC 和三只教学木桩，靠近后用 E 交互。直接运行主游戏也会在原地图显示新素材。样板禁用自动存档，不使用现有存档槽。

要直接查看野外、灰烬之地，可在项目根目录运行：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --scene res://scenes/ChapterOneArtSample.tscn -- --art-map=wild_trial
/Applications/Godot.app/Contents/MacOS/Godot --path . --scene res://scenes/ChapterOneArtSample.tscn -- --art-map=ash_land
```

实机截图：[营地 NPC 与木桩](camp.png)、[野外狼与裂壳虫](wild.png)、[灰烬游魂与裂壳虫](ash.png)。截图为1440×900、地图倍率100%；仅截图模式暂停怪物 AI 并将部分怪物移入视野，正常试玩使用地图原有刷新点。

## 资源与接入

| ID | 正式资源 | 帧画布与锚点 | 接入行为 |
|---|---|---|---|
| training_dummy | `assets/sprites/monsters/training_dummy/dummy_atlas.png` | 3×(64×80)，脚底(32,64) | 完整、受击、倒下三姿态；仍不移动、不反击 |
| shellback_bug | `assets/sprites/monsters/shellback_bug/actor_atlas.png` | 8×8格，每格80×80，脚底(40,64) | 现有高防近战数据和 AI，八向关键姿态 |
| ash_wraith | `assets/sprites/monsters/ash_wraith/actor_atlas.png` | 8×8格，每格64×80，虚拟脚底(32,64) | 现有远程数据和 AI，八向关键姿态 |
| quest / shop / blacksmith / warehouse / carter | `assets/sprites/npcs/<role>/idle_atlas.png` | 各8×(64×80)，脚底(32,64) | 原地图坐标、名称、靠近提示、E/鼠标交互；靠近玩家时转向 |

原有碰撞形状、怪物数值、掉落、任务推进和 NPC 交互范围保持不变。点击区域随新精灵扩展到角色头部；新角色和怪物按脚底世界 Y 排序。NPC 资源按功能角色复用，车夫和货郎跨地图保持同一造型。

NPC 目前为每方向1张静态姿态；正面/侧前待机4帧、交互4帧和头像仍待制作。怪物是少帧关键姿态，未达到正式逐帧规范。灰烬弹的独立飞行特效、正式地形与营地建筑也未包含在本批。

## 制作与验证

全部原图由内置 image_gen 生成，提示词和参考图路径见 [prompts.json](prompts.json)。原图保存在 `art_source/chapter_one_characters/`；`tools/build_chapter_one_art.gd`只负责透明像素整理、切分、最近邻缩放、统一脚底锚点和导出。重新打包：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/build_chapter_one_art.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import
```

`ChapterOneArtTest.tscn`验证 NPC 五角色贴图与点击、木桩受击姿态、野外和灰烬地图的怪物资源；`ChapterOneAcceptance.tscn`、原 `ArtSampleTest.tscn`通过。当前共享工作区的完整 `SmokeTest.tscn`仍有自动战斗相关断言失败，需由对应玩法改动单独处理。
