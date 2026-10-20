# Checklist — 循环图经济与数值复核（无尽回廊 · 聚金地脉 · 百首禁域）

> 变更 id：`rebalance-c7-endgame-economy`
> 每项均须以「检查代码/数据/实测输出」的方式判定，不得凭实现者自述勾选。

## 伤害下限（仅怪物 → 玩家）

- [x] `Combat.resolve()` 增加了末位可选参数 `min_damage`（缺省 `1`，既有位置参数调用点全部兼容）；下限**仅在不破防**（`floorf(攻×系数 − 防×0.5) ≤ 0`）时替换 1 点兜底，已破防的小额伤害不被抬升（口径修正见工程文档 67 §9）
- [x] `monster.gd` 存在 `_min_hit_on_player()`，公式为 `clampi(int(round(GameState.max_hp() * 0.0025)), 10, 60)`
- [x] `monster.gd::_skill_hit()` 与 `monster.gd::_do_attack()` 两处 `Combat.resolve(...)` 均传入 `_min_hit_on_player()`
- [x] `player.gd` 的两处玩家 → 怪物调用点未改动（仍为缺省 1）
- [x] `miss` 分支、休息区 / 无敌帧拦截逻辑未被改动
- [x] 用例：`Combat.resolve` 在「攻 1 / 防 100000」下缺省返回 1；传入 `min_damage = 37` 时返回 37
- [x] 用例：怪物 × 高防玩家的一次结算，伤害落在 `[10, 60]`
- [x] 负向注入验证：把 `_min_hit_on_player()` 临时改回 `1` 时，上述怪物侧用例**失败**（已记录输出并复原）

## Spawn 规格级倍率

- [x] `spawner.gd` 的 `point` 字典含 `hp_multiplier` / `atk_multiplier`（读 `hpMultiplier` / `atkMultiplier`，缺省 `1.0`）
- [x] `spawner.gd::_spawn()` 向 Monster 注入 `hp_multiplier` / `atk_multiplier`
- [x] `monster.gd` 有 `@export var hp_multiplier := 1.0` 与 `@export var atk_multiplier := 1.0`
- [x] 倍率在 `_load_template()` 的 norm / scale 分支**之后**应用，且 `hp` 在改动 `max_hp` 后同步重赋
- [x] 用例：不带倍率的规格与 `monster.gd` 单独装配同怪时，`max_hp` / `attack_power` 逐值相等（存量图零影响）
- [x] 用例：带 `hpMultiplier 3.0` / `atkMultiplier 2.0` 的规格，结果为精确倍数
- [x] `data/endgame.json` 未被改动

## 聚金地脉（密度 · 金币 · 经验）

- [x] `tools/build_c7_cycle_maps.py::build_gold()` 产出 **6 堆 × 16 席**（每堆 4×4、格间距 3），总席位数仍为 96，每怪种 `count == 12`
- [x] 生成器内含「堆心两两世界像素距离 ≥ 858px」与「网格欧氏距离 ≥ 24 格」的断言，且堆位避开入口 `(6,45)` 与出口缓冲
- [x] `c7_gold_field.normalCap == 32`、`respawnTime == 15`（未变）、`xpMultiplier == 0.1`
- [x] `DT_C7_Gold_Normal` 首条 `coin.goldRange == [440, 560]`，`desc` 已同步为「按实际击杀等级生成 + 新金币口径」
- [x] 生成器执行后 `validate_and_layout` 断言全过，固定格数与连通性无回退；两只 `layout` 产物由脚本产出、未被人工编辑
- [x] 生成器重复执行两次，两张 `map.json` 与两个 layout 产物字节一致（幂等）

## Boss 侧倍率与经验

- [x] `c7_arena.bossSpawns` 20 条**逐条**含 `hpMultiplier 2.0`、`xpMultiplier 0.5`；`cell` / `monsterId` / `group` / `respawnTime 600` / `dropTableId` 与改动前全等
- [x] `c7_arena` 的 `layoutVersion`、`unclaimedLootCap 200`、`bossCap 20` 未被改动，掩码产物未被重跑改写
- [x] `c7_boss_field.bossSpawns` 100 条**逐条**含 `hpMultiplier 2.0`、`atkMultiplier 1.5`、`xpMultiplier 0.25`
- [x] `c7_boss_field` 的 100 席坐标排布、`bossCap 18`、`unclaimedLootCap 2400`、`preserveUnclaimedLoot` 未被改动
- [x] 用例：三张图的倍率字段逐条断言通过（含 `c7_arena` 与 `c7_boss_field` 各自的差异口径）

## 测试与回归

- [x] `tests/endgame_cycle_map_test.gd` 的 `96 席 / 上限 28`、`金币 176–224`、`xpMultiplier 0.5` 等断言已全部同步到新口径
- [x] 其余写死 `28 / 176 / 224` 的用例已逐条判定并同步（无关者未动，同步范围已写入提交说明）
- [x] 无任何测试被删除，无断言被放宽到掩盖真实回退
- [x] `python3 tools/run_isolated_tests.py EndgameCycleMapTest ArenaMapTest SpawnerBudgetTest EconomyTest` 全绿
- [x] `python3 tools/run_isolated_tests.py`（默认集）全绿，或已记录改动前基线并区分既有失败
- [x] 每组改动的有牙断言均完成一次负向注入（改坏实现 → 用例失败 → 复原），并有输出留痕

## 文档与目录

- [x] `data/maps/ch07/c7_gold_field/README.md`、`c7_boss_field/README.md`、`c7_arena/README.md` 的人工说明句已按新口径改写（分堆 6×16、上限 32、金币 440–560、经验倍率、Boss 血量 ×2）
- [x] 三张 README 的 `MAP PARAMETERS` 标记区由 `python3 tools/check_map_catalog.py --update` 生成，人工文字写在标记之外
- [x] `python3 tools/check_map_catalog.py` 无告警
- [x] 产品文档 13 / 06 / 03 与工程文档 59 的口径已回写，且与 `spec.md` 的定案数值一致
- [x] 全仓无仍描述「金币 176–224 / 金币图上限 28 / 循环 Boss 经验倍率 0.5（c7_boss_field）」的有效文档（历史交付记录除外，仅需交叉引用）

## 提交纪律

- [x] 代码（T1/T2）与数据（T3/T4）各自独立 commit，未夹带工作区无关改动
- [x] 测试同步、README、设计文档回写各自独立 commit
- [x] commit 标题为中文 Conventional Commits
- [x] 临时探针 / 调试脚本未入库（若有则已删除）
