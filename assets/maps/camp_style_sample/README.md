# 幸存者营地 A/B 局部贴图样板

本目录只服务 `res://tests/CampStyleSample.tscn`，未接入正式营地入口。A 为低源像素的清晰轮廓对照，B 为高有效像素的克制插画试作；两版使用完全相同的 `camp_whitebox_v1` 坐标、正式角色/NPC、通行掩码和障碍。

- `a/`、`b/` 各有一张仅含地面、道路、贴地阴影的 RGBA 透明局部底图，以及五个整体实体：铁匠铺、货郎摊、长老树、北侧连续栅栏、西侧整体岩带。三个可绕行实体的 `_back` 与 `_front` 像素互斥；围栏、岩带只绘制可达侧的前沿。
- `manifest.json` 记录样板参考矩形、各实体矩形、深度脚底锚点和资源路径；坐标对应 `data/map_art/camp_whitebox_v1.json` 的 1672×941 参考画布。样板范围之外的纯色区域仅用于标出未制作区域。
- 源图位于 `art_source/environment/camp_style_sample/`。运行 `python3 tools/build_camp_style_sample.py` 可重建本目录 PNG 和清单；生成器要求 ImageMagick。
- 运行 `godot --path . --scene res://tests/CampStyleSample.tscn` 打开交互样板。F5/F6 切 A/B；F1–F4 切铁匠铺、长老树、岩石、栅栏观察点；F7/F8/F9 切 100%/150%/200%。正式游戏入口不引用该场景。

实际窗口截图和四项观察记录位于 `docs/素材设计/样板/幸存者营地AB/` 与 `docs/素材设计/17-幸存者营地AB局部样板验收记录.md`。
