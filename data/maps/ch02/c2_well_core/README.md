# 井心机室

井心机室是第 2 章地图，承担探索、战斗与任务推进。 地形与路线：左侧外围与两翼维护回路，右侧主机场，与长轴一致推进。

配置源：`map.json`；可通行布局见 `res://data/layouts/c2_well_core.json`。
地图用途和设计说明可在本段人工编辑；下方参数区由工具同步。

<!-- MAP PARAMETERS START -->

| 参数 | 当前值 |
|---|---|
| 章节 | 第 2 章 |
| 地图 ID | c2_well_core |
| 地图名称 | 井心机室 |
| 类型 | spoke |
| 所属城镇 | c2_well_town |
| 尺寸（格） | {"w":208,"h":117} |
| 等级范围 | [18,20] |
| 推荐等级 | 18 |
| 解锁条件 | c2_backup_furnace |
| 全图安全 | 否 |
| 入口落点 | {"from_works":[9,58]} |
| 马车落点 | [18,68] |
| 布局文件 | res://data/layouts/c2_well_core.json |
| 布局版本 | 2026-10-14-landscape-v2 |

### 怪物刷新

刷新点 11 组；完整刷新格、区域和附加规则见 `map.json`。

| 怪物 ID | 等级 | 数量 | 重生秒数 | 类型 |
|---|---:|---:|---:|---|
| c2_purple_parasite | 19 | 6 | 15 | 普通 |
| c2_broken_guard | 18 | 4 | 15 | 普通 |
| c2_spirit_attendant | 18 | 2 | 15 | 普通 |
| c2_purple_parasite | 19 | 6 | 15 | 普通 |
| c2_broken_guard | 18 | 4 | 15 | 普通 |
| c2_spirit_attendant | 18 | 2 | 15 | 普通 |
| c2_purple_parasite | 19 | 6 | 15 | 普通 |
| c2_broken_guard | 18 | 4 | 15 | 普通 |
| c2_spirit_attendant | 18 | 2 | 15 | 普通 |
| c2_elite_spirit_guard | 18 | 1 | 120 | elite |
| c2_elite_ash_leader | 18 | 1 | 120 | elite |

Boss 刷新：{"monsterId":"c2_boss_hundred_arm_extractor","level":20,"respawnTime":600,"count":1,"cell":[177,58],"kind":"boss","tombstone":true,"requiresUnlock":"c2_core_access","dropTableId":"DT_C2_Boss_Final"}

### NPC

| 名称 | 职责 | 格坐标 |
|---|---|---|
| 驿站车夫 | carter | [18,65] |

### 步行出口

| 出口 | 目标地图 ID | 格坐标 | 解锁条件 |
|---|---|---|---|
| 回工坊下层 | c2_lower_works | [5,58] | 无 |

<!-- MAP PARAMETERS END -->
