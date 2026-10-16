# 余烬炉房

余烬炉房是第 2 章地图，承担探索、战斗与任务推进。 地形与路线：纵长熔坑把主线外炉与右端可选内炉分开，上下热管桥连通。

配置源：`map.json`；可通行布局见 `res://data/layouts/c2_ember_furnace.json`。
地图用途和设计说明可在本段人工编辑；下方参数区由工具同步。

<!-- MAP PARAMETERS START -->

| 参数 | 当前值 |
|---|---|
| 章节 | 第 2 章 |
| 地图 ID | c2_ember_furnace |
| 地图名称 | 余烬炉房 |
| 类型 | spoke |
| 所属城镇 | c2_well_town |
| 尺寸（格） | {"w":160,"h":90} |
| 等级范围 | [17,19] |
| 推荐等级 | 17 |
| 解锁条件 | chapter2 |
| 全图安全 | 否 |
| 入口落点 | {"from_works":[91,8]} |
| 马车落点 | [82,14] |
| 布局文件 | res://data/layouts/c2_ember_furnace.json |
| 布局版本 | 2026-10-14-landscape-v2 |

### 怪物刷新

刷新点 10 组；完整刷新格、区域和附加规则见 `map.json`。

| 怪物 ID | 等级 | 数量 | 重生秒数 | 类型 |
|---|---:|---:|---:|---|
| c2_ash_beast | 17 | 8 | 15 | 普通 |
| c2_copper_worm | 17 | 6 | 15 | 普通 |
| c2_slag_leech | 17 | 4 | 15 | 普通 |
| c2_ash_beast | 17 | 8 | 15 | 普通 |
| c2_copper_worm | 17 | 6 | 15 | 普通 |
| c2_slag_leech | 17 | 4 | 15 | 普通 |
| c2_ash_beast | 17 | 8 | 15 | 普通 |
| c2_copper_worm | 17 | 6 | 15 | 普通 |
| c2_slag_leech | 17 | 4 | 15 | 普通 |
| c2_elite_copper_matriarch | 17 | 1 | 120 | elite |

Boss 刷新：{"monsterId":"c2_boss_slag_devourer","level":18,"respawnTime":300,"count":1,"cell":[137,46],"kind":"boss","tombstone":true,"dropTableId":"DT_C2_Boss_Slag"}

### NPC

| 名称 | 职责 | 格坐标 |
|---|---|---|
| 驿站车夫 | carter | [82,11] |

### 步行出口

| 出口 | 目标地图 ID | 格坐标 | 解锁条件 |
|---|---|---|---|
| 回工坊下层 | c2_lower_works | [91,4] | 无 |

<!-- MAP PARAMETERS END -->
