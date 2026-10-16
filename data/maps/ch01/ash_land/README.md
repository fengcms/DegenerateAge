# 灰烬之地

第一章中间图，6 只普通怪与 2 只精英怪，远程怪登场。

配置源：`map.json`；可通行布局见 `res://data/layouts/ash_land.json`。
地图用途和设计说明可在本段人工编辑；下方参数区由工具同步。

<!-- MAP PARAMETERS START -->

| 参数 | 当前值 |
|---|---|
| 章节 | 第 1 章 |
| 地图 ID | ash_land |
| 地图名称 | 灰烬之地 |
| 类型 | spoke |
| 所属城镇 | camp |
| 尺寸（格） | {"w":192,"h":108} |
| 等级范围 | [5,9] |
| 推荐等级 | 6 |
| 解锁条件 |  |
| 全图安全 | 否 |
| 入口落点 | {"from_wild":[9,54],"from_source":[183,54]} |
| 指定目的地费用 | {"camp":70,"wild_trial":50,"corruption_source":100} |
| 马车落点 | [17,61] |
| 布局文件 | res://data/layouts/ash_land.json |
| 布局版本 | 2026-10-14-landscape-v2 |

### 怪物刷新

刷新点 4 组；完整刷新格、区域和附加规则见 `map.json`。

| 怪物 ID | 等级 | 数量 | 重生秒数 | 类型 |
|---|---:|---:|---:|---|
| ash_wraith | 6 | 3 | 45 | 普通 |
| shellback_bug | 7 | 3 | 45 | 普通 |
| elite_ash_wraith | 8 | 1 | 120 | elite |
| elite_shellback_bug | 9 | 1 | 120 | elite |

Boss 刷新：无

### NPC

| 名称 | 职责 | 格坐标 |
|---|---|---|
| peddler_ash | shop | [20,58] |
| 车夫 | carter | [17,58] |

### 步行出口

| 出口 | 目标地图 ID | 格坐标 | 解锁条件 |
|---|---|---|---|
| 回试炼野外 | wild_trial | [5,54] | 无 |
| 往腐化源头 | corruption_source | [187,54] | 无 |

<!-- MAP PARAMETERS END -->
