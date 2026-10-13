# 第一章场景素材 v1

本批将试炼野外和灰烬之地从纯色网格替换为 64×32 等距地砖。每张地图有四种地面变体、四种地标原画，主通道与实际出口的第 30 行对齐。地标是纯装饰，不改变碰撞、移动、怪物刷新或地图数据。营地沿用已验收的地面与营火/木箱。

## 试玩

- 正常游戏：从营地出发，依次走到试炼野外和灰烬之地。
- 集中查看：在 Godot 中打开 `scenes/ChapterOneArtSample.tscn`，F6 运行默认为营地；启动参数 `-- --art-map=wild_trial` 或 `-- --art-map=ash_land` 可直接看对应地图。

## 素材与构建

- 生成原画：`art_source/environment/{wild,ash}_{tiles,props}.png`。
- 游戏内资产：`assets/tiles/{wild,ash}/tile_0..3.png`（64×32）、`prop_0..3.png`（80×80，立足点 40,72）。
- 可重复打包：`godot --headless --path . --script tools/build_environment_art.gd`。打包强制统一菱形边界，并清理半透明杂边。
- 运行时代码：`scripts/world/ground.gd` 负责铺地，`scripts/world/environment_props.gd` 负责固定地标。

## 生成提示词方向

使用内置 imagegen 的透明背景模式，分别生成四张 2×2 图集：野外地砖、灰烬地砖、野外地标、灰烬地标。统一指定 3/4 等距视角、左上方光源、清晰像素边缘、四格互不重叠、无文字。野外以苔色土壤、草、石、路面及枯树/路牌为主；灰烬以炭黑、灰土、冷却熔岩、微弱余烬及焦木/残碑为主。地面降低对比度，让角色始终成为视觉焦点。

## 验收

Godot 4.7.2 编辑器导入成功；`ArtSampleTest`、`ChapterOneArtTest`、`ChapterOneAcceptance` 通过。无界面渲染不能完成截图保存，仍需在游戏窗口人工检查色彩、遮挡和主通道可读性。
