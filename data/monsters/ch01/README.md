# 第1章怪物

本章定义 8 种具体怪物。其 `id` 是地图、任务、掉落与存档的稳定引用；刷新点可覆盖实际等级，不能因此把模板搬到其他章节。

<!-- MONSTER LIST START -->

| ID | 名称 | 模板等级 | 类型 | 掉落表 | 外观 ID |
|---|---|---:|---|---|---|
| `training_dummy` | 木桩怪 | 1 | 普通 | `` | `training_dummy` |
| `wolf_corrupted` | 腐化野狼 | 2 | 普通 | `DT_Wild_L1` | `wolf_corrupted` |
| `shellback_bug` | 裂壳虫 | 3 | 普通 | `DT_Shellback_L1` | `shellback_bug` |
| `ash_wraith` | 灰烬游魂 | 6 | 普通 | `DT_Ash_L1` | `ash_wraith` |
| `elite_ash_wraith` | 灰烬怨灵 | 8 | 精英 | `DT_Elite_L1` | `elite_ash_wraith` |
| `elite_shellback_bug` | 裂壳虫卫 | 8 | 精英 | `DT_Elite_L1` | `elite_shellback_bug` |
| `elite_wolf_king` | 裂爪狼王 | 4 | 精英 | `DT_Elite_L1` | `elite_wolf_king` |
| `boss_corrupted_beast` | 腐化巨兽 | 10 | 首领 | `DT_Boss_L1` | `boss_corrupted_beast` |

<!-- MONSTER LIST END -->

修改名称、等级、类型、掉落、能力或新增怪物时，同步维护本清单与设计用途；数值以 `monsters.json` 为唯一事实源。地图刷新点仍在 `data/maps/`，任务目标仍在 `data/quests.json`。
