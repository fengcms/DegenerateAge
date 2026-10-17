# 第6章怪物

本章定义 15 种具体怪物。其 `id` 是地图、任务、掉落与存档的稳定引用；刷新点可覆盖实际等级，不能因此把模板搬到其他章节。

<!-- MONSTER LIST START -->

| ID | 名称 | 模板等级 | 类型 | 掉落表 | 外观 ID |
|---|---|---:|---|---|---|
| `c6_normal01` | 裂纹卫体 | 51 | 普通 | `DT_C6_Normal` | `c6_normal01` |
| `c6_normal02` | 漏光螯虫 | 52 | 普通 | `DT_C6_Normal` | `c6_normal02` |
| `c6_normal03` | 失序刻印偶 | 53 | 普通 | `DT_C6_Normal` | `c6_normal03` |
| `c6_normal04` | 黑脉攀附体 | 54 | 普通 | `DT_C6_Normal` | `c6_normal04` |
| `c6_normal05` | 守库铜卫 | 55 | 普通 | `DT_C6_Normal` | `c6_normal05` |
| `c6_normal06` | 断誓游魂 | 56 | 普通 | `DT_C6_Normal` | `c6_normal06` |
| `c6_normal07` | 空环重体 | 57 | 普通 | `DT_C6_Normal` | `c6_normal07` |
| `c6_normal08` | 紫核析出体 | 58 | 普通 | `DT_C6_Normal` | `c6_normal08` |
| `c6_elite01` | 裂印执守 | 54 | 精英 | `DT_C6_Elite` | `c6_elite01` |
| `c6_elite02` | 回廊镇卫 | 55 | 精英 | `DT_C6_Elite` | `c6_elite02` |
| `c6_elite03` | 漏光母壳 | 56 | 精英 | `DT_C6_Elite` | `c6_elite03` |
| `c6_elite04` | 无名誓影 | 57 | 精英 | `DT_C6_Elite` | `c6_elite04` |
| `c6_boss01` | 守誓审判体 | 55 | 首领 | `DT_C6_Boss` | `c6_boss01` |
| `c6_boss02` | 前代残响 | 58 | 首领 | `DT_C6_Boss` | `c6_boss02` |
| `c6_boss03` | 裂隙主宰·空天之眼 | 60 | 首领 | `DT_C6_Boss` | `c6_boss03` |

<!-- MONSTER LIST END -->

修改名称、等级、类型、掉落、能力或新增怪物时，同步维护本清单与设计用途；数值以 `monsters.json` 为唯一事实源。地图刷新点仍在 `data/maps/`，任务目标仍在 `data/quests.json`。
