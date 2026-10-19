# Tasks — 无尽回廊（c7_arena）扩席与场地改造

> 变更 id：`expand-c7-arena-bosses`
> 前置：`spec.md` 已批准。用户已拍板：几何取**方案 B（去区厅）**、Boss 形象取**现有 10 只各用 2 次**、`unclaimedLootCap` **保持 200**。
> 提交纪律（`AGENT.md` §10 + 用户惯例）：每个 Task 完成并自检通过后**单独一次 commit**，不夹带其他并行改动。提交信息用中文 Conventional Commits。

---

- [x] Task 1：改造掩码生成器几何（`tools/build_c7_arena_layout.py`）
  - [x] SubTask 1.1：`OUTER` 改为 `(72.0, 38.0)`、`INNER` 改为 `(20.0, 11.0)`；`CENTER`/`WEST_CORRIDOR` 不动。
  - [x] SubTask 1.2：删除常量 `HALL_RING`、`HALL_ANGLES`、`HALL_RADIUS`，删除函数 `hall_centers()`。
  - [x] SubTask 1.3：`is_walkable()` 去掉 `halls` 形参与区厅循环分支，签名改为 `is_walkable(x, y)`，保留「外椭圆内 ∧ 内椭圆外 ⇒ 环」与「西门走廊矩形」两个返回点；同步改写函数内中文文档注释。
  - [x] SubTask 1.4：`main()` 里 `halls = hall_centers()` 与 `is_walkable(x, y, halls)` 调用同步去参。
  - [x] SubTask 1.5：重写文件头 `##` 说明（第 2–14 行）：删掉「五区厅」措辞、「10 个 Boss 格」改「20 个 Boss 格」，几何口径改为「外椭圆(a=72,b=38) 减 内椭圆(a=20,b=11)，中心 (80,45)；西门走廊 4≤x≤40 ∧ 42≤y≤48；已移除区厅部件」。
  - [x] SubTask 1.6：自检——脚本能 `python3 tools/build_c7_arena_layout.py` 跑通（此时若 `map.json` 仍是 10 席，断言应仍全过；若失败说明几何或数据未对齐，先修再进 Task 3）。

- [x] Task 2：更新地图配置 `data/maps/ch07/c7_arena/map.json`
  - [x] SubTask 2.1：用 `spec.md` 的**冻结席位表**整体替换 `bossSpawns` 数组（20 条），每条固定字段 `"kind":"boss", "respawnTime":600, "tombstone":true, "scaleStats":true, "xpFromCurve":true, "dropTableId":"DT_C7_Arena_Boss"`，另带各自 `monsterId` / `cell` / `group`。
  - [x] SubTask 2.2：`bossCap` 由 `10` 改为 `20`。
  - [x] SubTask 2.3：`desc` 由 `"环形回廊串起五区十席，首领等级随挑战者成长。"` 改写为不含「五区/十席」的新文案，例如 `"环形回廊串起二十席，首领等级随挑战者成长。"`。
  - [x] SubTask 2.4：`layoutVersion` 由 `"2026-10-18-endgame-v1"` 改为 `"2026-10-19-arena-20seats-v1"`（掩码形状已变，版本号需可追溯；生成器会自动把该值复制进 `data/layouts/c7_arena.json`）。
  - [x] SubTask 2.5：**不得改动** `size(160×90)`、`kind/hubId/requiresUnlock`、`levelFromPlayer`、`unclaimedLootCap:200`、`exits`、`entrances`、`carterArrival`、`carterFares`、`normalCap:0`、`eliteCap:0`、无 `spawnPoints`、无 `tierRange`。
  - [x] SubTask 2.6：自检——`python3 -c "import json;json.load(open('data/maps/ch07/c7_arena/map.json'))"` 解析无误；`bossSpawns` 恰 20 条且 `cell` 无重复。
  - [x] SubTask 2.7：commit（`feat(arena): 无尽回廊扩至 20 席并重划场地几何`，仅含 Task 1 + Task 2 的 `tools/` 与 `data/maps/` 改动）。

- [x] Task 3：重跑生成器产出掩码产物
  - [x] SubTask 3.1：执行 `python3 tools/build_c7_arena_layout.py`。
  - [x] SubTask 3.2：确认脚本输出中可走格为 **7,936**、且断言「20 个固定格可走 + 从 `[8,45]` 全连通」全部通过；若某席位断言失败，说明该坐标需回退到 spec §冻结席位表的重算流程（**不得手改 `data/layouts/c7_arena.json`**）。
  - [x] SubTask 3.3：确认 `data/layouts/c7_arena.json` 的 `points` 含 `c7_arena_exit01`、`carterArrival`、`spawn000`–`spawn019`（共 22 项），`layoutVersion` 已同步为 `2026-10-19-arena-20seats-v1`。
  - [x] SubTask 3.4：幂等自检——再跑一次脚本，`data/layouts/c7_arena.json` 字节不变。
  - [x] SubTask 3.5：commit（`chore(arena): 重建 c7_arena 通行掩码（可走 2197 → 7936 格）`）。

- [x] Task 4：同步测试断言（依赖 Task 3）
  - [x] SubTask 4.1：`tests/arena_map_test.gd` — L68 `bossCap == 10` → `20`；L142 `specs.size() == 10` → `20`；L163 `groups.size() == 5` 保留但注释由「五区各两只」改「五区各四只」；L165 `groups[group] == 2` → `4`；L202 `sp.point_count() == 10` → `20`；L203-204 注释「10 个点 / 10 只」→「20 个点 / 20 只」。L120 注释「10 个 Boss 格」→「20 个 Boss 格」。L67 `unclaimedLootCap == 200` **保持不变**。
    - 注意：L171 `Endgame.arena_bosses().size() == 10` **保持不变**（本次不扩 `endgame.json`，仍为 10 条基底）。
  - [x] SubTask 4.2：`tests/boss_multi_target_test.gd` — L165 `arena.size() == 10` → `20`，文案「10 个 Boss 点」→「20 个 Boss 点」。L64-91 的同名双实例用例保持不动（仍须通过）。
  - [x] SubTask 4.3：`tests/boss_token_test.gd` — L15 `TOTAL_BOSS_ROWS := 27` → `37`；L53-54 文案「（17 单点 + c7_arena 10）」→「（17 单点 + c7_arena 20）」；L56 `arena.size() == 10` → `20`，文案同步；L146 `rows.size() == 10` → `20`，文案「应有 10 行」→「应有 20 行」；L185 `actual.size() == 10` → `20`，文案「10 个 Boss 点」→「20 个 Boss 点」。
    - L131-135（`arena.size() == keys.size()`）为动态断言，**不得改成常量**。
  - [x] SubTask 4.4：自检——`python3 tools/run_isolated_tests.py ArenaMapTest BossMultiTargetTest BossTokenTest` 全绿（各自输出 `[XxxTest] 全部通过 ✅`）。
  - [x] SubTask 4.5：commit（`test(arena): 同步 c7_arena 20 席断言（放宽分组计数至每区 4 只）`，说明中显式标注「放宽既有断言」）。

- [x] Task 5：补齐地图 README（`AGENT.md` §4 强制）
  - [x] SubTask 5.1：先运行 `python3 tools/check_map_catalog.py`，记录其报出的 README 缺失/索引问题。
  - [x] SubTask 5.2：新建 `data/maps/ch07/c7_arena/README.md` —— 中文名（无尽回廊）、章节用途（满级后循环挑战场，`requiresUnlock: campaign_complete`）、探索路线（`c6_map00 ↔ c7_arena` 唯一出入口，马车报价 1200）、关键参数（160×90、`normalCap:0`/`eliteCap:0`/`bossCap:20`、`levelFromPlayer.minLevel:60`、`unclaimedLootCap:200`、`respawnTime:600` + 墓碑）、**几何口径**（外椭圆 72/38 − 内椭圆 20/11 + 西门走廊，`tools/build_c7_arena_layout.py` 为唯一生成入口）、**20 席分组与最小世界间距 544px**、本次改造说明。
  - [x] SubTask 5.3：若 `check_map_catalog.py` 报章节 README 缺失，则补 `data/maps/ch07/README.md`（章节级：用途、地图清单、与 `data/maps/index.json` 的登记关系）。
  - [x] SubTask 5.4：运行 `python3 tools/check_map_catalog.py --update` 刷新两个 README 的 `MAP PARAMETERS` 标记区（标记区**只由工具写**，人工文字写在标记外）。
  - [x] SubTask 5.5：自检——`python3 tools/check_map_catalog.py` 无告警。
  - [x] SubTask 5.6：commit（`docs(map): 补齐 ch07 与 c7_arena README 并同步 20 席参数`）。

- [x] Task 6：同步设计/工程文档 + 新建独立交付文档（依赖 Task 2、Task 3）
  - [x] SubTask 6.1：`docs/产品文档/13-满级后循环玩法（循环装备·循环Boss·随身三件套）.md` — L40「10 只」改 20；§4.1 表（约 L376-383）中「Boss 点 = 10 个，分 5 区（每区 2 只）环形走廊串联」改「Boss 点 = 20 个，分 5 组（每组 4 只）环形走廊串联」；「生成预算 `bossCap: 10`」改 `20`；L546「`c7_arena` 一行展开 10 条」改 20 条；L1052 M10-3 行「`bossCap:10`」「进图 10 只」改 20。
  - [x] SubTask 6.2：`docs/工程文档/43-M10-3循环Boss图实施方案.md` — L4「10 只 Boss」改 20 只；L19「160×90 环形回廊 + 10 个固定 Boss 点」改 20 个；L73-76「进图 10 只 vs `ACTIVE_DISTANCE=760`」改为 20 席口径并说明「20 席仅登记点，实体仍受 760px 限制，同屏远小于 20」；L150 `bossCap: 10` 改 `20`；§4.3 十条席位清单改 20 条（指向 spec 冻结席位表）；L195「可走 2,197 / 16,400」——**注意原分母 16,400 与实测 `160×90 = 14,400` 不符，本次一并纠正为 7,936 / 14,400（55.1%）**；L199「points 写 `spawn000..009`」改 `..019`；§4.5 几何表改为方案 B 常量并注明「区厅部件已移除」。
  - [x] SubTask 6.3：在 43 号文档新增「## 改造记录」小节（不重写历史正文），交叉引用 55 号文档，一句话说明「2026-10-19 按方案 B 扩至 20 席，几何与席位以 55 号文档为准」。
  - [x] SubTask 6.4：新建 `docs/工程文档/55-无尽回廊（c7_arena）扩席与场地改造记录.md` —— 独立可交付：改造动因、方案对比表（现状 / A / B / B2 / C 的可走占比与 20 席最小间距）、最终几何口径、20 席冻结坐标表、测试与性能对照记录、遗留观察项（`unclaimedLootCap:200` 逼近关系）、回滚方式。内容源自 `spec.md`，去掉「待批准」措辞，作为最终版。
  - [x] SubTask 6.5：commit（`docs(arena): 同步循环玩法与 M10-3 文档并新增 55 号改造记录`）——按用户惯例，**新建的 55 号文档连同 13/43 的同步改动各自独立提交**；若需拆两次提交，先提交 55 号新文档，再提交 13/43 同步。

- [x] Task 7：定向回归与性能对照（依赖 Task 3、Task 4）
  - [x] SubTask 7.1：跑地图/寻路/缓存定向集 —— `python3 tools/run_isolated_tests.py ArenaMapTest BossMultiTargetTest BossTokenTest CaveConnectivityTest CaveLayoutTest CaveNavigationTest MapCanvasCacheTest FlatTerrainMeshTest MapTextureBatchTest MapPerformanceTest`，逐项确认成功标记。
  - [x] SubTask 7.2：跑窗口绘制对照 —— `python3 tools/run_isolated_tests.py --rendered MapRenderBenchmark`，记录改造后的绘制调用数与耗时中位数/P95。
  - [x] SubTask 7.3：从 git 取改造前快照跑同一 `MapRenderBenchmark`，把**前后对照数据**写进 55 号文档的性能小节（`AGENT.md` §2 要求「替代/变更现有架构必须提供同场景行为验证和性能对照」；本例只改数据量、不改架构，但可走格 3.6× 属「扩大地图」场景，必须留档）。
  - [x] SubTask 7.4：跑默认隔离集 —— `python3 tools/run_isolated_tests.py`（47 项）确认为绿；如出现与本次改动无关的既有失败，记录改动前基线并区分责任范围，**不得删除测试或用放宽断言掩盖**。
  - [x] SubTask 7.5：视情况跑 `python3 tools/run_isolated_tests.py --all`（98 项）确认跨域无回归。
  - [x] SubTask 7.6：commit（若有对照数据补充进 55 号文档则单独提交 `docs(arena): 补充 c7_arena 改造前后性能对照`）。

- [x] Task 8（实施中追加）：补记渲染基准未覆盖的场景
  - [x] SubTask 8.1：把「`MapRenderBenchmark` 未单独采样『首次全屏打开大地图』与『满活动 Boss 数密集战斗』」写入 55 号文档「遗留观察项」（`AGENT.md` §7 要求压力场景留档，不能默认基准已覆盖）。
  - [x] SubTask 8.2：commit `docs(arena): 补记渲染基准未覆盖的场景`（提交 hash `a1a258ac`）。

---

# Task Dependencies

- Task 3 依赖 Task 1（几何）+ Task 2（20 席数据落盘）：生成器把 `map.json` 的 `bossSpawns[].cell` 当作固定格读取，数据未更新则断言无意义。
- Task 4 依赖 Task 3：测试读的是运行期数据与掩码产物。
- Task 5 依赖 Task 2（README 参数要写 20 席口径）。
- Task 6 依赖 Task 2、Task 3（文档要引用实测的 7,936 格与席位表）。
- Task 7 依赖 Task 3、Task 4。
- Task 1 与 Task 2 可并行；Task 5、Task 6 可并行。

# 明确不做（防止范围蔓延）

- 不新增 `endgame.json` 的 `arenaBosses` 条目（形象仍 10 只，各用 2 次）。
- 不改 `unclaimedLootCap: 200`。
- 不改 `spawner.gd`、`data_loader.gd`、`map_service.gd`、`dropTables.json` 的 `DT_C7_Arena_Boss`。
- 不手改 `data/layouts/c7_arena.json`（一律由生成器产出）。
- 不改动 `data/maps/ch07/c7_arena/map.json` 中除 `bossSpawns` / `bossCap` / `desc` / `layoutVersion` 以外的任何字段。
- 不新增地图美术素材、不改小地图/大地图渲染架构。
