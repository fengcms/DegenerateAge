# 腐化源头

第一章 Boss 区，8 只普通怪、4 只精英怪及腐化巨兽；Boss 死亡生成墓碑倒计时。

配置源：`map.json`；可通行布局见 `res://data/layouts/corruption_source.json`。
地图用途和设计说明可在本段人工编辑；下方参数区由工具同步。

<!-- MAP PARAMETERS START -->

| 参数 | 当前值 |
|---|---|
| 章节 | 第 1 章 |
| 地图 ID | corruption_source |
| 地图名称 | 腐化源头 |
| 类型 | spoke |
| 所属城镇 | camp |
| 尺寸（格） | {"w":160,"h":90} |
| 等级范围 | [10,10] |
| 推荐等级 | 10 |
| 解锁条件 |  |
| 全图安全 | 否 |
| 入口落点 | {"from_ash":[8,45]} |
| 指定目的地费用 | {"camp":170,"wild_trial":150,"ash_land":100} |
| 马车落点 | [14,52] |
| 布局文件 | res://data/layouts/corruption_source.json |
| 布局版本 | 2026-10-14-landscape-v2 |

### 怪物刷新

刷新点 4 组；完整刷新格、区域和附加规则见 `map.json`。

| 怪物 ID | 等级 | 数量 | 重生秒数 | 类型 |
|---|---:|---:|---:|---|
| shellback_bug | 10 | 5 | 60 | 普通 |
| ash_wraith | 10 | 3 | 60 | 普通 |
| elite_ash_wraith | 10 | 2 | 120 | elite |
| elite_shellback_bug | 10 | 2 | 120 | elite |

Boss 刷新：{"monsterId":"boss_corrupted_beast","level":10,"respawnTime":300,"tombstone":true}

### NPC

| 名称 | 职责 | 格坐标 |
|---|---|---|
| 车夫 | carter | [14,49] |

### 步行出口

| 出口 | 目标地图 ID | 格坐标 | 解锁条件 |
|---|---|---|---|
| 回灰烬之地 | ash_land | [4,45] | 无 |

<!-- MAP PARAMETERS END -->
