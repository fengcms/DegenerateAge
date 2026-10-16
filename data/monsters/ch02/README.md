# 第2章怪物

本章定义 16 种具体怪物。其 `id` 是地图、任务、掉落与存档的稳定引用；刷新点可覆盖实际等级，不能因此把模板搬到其他章节。

<!-- MONSTER LIST START -->

| ID | 名称 | 模板等级 | 类型 | 掉落表 |
|---|---|---:|---|---|
| `c2_spirit_larva` | 汲灵幼虫 | 11 | 普通 | `DT_C2_Normal` |
| `c2_copper_worm` | 铜壳蠕虫 | 12 | 普通 | `DT_C2_Normal` |
| `c2_broken_guard` | 断链守卫 | 13 | 普通 | `DT_C2_Normal` |
| `c2_slag_leech` | 喷渣蛭 | 14 | 普通 | `DT_C2_Normal` |
| `c2_badge_wraith` | 工牌游魂 | 15 | 普通 | `DT_C2_Normal` |
| `c2_ash_beast` | 煤灰兽 | 17 | 普通 | `DT_C2_Normal` |
| `c2_spirit_attendant` | 汲灵侍虫 | 17 | 普通 | `DT_C2_Normal` |
| `c2_purple_parasite` | 紫脉寄生体 | 19 | 普通 | `DT_C2_Normal` |
| `c2_elite_copper_matriarch` | 铜壳母虫 | 13 | 精英 | `DT_C2_Elite` |
| `c2_elite_broken_inspector` | 断链巡检长 | 14 | 精英 | `DT_C2_Elite` |
| `c2_elite_gray_scribe` | 灰印书记 | 17 | 精英 | `DT_C2_Elite` |
| `c2_elite_spirit_guard` | 汲灵护卫 | 16 | 精英 | `DT_C2_Elite` |
| `c2_elite_ash_leader` | 煤灰头领 | 18 | 精英 | `DT_C2_Elite` |
| `c2_boss_iron_foreman` | 镇井监工·铁臂 | 15 | 首领 | `DT_C2_Boss` |
| `c2_boss_slag_devourer` | 炉渣吞噬者 | 18 | 首领 | `DT_C2_Boss_Slag` |
| `c2_boss_hundred_arm_extractor` | 百臂汲灵机 | 20 | 首领 | `DT_C2_Boss_Final` |

<!-- MONSTER LIST END -->

修改名称、等级、类型、掉落、能力或新增怪物时，同步维护本清单与设计用途；数值以 `monsters.json` 为唯一事实源。地图刷新点仍在 `data/maps/`，任务目标仍在 `data/quests.json`。
