# 试炼野外

第一章第一张野外图，含精英裂爪狼王。

配置源：`map.json`；可通行布局见 `res://data/layouts/wild_trial.json`。
地图用途和设计说明可在本段人工编辑；下方参数区由工具同步。

<!-- MAP PARAMETERS START -->

| 参数 | 当前值 |
|---|---|
| 章节 | 第 1 章 |
| 地图 ID | wild_trial |
| 地图名称 | 试炼野外 |
| 类型 | spoke |
| 所属城镇 | camp |
| 尺寸（格） | {"w":176,"h":99} |
| 等级范围 | [1,5] |
| 推荐等级 | 2 |
| 解锁条件 |  |
| 全图安全 | 否 |
| 入口落点 | {"from_camp":[8,50],"from_ash":[168,50]} |
| 指定目的地费用 | {"camp":20,"ash_land":50,"corruption_source":150} |
| 马车落点 | [15,55] |
| 布局文件 | res://data/layouts/wild_trial.json |
| 布局版本 | 2026-10-14-landscape-v2 |

### 怪物刷新

刷新点 3 组；完整刷新格、区域和附加规则见 `map.json`。

| 怪物 ID | 等级 | 数量 | 重生秒数 | 类型 |
|---|---:|---:|---:|---|
| wolf_corrupted | 2 | 6 | 30 | 普通 |
| shellback_bug | 3 | 2 | 30 | 普通 |
| elite_wolf_king | 4 | 1 | 120 | elite |

Boss 刷新：无

### NPC

| 名称 | 职责 | 格坐标 |
|---|---|---|
| 车夫 | carter | [15,52] |

### 步行出口

| 出口 | 目标地图 ID | 格坐标 | 解锁条件 |
|---|---|---|---|
| 回幸存者营地 | camp | [4,50] | 无 |
| 往灰烬之地 | ash_land | [172,50] | 无 |

<!-- MAP PARAMETERS END -->
