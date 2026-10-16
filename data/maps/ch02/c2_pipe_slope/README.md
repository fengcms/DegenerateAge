# 断管坡

断管坡是第 2 章地图，承担探索、战斗与任务推进。 地形与路线：横向山坡由两段错位断崖分隔，主管路与废料回路并行。

配置源：`map.json`；可通行布局见 `res://data/layouts/c2_pipe_slope.json`。
地图用途和设计说明可在本段人工编辑；下方参数区由工具同步。

<!-- MAP PARAMETERS START -->

| 参数 | 当前值 |
|---|---|
| 章节 | 第 2 章 |
| 地图 ID | c2_pipe_slope |
| 地图名称 | 断管坡 |
| 类型 | spoke |
| 所属城镇 | c2_well_town |
| 尺寸（格） | {"w":192,"h":108} |
| 等级范围 | [11,13] |
| 推荐等级 | 11 |
| 解锁条件 | chapter2 |
| 全图安全 | 否 |
| 入口落点 | {"from_town":[9,54],"from_well":[183,54]} |
| 马车落点 | [17,62] |
| 布局文件 | res://data/layouts/c2_pipe_slope.json |
| 布局版本 | 2026-10-14-landscape-v2 |

### 怪物刷新

刷新点 14 组；完整刷新格、区域和附加规则见 `map.json`。

| 怪物 ID | 等级 | 数量 | 重生秒数 | 类型 |
|---|---:|---:|---:|---|
| c2_spirit_larva | 11 | 11 | 15 | 普通 |
| c2_copper_worm | 12 | 5 | 15 | 普通 |
| c2_broken_guard | 13 | 5 | 15 | 普通 |
| c2_spirit_larva | 11 | 11 | 15 | 普通 |
| c2_copper_worm | 12 | 5 | 15 | 普通 |
| c2_broken_guard | 13 | 5 | 15 | 普通 |
| c2_spirit_larva | 11 | 10 | 15 | 普通 |
| c2_copper_worm | 12 | 6 | 15 | 普通 |
| c2_broken_guard | 13 | 5 | 15 | 普通 |
| c2_spirit_larva | 11 | 10 | 15 | 普通 |
| c2_copper_worm | 12 | 5 | 15 | 普通 |
| c2_broken_guard | 13 | 6 | 15 | 普通 |
| c2_elite_copper_matriarch | 13 | 1 | 120 | elite |
| c2_elite_broken_inspector | 13 | 1 | 120 | elite |

Boss 刷新：无

### NPC

| 名称 | 职责 | 格坐标 |
|---|---|---|
| 驿站车夫 | carter | [17,59] |
| 石岑 | quest | [21,59] |

### 步行出口

| 出口 | 目标地图 ID | 格坐标 | 解锁条件 |
|---|---|---|---|
| 回沉井镇 | c2_well_town | [5,54] | 无 |
| 往旧汲灵井 | c2_old_well | [187,54] | 无 |

<!-- MAP PARAMETERS END -->
