# 第3章怪物

本章定义 15 种具体怪物。其 `id` 是地图、任务、掉落与存档的稳定引用；刷新点可覆盖实际等级，不能因此把模板搬到其他章节。

<!-- MONSTER LIST START -->

| ID | 名称 | 模板等级 | 类型 | 掉落表 | 外观 ID |
|---|---|---:|---|---|---|
| `c3_normal01` | 砂背螯虫 | 21 | 普通 | `DT_C3_Normal` | `placeholder` |
| `c3_normal02` | 窃水獾 | 22 | 普通 | `DT_C3_Normal` | `placeholder` |
| `c3_normal03` | 枯渠游魂 | 23 | 普通 | `DT_C3_Normal` | `placeholder` |
| `c3_normal04` | 铆钉巡卫 | 24 | 普通 | `DT_C3_Normal` | `placeholder` |
| `c3_normal05` | 盐晶蚀蛾 | 25 | 普通 | `DT_C3_Normal` | `placeholder` |
| `c3_normal06` | 干井潜蜥 | 26 | 普通 | `DT_C3_Normal` | `placeholder` |
| `c3_normal07` | 抄令傀儡 | 27 | 普通 | `DT_C3_Normal` | `placeholder` |
| `c3_normal08` | 铜渠寄生体 | 28 | 普通 | `DT_C3_Normal` | `placeholder` |
| `c3_elite01` | 背闸虫王 | 24 | 精英 | `DT_C3_Elite` | `placeholder` |
| `c3_elite02` | 巡渠铜卫 | 25 | 精英 | `DT_C3_Elite` | `placeholder` |
| `c3_elite03` | 缄默执笔者 | 26 | 精英 | `DT_C3_Elite` | `placeholder` |
| `c3_elite04` | 旱井吞砂兽 | 27 | 精英 | `DT_C3_Elite` | `placeholder` |
| `c3_boss01` | 闸印守卫 | 25 | 首领 | `DT_C3_Boss` | `placeholder` |
| `c3_boss02` | 沉沙母螯 | 28 | 首领 | `DT_C3_Boss` | `placeholder` |
| `c3_boss03` | 空壳总督 | 30 | 首领 | `DT_C3_Boss` | `placeholder` |

<!-- MONSTER LIST END -->

修改名称、等级、类型、掉落、能力或新增怪物时，同步维护本清单与设计用途；数值以 `monsters.json` 为唯一事实源。地图刷新点仍在 `data/maps/`，任务目标仍在 `data/quests.json`。
