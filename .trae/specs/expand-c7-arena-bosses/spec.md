# 无尽回廊（c7_arena）扩席与场地改造 Spec

> 变更 id：`expand-c7-arena-bosses`
> 地图：`data/maps/ch07/c7_arena/`（玩家口中的「无尽回廊」）
> 关联设计：`docs/产品文档/13-满级后循环玩法（循环装备·循环Boss·随身三件套）.md`、`docs/工程文档/43-M10-3循环Boss图实施方案.md`

## Why

现状 `c7_arena` 有两个明显体验缺陷，均由**掩码几何**与**Boss 席位派生方式**直接导致：

1. **可走区域过少**：掩码 = 外椭圆(48,24) − 内椭圆(40,16) 的细环（宽约 8 格）+ 5 个半径 8 的小圆盘。实测可走 **2,197 / 14,400 格 = 15.3%**，85% 的地图是墙。
2. **Boss 间距过小**：10 条 `bossSpawns` 由脚本按「厅心 ±4 格」成对派生，同组两只**格距仅 8 格**。在 `Iso` 的 2:1 等距投影下 `Δcol=8` 折算世界距离仅 **286px**，且投影沿不同方向压缩不一致（同一格距在不同朝向的世界距离差可达 25%），**格数不是间距的正确度量**。

目标：在不改变「满级循环挑战场」玩法定位的前提下，把可走面积大幅提升、把 **20 席** Boss 在**世界像素尺度**上真正拉开。

## What Changes

- **掩码几何换挡（方案 B，无区厅）**：`tools/build_c7_arena_layout.py` 中 `OUTER` 由 `(48.0, 24.0)` 改为 **`(72.0, 38.0)`**，`INNER` 由 `(40.0, 16.0)` 改为 **`(20.0, 11.0)`**；删除 `HALL_RING / HALL_ANGLES / HALL_RADIUS` 与 `hall_centers()`，`is_walkable()` 退化为 **「环形走廊 ∨ 西门走廊」** 两个部件。`CENTER = (80.0, 45.0)`、`WEST_CORRIDOR = (4, 40, 42, 48)` 保持不变。
  - 效果：可走 **2,197 → 7,936 格（15.3% → 55.1%）**。中心保留一片不可走「内核」（内椭圆 20×11，约 690 格），外圈保留完整边界留白。
- **Boss 席位 10 → 20**：`data/maps/ch07/c7_arena/map.json` 的 `bossSpawns` 写入 **20 条**（冻结坐标见下方「冻结席位表」），`bossCap` 由 `10` 改为 **`20`**，`desc` 由「环形回廊串起五区十席……」改写为不含「五区十席」的新文案。
  - 20 席坐标经**全局最远点采样 + 掩码腐蚀 6 格净空约束**选出，**世界尺度最小间距 544px**（未腐蚀口径 643px），较现状 286px 提升约 1.9 倍。
  - **形象不新增**：沿用 `data/endgame.json` 现有 10 条 `arenaBosses`，每只出现 2 次。同名两只以 `ordinal 0/1` 各占一条血条（`tests/boss_multi_target_test.gd` 已覆盖该行为），`endgame.json` **零改动**。
- **掩码产物重建**：重跑 `tools/build_c7_arena_layout.py` 生成 `data/layouts/c7_arena.json`。脚本自身断言「出口 / 车夫落点 / 全部 20 个 `spawn%03d` 可走」与「可走格四邻接全连通」，无需额外人工校验。
- **门禁契约不变**：出口格 `[8,45]`、`entrances.from_c6_map00`、`carterArrival [10,45]`、`exits/entrances/levelFromPlayer.minLevel:60/unclaimedLootCap:200/carterFares` 全部保持原值；`[8,45]` 落在西门走廊 `4≤x≤40 ∧ 42≤y≤48` 内，新几何下仍可走。
- **不改动的部分（已核实）**：`autoload/data_loader.gd` 的 `bossSpawns` 校验（允许同 `monsterId` 在 `bossSpawns` 内重复——c7_arena 无 `spawnPoints`，非「Boss 与普通点不重叠」约束的适用对象）；`scripts/world/spawner.gd`（`ACTIVE_DISTANCE=760px`、`RETIRE_DISTANCE=1100`、`MIN_SPAWN_DIST=220`、`key = map_id#monster_id#ordinal`、`_level_min` 跟随玩家等级）；`data/endgame.json`；`data/dropTables.json` 的 `DT_C7_Arena_Boss`；存档字段与既有存档。
- **测试断言同步（BREAKING：既有断言放宽）**：`tests/arena_map_test.gd`、`tests/boss_multi_target_test.gd`、`tests/boss_token_test.gd` 中写死的 `10` 全部改 `20`；`TOTAL_BOSS_ROWS` 由 `27`（17 单点 + c7_arena 10）改 **`37`**；`group` 断言由「5 区各恰好 2 只」放宽为「5 区各恰好 4 只」。
  - 注：`group` 字段**仅作数据标注**，运行时无任何代码读取；其唯一消费者是 `arena_map_test.gd` 的分组计数断言。
- **文档同步**：按 `AGENT.md` §4 强制要求补齐 `data/maps/ch07/c7_arena/README.md`（当前缺失），并同步 `docs/产品文档/13`、`docs/工程文档/43` 中关于「10 只 Boss / 五区十席 / bossCap 10 / 可走 2,197 格 / 几何常量」的表述。新增独立交付文档 `docs/工程文档/55-无尽回廊（c7_arena）扩席与场地改造记录.md`。

### 冻结席位表（20 席，方案 B 几何下唯一事实源）

下表为写入 `data/maps/ch07/c7_arena/map.json` `bossSpawns` 的**完整、冻结**内容。每条除表中字段外，另附固定字段
`"kind":"boss", "respawnTime":600, "tombstone":true, "scaleStats":true, "xpFromCurve":true, "dropTableId":"DT_C7_Arena_Boss"`。

| # | monsterId | cell | group | | # | monsterId | cell | group |
|---|---|---|---|---|---|---|---|---|
| 0 | `c6_boss03` | `[19,57]` | A | | 10 | `c6_boss03` | `[59,15]` | C |
| 1 | `c6_boss02` | `[23,39]` | A | | 11 | `c6_boss02` | `[86,28]` | C |
| 2 | `c5_boss04` | `[39,70]` | A | | 12 | `c5_boss04` | `[106,48]` | D |
| 3 | `c4_boss02` | `[44,57]` | A | | 13 | `c4_boss02` | `[119,70]` | D |
| 4 | `c3_boss02` | `[29,26]` | B | | 14 | `c3_boss02` | `[96,14]` | D |
| 5 | `boss_corrupted_beast` | `[59,55]` | B | | 15 | `boss_corrupted_beast` | `[131,65]` | D |
| 6 | `c2_boss_iron_foreman` | `[57,37]` | B | | 16 | `c2_boss_iron_foreman` | `[123,46]` | E |
| 7 | `c2_boss_slag_devourer` | `[75,75]` | B | | 17 | `c2_boss_slag_devourer` | `[118,19]` | E |
| 8 | `c2_boss_hundred_arm_extractor` | `[45,18]` | C | | 18 | `c2_boss_hundred_arm_extractor` | `[143,53]` | E |
| 9 | `c5_boss02` | `[89,61]` | C | | 19 | `c5_boss02` | `[143,36]` | E |

**筛选口径**：以「掩码腐蚀 6 格」后的可行域做全局最远点采样（farthest-point），取 20 个样本点。
**已校验**：20 个 `cell` 逐个代入 `is_walkable()`（方案 B 几何）均判定为可走；同名两只分处场地两端（同名最近一对间距 2,183px）。
**`group` 语义**：按上表索引每 4 席一组（0–3 = A，4–7 = B，8–11 = C，12–15 = D，16–19 = E）；纯数据标注，运行时无消费者。

## Impact

- **受影响规格（capabilities）**：地图与遭遇设计（`AGENT.md` §4）、性能架构（`AGENT.md` §2）、满级后循环玩法（产品文档 13）、M10-3 循环 Boss 图（工程文档 43）。
- **受影响代码/数据**：
  - `tools/build_c7_arena_layout.py`（几何常量 + 文件头注释 + `is_walkable`）
  - `data/maps/ch07/c7_arena/map.json`（`bossSpawns` ×20、`bossCap`、`desc`、`layoutVersion`）
  - `data/layouts/c7_arena.json`（脚本重跑产物，不手改）
  - `tests/arena_map_test.gd`、`tests/boss_multi_target_test.gd`、`tests/boss_token_test.gd`
  - `data/maps/ch07/README.md`、`data/maps/ch07/c7_arena/README.md`
  - `docs/产品文档/13-…md`、`docs/工程文档/43-…md`
- **不影响**：`spawner.gd`、`data_loader.gd`、`map_service.gd`、`cave_layout.gd`、`cave_navigator.gd`、`flat_tile_mesh.gd`、`map_canvas.gd`、`ground.gd`、`endgame.json`、`dropTables.json`、存档结构与既有存档。

### 性能影响（`AGENT.md` §2 不可退项，必须实测并留档）

| 项目 | 现状 | 改造后 | 说明 |
|---|---|---|---|
| 可走格 | 2,197 | 7,936（3.61×） | 影响地面瓦片数、静态同色地形合批顶点数、不可走格碰撞轮廓段数 |
| 同时活动 Boss 上限 | `bossCap: 10` | `bossCap: 20` | 受 `ACTIVE_DISTANCE=760px` 限制，同屏实际远小于 20 |
| 掩码「0」格 | 12,203 | 6,464 | 障碍边界的碰撞轮廓段数学上应减少，但需实测确认 |

架构本身不退化：小地图底图仍按「静态底图 + 动态标记分层」，静态同色地形仍走合批网格（`scripts/systems/flat_tile_mesh.gd`），玩家移动不重建底图。**仅"数据量"变化，不引入新的逐格绘制路径。** 因此验收必须给出改造前后的 `MapRenderBenchmark` 绘制调用/耗时对照，而不是只跑逻辑测试。

### 风险

1. **未领取掉落上限**：`DT_C7_Arena_Boss` 每只 Boss 掉约 9–12 件（coin 3,000–3,400 100%；`c6_normal` 5–8 件 common70/uncommon30；`c6_normal` 2 件 rare75/epic25；`c6_legendary` 1 件 5%；红蓝药各 2；符石 30%）。20 只满场未领取可达 180–240 件，已接近 `unclaimedLootCap: 200`。**本次决策：保持 200 不变**（用户拍板），先观察真实挂机表现，若确认触顶另开变更单独评估。
2. **20 席共用 10 个形象**：同名两只在追踪令牌中被视为两条独立记录（不同 `ordinal`），`TOTAL_BOSS_ROWS` 由 27 → 37。**持有旧令牌的存档不需要迁移**：令牌按 `map_id#monster_id#ordinal` 存储，新增的是新的 `ordinal` 行，旧行仍然有效。
3. **小地图/大地图底图重建成本**：可走格数 3.6×，首次打开大地图与首次进入地图的网格构建/上传尖峰需实测。

## ADDED Requirements

### Requirement: 20 席 Boss 席位与场地几何
`c7_arena` SHALL 在 `bossSpawns` 中登记 **20** 条 `kind:"boss"` 规格，且每条 `cell` MUST 落在当前掩码的可走格上；`bossCap` MUST 为 `20`。

#### Scenario: 掩码生成断言全部通过
- **WHEN** 执行 `python3 tools/build_c7_arena_layout.py`
- **THEN** 脚本对 1 个出口格、`carterArrival [10,45]`、20 个 `spawn000..spawn019` 逐项断言 `walkable_rows[y][x] == "1"`，并断言从 `[8,45]` 四邻接洪泛可达全部可走格；任一项不成立即 `AssertionError` 退出，不写出产物。

#### Scenario: 席位规格字段完整
- **WHEN** 任一 `bossSpawns` 条目被 `DataLoader` 载入
- **THEN** 该条含 `kind:"boss"`、`respawnTime:600`、`tombstone:true`、`scaleStats:true`、`xpFromCurve:true`、`dropTableId:"DT_C7_Arena_Boss"`、非空 `group`，且 `monsterId` 在 `monsters` 表中存在且模板 `kind == "boss"`。

### Requirement: Boss 世界尺度间距
20 席在 `Iso.grid_to_world()` 世界坐标下的**两两最小欧氏距离** MUST ≥ **500px**。

#### Scenario: 间距回归
- **WHEN** 对 `bossSpawns` 的 20 个 `cell` 两两计算 `Iso.grid_to_world()` 距离
- **THEN** 最小值为 **544px**（方案 B 冻结坐标实测值），不小于 500px。

### Requirement: 场地 README 与文档同步
`c7_arena` SHALL 拥有同目录 `README.md`，内容覆盖中文名、章节用途、探索路线、关键参数（尺寸/入口/出口/马车/Boss 席位/解锁）、几何口径与本次改造说明；`AGENT.md` §4 的 `MAP PARAMETERS` 标记区由 `tools/check_map_catalog.py --update` 生成。

#### Scenario: 地图目录检查通过
- **WHEN** 执行 `python3 tools/check_map_catalog.py`
- **THEN** 无 README 缺失、无索引不一致、无跨图引用错误告警。

## MODIFIED Requirements

### Requirement: 无尽回廊可走区域占比
改造前：掩码仅由「外椭圆 48/24 − 内椭圆 40/16」的细环 + 5 个半径 8 的区厅圆盘 + 西门走廊构成，可走 2,197 格（15.3%）。
改造后：掩码由「外椭圆 72/38 − 内椭圆 20/11」的宽环 + 西门走廊构成，**可走 7,936 格（55.1%）**；区厅部件整体移除。

### Requirement: 无尽回廊 Boss 分组标注
改造前：5 个 `group`（A–E），每组恰好 2 只。
改造后：5 个 `group`（A–E），**每组恰好 4 只**（按 20 席列表索引每 4 席一组切分）。`group` 仍为纯数据标注，运行时无消费者。

### Requirement: Boss 追踪令牌行数
改造前：`TOTAL_BOSS_ROWS = 27`（17 个单点图 × 1 + c7_arena × 10）。
改造后：`TOTAL_BOSS_ROWS = 37`（17 个单点图 × 1 + **c7_arena × 20**）。

### Requirement: 无尽回廊未领取掉落上限
维持 `unclaimedLootCap: 200` 不变（本次不变更）。附带义务：交付文档须记录「20 只 Boss 满场未领取量 180–240 件 vs 上限 200」的逼近关系与后续观察口径。

## REMOVED Requirements

### Requirement: 五区厅结构（HALL_RING / HALL_ANGLES / HALL_RADIUS）
**Reason**：五个半径 8 的区厅圆盘是「可走区域过少」的直接成因之一。方案 C 实测显示：保留区厅结构后无论怎么摆，20 席最小间距都只能做到约 319px（仅比现状 +12%），无法满足用户「把 Boss 弄分散一点」的诉求。用户已在方案 A / B / B2 / C 中明确选择 **B（去区厅）**。
**Migration**：删除 `hall_centers()`、`HALL_RING / HALL_ANGLES / HALL_RADIUS` 常量与 `is_walkable()` 中的区厅分支；文件头「几何口径」注释同步改写；`docs/工程文档/43` §4.5 几何表同步更新。无数据迁移需求——区厅仅影响掩码形状，不承载任何实体、任务或存档数据。
