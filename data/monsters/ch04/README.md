# 第4章怪物

本章定义 15 种具体怪物。其 `id` 是地图、任务、掉落与存档的稳定引用；刷新点可覆盖实际等级，不能因此把模板搬到其他章节。

<!-- MONSTER LIST START -->

| ID | 名称 | 模板等级 | 类型 | 掉落表 | 外观 ID |
|---|---|---:|---|---|---|
| `c4_normal01` | 根颚兽 | 31 | 普通 | `DT_C4_Normal` | `placeholder` |
| `c4_normal02` | 孢灯蛾 | 32 | 普通 | `DT_C4_Normal` | `placeholder` |
| `c4_normal03` | 枯信偶 | 33 | 普通 | `DT_C4_Normal` | `placeholder` |
| `c4_normal04` | 藤甲巡守 | 34 | 普通 | `DT_C4_Normal` | `placeholder` |
| `c4_normal05` | 折镜游魂 | 35 | 普通 | `DT_C4_Normal` | `placeholder` |
| `c4_normal06` | 泥苔蜥 | 36 | 普通 | `DT_C4_Normal` | `placeholder` |
| `c4_normal07` | 节根重兽 | 37 | 普通 | `DT_C4_Normal` | `placeholder` |
| `c4_normal08` | 哨塔寄藤 | 38 | 普通 | `DT_C4_Normal` | `placeholder` |
| `c4_elite01` | 千结根牙 | 34 | 精英 | `DT_C4_Elite` | `placeholder` |
| `c4_elite02` | 失声旗卫 | 35 | 精英 | `DT_C4_Elite` | `placeholder` |
| `c4_elite03` | 折光观测偶 | 36 | 精英 | `DT_C4_Elite` | `placeholder` |
| `c4_elite04` | 白孢母体 | 37 | 精英 | `DT_C4_Elite` | `placeholder` |
| `c4_boss01` | 无声巡林者 | 35 | 首领 | `DT_C4_Boss` | `placeholder` |
| `c4_boss02` | 孢灯育巢 | 38 | 首领 | `DT_C4_Boss` | `placeholder` |
| `c4_boss03` | 缠根守门者 | 40 | 首领 | `DT_C4_Boss` | `placeholder` |

<!-- MONSTER LIST END -->

修改名称、等级、类型、掉落、能力或新增怪物时，同步维护本清单与设计用途；数值以 `monsters.json` 为唯一事实源。地图刷新点仍在 `data/maps/`，任务目标仍在 `data/quests.json`。
