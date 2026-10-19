# Checklist — 无尽回廊（c7_arena）扩席与场地改造

> 变更 id：`expand-c7-arena-bosses`
> 每项均须以「检查代码/数据/实测输出」的方式判定，不得凭实现者自述勾选。

## 几何与掩码

- [x] `tools/build_c7_arena_layout.py` 中 `OUTER == (72.0, 38.0)`、`INNER == (20.0, 11.0)`、`CENTER == (80.0, 45.0)`、`WEST_CORRIDOR == (4, 40, 42, 48)`
- [x] `HALL_RING` / `HALL_ANGLES` / `HALL_RADIUS` 常量与 `hall_centers()` 函数已完全移除（全仓 grep 无残留引用）
- [x] `is_walkable()` 只保留「环形走廊 ∨ 西门走廊」两个判定分支，签名不含 `halls` 形参
- [x] 文件头 `##` 说明已改写：无「五区厅」措辞，「20 个 Boss 格」，几何口径与代码一致
- [x] `python3 tools/build_c7_arena_layout.py` 执行成功，输出可走格数为 **7,936**
- [x] 生成器断言覆盖「出口格 / `carterArrival [10,45]` / `spawn000..spawn019`」共 22 个固定格全部可走
- [x] 生成器断言「从 `[8,45]` 四邻接洪泛可达全部可走格」通过（无孤岛）
- [x] 重复执行生成器两次，`data/layouts/c7_arena.json` 字节一致（幂等）
- [x] `data/layouts/c7_arena.json` 未被人工编辑（改动仅来自脚本运行）

## 地图数据

- [x] `map.json` 的 `bossSpawns` 恰为 **20** 条，与 spec「冻结席位表」逐条一致（`monsterId` / `cell` / `group` 全等）
- [x] 20 个 `cell` 两两不重复
- [x] 每条 `bossSpawns` 均含 `kind:"boss"`、`respawnTime:600`、`tombstone:true`、`scaleStats:true`、`xpFromCurve:true`、`dropTableId:"DT_C7_Arena_Boss"`、非空 `group`
- [x] `bossCap == 20`
- [x] `desc` 不再含「五区」「十席」字样
- [x] `layoutVersion` 已更新且与 `data/layouts/c7_arena.json` 中的值一致
- [x] `unclaimedLootCap` 仍为 `200`（未被本次改动）
- [x] `size`、`kind`、`hubId`、`requiresUnlock`、`levelFromPlayer`、`exits`、`entrances`、`carterArrival`、`carterFares`、`normalCap:0`、`eliteCap:0` 与改造前逐字段一致（无 `spawnPoints`、无 `tierRange`）

## 需求达成度

- [x] 可走格占比由 15.3% 提升至 55.1%（2,197 → 7,936 / 14,400）
- [x] 20 席在 `Iso.grid_to_world()` 世界坐标下的最小两两距离 **≥ 500px**（实测应为 544px，较改造前 286px 显著改善）
- [x] 同名 Boss 的两只席位分处场地两端（同名最近一对间距约 2,183px），不在同一小区域内重复扎堆

## 代码与数据契约（未被破坏）

- [x] `autoload/data_loader.gd` 未改动，且加载 `c7_arena` 时对 20 条 `bossSpawns` 的逐条校验全部通过（含 `monsterId` 存在、模板 `kind == "boss"`、`cell` 合法、`dropTableId` 存在）
- [x] `scripts/world/spawner.gd` 未改动
- [x] `data/endgame.json` 未改动（`arenaBosses` 仍为 10 条基底）
- [x] 出口双向同格契约仍成立：`c7_arena.exits[0].cell == [8,45]` 且 `entrances.from_c6_map00 == [8,45]`，并与 `c6_map00` 反向出口格一致

## 测试

- [x] `tests/arena_map_test.gd` 内与本次相关的硬编码数字已同步（`bossCap == 20`、`specs.size() == 20`、`groups` 每区 4 只、`point_count() == 20`）；`Endgame.arena_bosses().size() == 10` 与 `unclaimedLootCap == 200` 保持原值
- [x] `tests/boss_multi_target_test.gd` 的 `arena.size() == 20`
- [x] `tests/boss_token_test.gd` 的 `TOTAL_BOSS_ROWS == 37`，且 `c7_arena` 相关计数均为 20
- [x] `boss_token_test.gd` 的 `arena.size() == keys.size()` 仍为动态断言（未被写成常量）
- [x] `python3 tools/run_isolated_tests.py ArenaMapTest BossMultiTargetTest BossTokenTest` 全绿并输出成功标记
- [x] `python3 tools/run_isolated_tests.py CaveConnectivityTest CaveLayoutTest CaveNavigationTest MapCanvasCacheTest FlatTerrainMeshTest MapTextureBatchTest MapPerformanceTest` 全绿
- [x] `python3 tools/run_isolated_tests.py`（默认 47 项）全绿，或已记录改动前基线并区分既有失败
- [x] 无任何测试被删除、无断言被放宽到掩盖真实回退（仅按数据规模变化的必要同步）

## 文档与目录

- [x] `data/maps/ch07/c7_arena/README.md` 已存在，且覆盖中文名、章节用途、探索路线、关键参数、几何口径、20 席分组与最小间距、本次改造说明
- [x] `python3 tools/check_map_catalog.py` 无 README 缺失 / 索引不一致 / 跨图引用错误告警
- [x] README 的 `MAP PARAMETERS` 标记区由 `check_map_catalog.py --update` 生成，人工说明写在标记之外
- [x] `docs/产品文档/13-…md` 中「10 只 / 每区 2 只 / `bossCap:10` / 10 条」已全部同步为 20 席口径
- [x] `docs/工程文档/43-…md` 中 10 只、10 个固定点、`bossCap: 10`、`spawn000..009`、§4.5 几何表均已同步；分母笔误 `16,400` 已纠正为 `14,400`
- [x] 43 号文档新增「改造记录」小节并交叉引用 55 号文档
- [x] `docs/工程文档/55-无尽回廊（c7_arena）扩席与场地改造记录.md` 已产出：含动因、方案对比（A/B/B2/C 的可走占比与最小间距）、最终几何、20 席坐标表、测试与性能对照、遗留观察项、回滚方式；**无「待批准/待确认/旧设计」残留标注**
- [x] 全仓 grep 无仍描述 c7_arena 为「10 只 Boss / 10 席 / 五区十席 / bossCap 10 / 可走 2,197 格」的有效文档（历史记录类文档除外，仅需交叉引用）

## 性能与验收

- [x] `python3 tools/run_isolated_tests.py --rendered MapRenderBenchmark` 已执行，记录绘制调用数与耗时中位数/P95
- [x] 改造前（git 快照）与改造后的 `MapRenderBenchmark` 对照数据已写入 55 号文档性能小节
- [x] 对照数据覆盖地图加载与每 200ms 的地图画布刷新（改造前后各 140 帧 × `normal / ground hidden / maps hidden` 三种采样）
- [x] 「首次全屏打开大地图」与「满活动 Boss 数密集战斗」未被该基准单独采样，已作为遗留观察项记入 55 号文档（受 `ACTIVE_DISTANCE=760px` 约束，同屏实体数远小于 20）
- [x] 确认未引入逐格 `draw_colored_polygon()` 或逐瓦片切纹理的新路径（`AGENT.md` §2 不可退项）；小地图底图仍为「静态底图 + 动态标记分层」

## 提交纪律

- [x] Task 1+2、Task 3、Task 4、Task 5、Task 6（如拆分则两笔）、Task 7 各自独立 commit，未夹带无关并行改动
- [x] commit 标题为中文 Conventional Commits；Task 4 的提交说明显式标注「放宽既有断言（每区 2 只 → 4 只）」
- [x] 临时探针/调试脚本未入库（若有则已删除）
