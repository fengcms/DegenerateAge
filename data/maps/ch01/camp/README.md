# 幸存者营地

营地 NPC 周围为矩形安全区；区外可以战斗。

配置源：`map.json`；可通行布局见 `res://data/layouts/camp.json`。
地图用途和设计说明可在本段人工编辑；下方参数区由工具同步。

<!-- MAP PARAMETERS START -->

| 参数 | 当前值 |
|---|---|
| 章节 | 第 1 章 |
| 地图 ID | camp |
| 地图名称 | 幸存者营地 |
| 类型 | hub |
| 所属城镇 | camp |
| 尺寸（格） | {"w":110,"h":110} |
| 等级范围 | [1,1] |
| 推荐等级 | 1 |
| 解锁条件 |  |
| 安全区 | {"min":[43,33],"max":[75,79]} |
| 全图安全 | 是 |
| 入口落点 | {"from_wild":[76,33],"from_c2":[76,77]} |
| 马车连接 | ["c2_well_town"] |
| 马车费用 | {"spoke":50,"hub":150} |
| 指定目的地费用 | {"wild_trial":0,"ash_land":50,"corruption_source":150,"c2_well_town":200} |
| 马车落点 | [48,34] |
| 布局文件 | res://data/layouts/camp.json |
| 布局版本 | 2026-10-16-camp-open-perimeter-v2 |

### 怪物刷新

刷新点 1 组；完整刷新格、区域和附加规则见 `map.json`。

| 怪物 ID | 等级 | 数量 | 重生秒数 | 类型 |
|---|---:|---:|---:|---|
| training_dummy | 1 | 3 | 20 | 普通 |

Boss 刷新：无

### NPC

| 名称 | 职责 | 格坐标 |
|---|---|---|
| peddler_camp | shop | [43,63] |
| 长老 | quest | [64,48] |
| 铁匠 | blacksmith | [49,78] |
| 仓库管理员 | warehouse | [72,56] |
| 车夫 | carter | [46,33] |

### 步行出口

| 出口 | 目标地图 ID | 格坐标 | 解锁条件 |
|---|---|---|---|
| 往试炼野外 | wild_trial | [79,31] | 无 |
| 往沉井镇 | c2_well_town | [81,81] | 无 |

<!-- MAP PARAMETERS END -->
