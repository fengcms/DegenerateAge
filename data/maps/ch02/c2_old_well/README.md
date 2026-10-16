# 旧汲灵井

旧汲灵井是第 2 章地图，承担探索、战斗与任务推进。 地形与路线：两座干井横向并列，平台上下贯通，最右端是监工调压台。

配置源：`map.json`；可通行布局见 `res://data/layouts/c2_old_well.json`。
地图用途和设计说明可在本段人工编辑；下方参数区由工具同步。

<!-- MAP PARAMETERS START -->

| 参数 | 当前值 |
|---|---|
| 章节 | 第 2 章 |
| 地图 ID | c2_old_well |
| 地图名称 | 旧汲灵井 |
| 类型 | spoke |
| 所属城镇 | c2_well_town |
| 尺寸（格） | {"w":224,"h":126} |
| 等级范围 | [13,15] |
| 推荐等级 | 13 |
| 解锁条件 | chapter2 |
| 全图安全 | 否 |
| 入口落点 | {"from_slope":[10,63],"from_works":[214,63]} |
| 马车落点 | [21,70] |
| 布局文件 | res://data/layouts/c2_old_well.json |
| 布局版本 | 2026-10-14-landscape-v2 |

### 怪物刷新

刷新点 15 组；完整刷新格、区域和附加规则见 `map.json`。

| 怪物 ID | 等级 | 数量 | 重生秒数 | 类型 |
|---|---:|---:|---:|---|
| c2_spirit_larva | 13 | 10 | 15 | 普通 |
| c2_copper_worm | 13 | 8 | 15 | 普通 |
| c2_broken_guard | 13 | 8 | 15 | 普通 |
| c2_slag_leech | 14 | 4 | 15 | 普通 |
| c2_spirit_larva | 13 | 10 | 15 | 普通 |
| c2_copper_worm | 13 | 8 | 15 | 普通 |
| c2_broken_guard | 13 | 8 | 15 | 普通 |
| c2_slag_leech | 14 | 4 | 15 | 普通 |
| c2_spirit_larva | 13 | 10 | 15 | 普通 |
| c2_copper_worm | 13 | 8 | 15 | 普通 |
| c2_broken_guard | 13 | 8 | 15 | 普通 |
| c2_slag_leech | 14 | 4 | 15 | 普通 |
| c2_elite_copper_matriarch | 13 | 1 | 120 | elite |
| c2_elite_broken_inspector | 14 | 1 | 120 | elite |
| c2_elite_spirit_guard | 15 | 1 | 120 | elite |

Boss 刷新：{"monsterId":"c2_boss_iron_foreman","level":15,"respawnTime":300,"count":1,"cell":[192,64],"kind":"boss","tombstone":true}

### NPC

| 名称 | 职责 | 格坐标 |
|---|---|---|
| 驿站车夫 | carter | [21,67] |

### 步行出口

| 出口 | 目标地图 ID | 格坐标 | 解锁条件 |
|---|---|---|---|
| 回断管坡 | c2_pipe_slope | [6,63] | 无 |
| 往工坊下层 | c2_lower_works | [218,63] | 无 |

<!-- MAP PARAMETERS END -->
