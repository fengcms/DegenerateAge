# 11—51 级主角形象审稿与源稿索引

五档形象以已批准的初始角色为同一人物基准；用户指出剑柄与刀剑轴线错位后，已逐张修正。**`*_final.png` 为修正版，`*_concept.png` 为修正前对照。**这两类全身图只作美术设计与制图源稿，游戏使用 `assets/sprites/player/stage_looks/` 下的独立小图集。

| 起点 | 修正版全身图 | 256×400 面板候选 | 八向站姿源稿 |
|---|---|---|---|
| Lv11 | `look_02_lv11_final.png` | `look_02_panel_256x400.png` | `art_source/player/look_02/idle_8dir_master.png` |
| Lv21 | `look_03_lv21_final.png` | `look_03_panel_256x400.png` | `art_source/player/look_03/idle_8dir_master.png` |
| Lv31 | `look_04_lv31_final.png` | `look_04_panel_256x400.png` | `art_source/player/look_04/idle_8dir_master.png` |
| Lv41 | `look_05_lv41_final.png` | `look_05_panel_256x400.png` | `art_source/player/look_05/idle_8dir_master.png` |
| Lv51 | `look_06_lv51_final.png` | `look_06_panel_256x400.png` | `art_source/player/look_06/idle_8dir_master.png` |

五张面板图为真实透明 RGBA、256×400，按最近邻从修正版全身稿导出；不是世界 64×80 首帧放大，现已复制到 `assets/ui/portraits/` 并随对应武器更换。每档还制作了八向站立、四步行走、攻击接触与收势、受击、打坐、倒地母版；起势源稿另存供未来调整攻击时间轴。所有运行图集由 `tools/build_player_stage_looks.gd` 统一裁切、清除低透明噪点、对齐脚底并打包。`look_06` 行走母版最后一排有截脚，运行图集跳过这一排，复用第二步。

创作提示词要点：同一黑发年轻守护者与旧沙色围巾；按章节依次加入井镇旧铁/暖灯、渠铜测量布/圆盾、林海短绿披肩/红色邮签、边境深铁重甲/撤离军旗、镇脉灰白旧石/暖金旁路。画布透明、复古像素簇、左上主光、完整全身；武器握柄—护手—刃身同轴，避免错手、断刃、斜接；禁止现代机械、全身紫化、神环和大面积发光。八向源稿额外要求 `s, sw, w, nw, n, ne, e, se` 顺序、足底同线与各列留白。

详细剧情映射、世界帧验收规格与目前尚缺的动作见[制作记录](../../18-11至51级主角阶段形象定稿与制作记录.md)。
