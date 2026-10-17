# 第5章怪物

本章定义 18 种具体怪物。其 `id` 是地图、任务、掉落与存档的稳定引用；刷新点可覆盖实际等级，不能因此把模板搬到其他章节。

<!-- MONSTER LIST START -->

| ID | 名称 | 模板等级 | 类型 | 掉落表 | 外观 ID |
|---|---|---:|---|---|---|
| `c5_normal01` | 潮甲步卒 | 41 | 普通 | `DT_C5_Normal` | `c5_normal01` |
| `c5_normal02` | 裂矢猎手 | 42 | 普通 | `DT_C5_Normal` | `c5_normal02` |
| `c5_normal03` | 负舟兽 | 43 | 普通 | `DT_C5_Normal` | `c5_normal03` |
| `c5_normal04` | 空旗游魂 | 44 | 普通 | `DT_C5_Normal` | `c5_normal04` |
| `c5_normal05` | 紫鳞潜猎者 | 45 | 普通 | `DT_C5_Normal` | `c5_normal05` |
| `c5_normal06` | 潮盾卫 | 46 | 普通 | `DT_C5_Normal` | `c5_normal06` |
| `c5_normal07` | 缚索虫 | 47 | 普通 | `DT_C5_Normal` | `c5_normal07` |
| `c5_normal08` | 折翼掠兽 | 48 | 普通 | `DT_C5_Normal` | `c5_normal08` |
| `c5_normal09` | 裂痕重斧手 | 49 | 普通 | `DT_C5_Normal` | `c5_normal09` |
| `c5_elite01` | 双旗斩卫 | 44 | 精英 | `DT_C5_Elite` | `c5_elite01` |
| `c5_elite02` | 潮壳驮将 | 45 | 精英 | `DT_C5_Elite` | `c5_elite02` |
| `c5_elite03` | 缚索祭司 | 46 | 精英 | `DT_C5_Elite` | `c5_elite03` |
| `c5_elite04` | 裂箭哨长 | 47 | 精英 | `DT_C5_Elite` | `c5_elite04` |
| `c5_elite05` | 回潮斧首 | 48 | 精英 | `DT_C5_Elite` | `c5_elite05` |
| `c5_boss01` | 驭潮号将 | 45 | 首领 | `DT_C5_Boss` | `c5_boss01` |
| `c5_boss02` | 裂舟噬骨者 | 47 | 首领 | `DT_C5_Boss` | `c5_boss02` |
| `c5_boss03` | 逆风军团长 | 49 | 首领 | `DT_C5_Boss` | `c5_boss03` |
| `c5_boss04` | 裂隙统帅·执灯者 | 50 | 首领 | `DT_C5_Boss` | `c5_boss04` |

<!-- MONSTER LIST END -->

修改名称、等级、类型、掉落、能力或新增怪物时，同步维护本清单与设计用途；数值以 `monsters.json` 为唯一事实源。地图刷新点仍在 `data/maps/`，任务目标仍在 `data/quests.json`。
