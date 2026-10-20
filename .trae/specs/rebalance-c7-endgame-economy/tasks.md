# Tasks — 循环图经济与数值复核（无尽回廊 · 聚金地脉 · 百首禁域）

> 变更 id：`rebalance-c7-endgame-economy`
> 前置：`spec.md` 已批准；权威方案 = [工程文档 67](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/工程文档/67-循环图经济与数值复核方案（无尽回廊·聚金地脉·百首禁域）.md)（§4 已拍板数值、§5 落点清单、§6 验收步骤）。
> 提交纪律：代码按 **T1/T2**、**T3/T4** 两批分别 commit；文档与测试各自独立 commit；不夹带无关改动。

---

- [x] Task 1：伤害下限参数与怪物侧接入（`combat.gd` + `monster.gd`）
  - [x] SubTask 1.1：`scripts/systems/combat.gd` 的 `resolve()` 增加**末位可选参数** `min_damage: int = 1`（放在 `use_rng` 之后，保持既有位置参数调用全部兼容），末行返回改为 `maxi(min_damage, int(damage))`；同步更新函数上方注释说明「缺省 1 = 原行为」。
  - [x] SubTask 1.2：`scripts/entities/monster.gd` 新增私有方法 `_min_hit_on_player() -> int`，实现 `clampi(int(round(float(GameState.max_hp()) * 0.0025)), 10, 60)`（`GameState.max_hp()` 已存在，勿新增接口）。
  - [x] SubTask 1.3：`monster.gd::_skill_hit()`（Boss 技能 / 远程命中，约 L478–482）与 `monster.gd::_do_attack()`（普攻，约 L780–784）两处 `Combat.resolve(...)` 调用**追加末位实参** `_min_hit_on_player()`。
  - [x] SubTask 1.4：**不得改动** `scripts/entities/player.gd` 的两处玩家 → 怪物调用点（保持缺省 1），也不得改 `miss` 分支、休息区 / 无敌帧逻辑。
  - [x] SubTask 1.5：新增有牙断言（写入 `tests/endgame_cycle_map_test.gd`）：
    - 纯公式：`Combat.resolve(1.0, 100000.0, 1.0, 0.0, 1.0, 0.0)` 的 `damage == 1`；同参数传末位 `min_damage = 37` 时 `damage == 37`。
    - 怪物侧：以「`attack_power` 极小、玩家防御极高」构造一次 `_do_attack` 等价的结算，断言怪物 → 玩家伤害 ≥ 10 且 ≤ 60。
  - [x] SubTask 1.6：**负向注入自检**：临时把 `_min_hit_on_player()` 的返回值改回 `1`，确认 SubTask 1.5 的怪物侧用例**失败**（证明用例有牙），随后复原。
  - [x] SubTask 1.7：`python3 tools/run_isolated_tests.py EndgameCycleMapTest ChapterTwoCombatTest ChapterSixCombatTest SkillCombatTest` 全绿。

- [x] Task 2：spawn 规格级倍率接入（`spawner.gd` + `monster.gd`）
  - [x] SubTask 2.1：`scripts/world/spawner.gd::spawn_from_specs()` 的 `point` 字典（约 L101–118）新增 `"hp_multiplier": float(spec.get("hpMultiplier", 1.0))` 与 `"atk_multiplier": float(spec.get("atkMultiplier", 1.0))`。
  - [x] SubTask 2.2：`spawner.gd::_spawn()` 注入 Monster 处（约 L214–224）新增 `m.hp_multiplier = float(point.get("hp_multiplier", 1.0))` 与 `m.atk_multiplier = float(point.get("atk_multiplier", 1.0))`。
  - [x] SubTask 2.3：`monster.gd` 新增 `@export var hp_multiplier := 1.0` 与 `@export var atk_multiplier := 1.0`（与既有 `xp_multiplier` 等字段并列）。
  - [x] SubTask 2.4：在 `monster.gd::_load_template()` 的 norm / scale 分支**之后**（约 L205–209 之后、`_roll_affixes()` 之前）应用倍率：`max_hp = maxi(1, int(round(float(max_hp) * hp_multiplier)))`，随后**重赋** `hp = max_hp`；`attack_power *= atk_multiplier`。注意顺序——必须在 norm / scale 结算完成之后，否则倍率会被缩放覆盖。
  - [x] SubTask 2.5：有牙断言：构造两条测试规格（一条无倍率、一条 `hpMultiplier 3.0` / `atkMultiplier 2.0`），断言无倍率者的 `max_hp` / `attack_power` 与 `monster.gd` 单独装配时**逐值相等**（存量图零影响），有倍率者精确等于 `基础值 × 倍率`。
  - [x] SubTask 2.6：`python3 tools/run_isolated_tests.py` 中与怪物数值相关的定向集（`BalanceTest`、`EndgameCycleMapTest`、`ArenaMapTest`、`ChapterSixCombatTest`）全绿。

- [x] Task 3：聚金地脉布点与经验（`tools/build_c7_cycle_maps.py`）
  - [x] SubTask 3.1：`build_gold()` 改为**6 堆 × 16 席**的确定性布点：每堆为 4×4 网格、格间距 3 格；8 个怪种每种在每堆占 2 席（`count` 仍为 12 → 6 堆 × 2）；`spawnPoints` 的分组结构、`respawnTime 15`、`scaleStats`、`xpFromCurve`、`xpCurveDivisor 10`、`dropTableId` 保持不变。
  - [x] SubTask 3.2：堆心选取满足「两两**世界像素距离 ≥ 858px**（`Iso` 的 2:1 投影换算）且**网格欧氏距离 ≥ 24 格**」，并避开入口 `(6,45)` 与出口缓冲；3 堆在左半、3 堆在右半。在生成器内**加断言**固化这两条约束（不满足即抛错，不允许静默通过）。
  - [x] SubTask 3.3：`normalCap 28 → 32`、`xpMultiplier 0.5 → 0.1`；`desc` 同步改写为「按堆密集刷新」的口径。
  - [x] SubTask 3.4：`build_boss()`（百首禁域）每条席位新增 `"hpMultiplier": 2.0`、`"atkMultiplier": 1.5`，并把 `"xpMultiplier": 0.5` 改为 `0.25`；其余字段（100 席 / 每 10 席一行的排布 / `bossCap 18` / `unclaimedLootCap 2400` / `preserveUnclaimedLoot`）**不得改动**。
  - [x] SubTask 3.5：执行 `python3 tools/build_c7_cycle_maps.py`，确认 `validate_and_layout` 的「固定格可走 + 四邻接全连通」断言通过、固定格总数不变（金币 96 + 出口/车夫；Boss 100 + 出口/车夫）；产出 `data/maps/ch07/c7_gold_field/map.json`、`c7_boss_field/map.json` 与对应 `data/layouts/*.json`。
  - [x] SubTask 3.6：幂等自检——再跑一次生成器，两张 `map.json` 与两个 layout 产物字节不变。

- [x] Task 4：无尽回廊倍率与金币数值（数据落盘）
  - [x] SubTask 4.1：`data/maps/ch07/c7_arena/map.json` 的 20 条 `bossSpawns` **逐条新增** `"hpMultiplier": 2.0` 与 `"xpMultiplier": 0.5`（该文件的 `bossSpawns` 不由生成器写入，属人工维护；只加字段，`cell` / `monsterId` / `group` / `respawnTime` / `dropTableId` 等一律不动）。
    - `c7_arena` 的 `layoutPath` 掩码只消费 `cell`，加字段不改变几何 ⇒ **不要**改 `layoutVersion`、**不要**重跑 `build_c7_arena_layout.py`。
  - [x] SubTask 4.2：`data/dropTables.json` 的 `DT_C7_Gold_Normal` 首条 `coin` 的 `goldRange` 由 `[176, 224]` 改为 `[440, 560]`；`desc` 文案由「金币为第六章普通怪四倍」改为与新数值一致的口径。
  - [x] SubTask 4.3：有牙断言（合并进 `tests/endgame_cycle_map_test.gd`）：
    - `c7_gold_field`：`normalCap == 32`、`count == 96`、每个 `spawnPoints[].xpMultiplier == 0.1`、堆数 == 6、堆心两两世界距离 ≥ 858px。
    - `DT_C7_Gold_Normal.goldRange == [440, 560]`。
    - `c7_boss_field.bossSpawns[]` 每条 `hpMultiplier == 2.0`、`atkMultiplier == 1.5`、`xpMultiplier == 0.25`。
    - `c7_arena.bossSpawns[]` 每条 `hpMultiplier == 2.0`、`xpMultiplier == 0.5`。
  - [x] SubTask 4.4：commit（`feat(c7): 循环图数值复核——Boss 血量翻倍、经验减半、打金图分堆加密`，含 Task 1–4 的代码与数据改动；如分两批，先 T1/T2 代码，再 T3/T4 数据）。

- [x] Task 5：既有测试断言同步（`tests/endgame_cycle_map_test.gd` + 受影响断言）
  - [x] SubTask 5.1：`tests/endgame_cycle_map_test.gd::_test_maps()` —— `count == 96 and normalCap == 28` 改 `normalCap == 32`；`金币范围 176–224` 改 `440–560`；`gold_range[0] == 440 / [1] == 560`。
  - [x] SubTask 5.2：`_test_spawn_instances()` —— 金币图 `alive_count() == 28` 改 `32`；`expected` 的经验系数 `* 0.5` 改 `* 0.1`；百首禁域 `boss.xp_multiplier == 0.5` 改 `0.25`，并补 `hp_multiplier == 2.0` / `atk_multiplier == 1.5` 断言。
  - [x] SubTask 5.3：全仓 grep 其余写死「28 / 176 / 224 / xpMultiplier 0.5」的用例（如 `tests/spawner_budget_test.gd`、`tests/economy_test.gd`），逐条判定是新口径还是无关，**只改本批口径相关的**，并在提交说明里列明同步的范围。
  - [x] SubTask 5.4：`python3 tools/run_isolated_tests.py EndgameCycleMapTest ArenaMapTest SpawnerBudgetTest EconomyTest` 全绿。
  - [x] SubTask 5.5：commit（`test(c7): 同步循环图数值断言（上限 32 / 金币 440–560 / 倍率口径）`）。

- [x] Task 6：地图 README 与目录校验
  - [x] SubTask 6.1：更新 `data/maps/ch07/c7_gold_field/README.md` 的人工说明句：96 席由 12×8 点阵改为 **6 堆 × 16 席**、同屏上限 32、金币 440–560（×2.5）、经验系数 0.1（约 `boss_xp(L)/100`）。
  - [x] SubTask 6.2：更新 `data/maps/ch07/c7_boss_field/README.md` 与 `c7_arena/README.md` 的人工说明句：Boss 血量 ×2、经验倍率（`0.25` / `0.5`）、百首禁域攻击 ×1.5。
  - [x] SubTask 6.3：`python3 tools/check_map_catalog.py --update` 刷新 `MAP PARAMETERS` 标记区（标记区**只由工具写**，人工文字写在标记外）。
  - [x] SubTask 6.4：自检——`python3 tools/check_map_catalog.py` 无告警；`python3 tools/run_isolated_tests.py MapCatalogTest` 全绿。
  - [x] SubTask 6.5：commit（`docs(map): 同步 ch07 三图循环数值口径到 README`）。

- [x] Task 7：设计/工程文档口径回写
  - [x] SubTask 7.1：`docs/产品文档/13-满级后循环玩法（循环装备·循环Boss·随身三件套）.md` —— 更新 Boss 血量 / 经验倍率、聚金地脉 6 堆 × 16 席与上限 32、金币 440–560、普通怪经验系数四项口径。
  - [x] SubTask 7.2：`docs/产品文档/06-经济与NPC系统.md` —— 金币产出口径（循环图单只金币与药水回收关系）。
  - [x] SubTask 7.3：`docs/产品文档/03-核心循环与战斗系统.md` —— §3.2 伤害公式补「怪物 → 玩家存在按最大生命比例的伤害下限 `clampi(maxHP×0.25%, 10, 60)`，玩家 → 怪物仍为 1」。
  - [x] SubTask 7.4：`docs/工程文档/59-无尽回廊双循环地图产品与开发规划.md` —— 同步三图倍率字段（`hpMultiplier` / `atkMultiplier`）的落点与本次改造记录。
  - [x] SubTask 7.5：commit（`docs(c7): 回写循环图数值复核口径到产品与工程文档`）。

- [x] Task 8：回归与验收
  - [x] SubTask 8.1：`python3 tools/run_isolated_tests.py`（默认集 47 项）全绿；如有与本批无关的既有失败，记录改动前基线并区分责任范围，**不得删除测试或放宽断言**。
  - [x] SubTask 8.2：对 Task 1 与 Task 4 的有牙断言各做一次**负向注入**（临时改坏实现 → 断言必须失败 → 复原），并记录注入前后的输出。
  - [x] SubTask 8.3：实机手感验收交由用户执行（三张图各刷 5 分钟，记录金币/分钟、是否还需跑图、药水消耗、Boss 单只耗时、升级速度）；`xpMultiplier` 允许在 `[0.05, 0.2]` 内微调，微调后须重跑 Task 5 断言。

---

# Task Dependencies

- Task 2 依赖 Task 1？**否**——两者改同一文件 `monster.gd`，必须**同一个执行者按 T1 → T2 顺序串行**，避免交错冲突。
- Task 3 → Task 4：`c7_gold_field` / `c7_boss_field` 的 `map.json` 由生成器产出，必须先改生成器再落盘；`c7_arena` 的倍率是人工字段，可在 Task 4 一并写入。
- Task 5 依赖 Task 3、Task 4（断言读的是落盘后的数据）。
- Task 6 依赖 Task 3、Task 4（README 参数与说明句以新口径为准）。
- Task 7 依赖 Task 4（文档口径以定案数值为准）。
- Task 8 依赖 Task 1–7。
- Task 6 与 Task 7 可并行。

# 明确不做（防止范围蔓延）

- 不改 `data/endgame.json`（两图共用同 10 个 Boss 的 norm，改 norm 无法区分攻击倍率）。
- 不改 `c7_gold_field` / `c7_boss_field` 的掩码几何、`c7_arena` 的 `unclaimedLootCap`、`bossCap`、`respawnTime`。
- 不改 `player.gd` 的玩家 → 怪物伤害路径、`LevelGap` 两条倍率、药水数值与冷却。
- 不新增美术素材、不改掉落表的装备条目与品质权重（除 `DT_C7_Gold_Normal` 的金币区间）。
- 不删除任何既有测试用例。
