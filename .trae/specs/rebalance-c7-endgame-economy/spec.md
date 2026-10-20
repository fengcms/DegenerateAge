# 循环图经济与数值复核 Spec（无尽回廊 · 聚金地脉 · 百首禁域）

> 变更 id：`rebalance-c7-endgame-economy`
> 唯一权威方案文档：[67-循环图经济与数值复核方案](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/工程文档/67-循环图经济与数值复核方案（无尽回廊·聚金地脉·百首禁域）.md)（已拍板）
> 涉及地图：`data/maps/ch07/c7_arena/`、`c7_gold_field/`、`c7_boss_field/`
> 术语：用户所述「白首禁域」= **百首禁域** `c7_boss_field`

## Why

满级后循环图实测出现四个问题，互相耦合：

1. 无尽回廊与百首禁域的 Boss **血量偏低、经验偏高**，Boss 战没有时长感，且升级速度过快。
2. 聚金地脉「掉金少」的真实根因不是数值，而是 **96 席铺成 12×8 稀疏点阵覆盖全图**（邻距约 429px），叠加 `ACTIVE_DISTANCE 760px` 的生成规则 ⇒ 玩家视野内只有零星几只，**跑图时间成为瓶颈**；更糟的是「Boss 图打 Boss 卖装备」的路子收益观感明显更好。
3. 加密聚金地脉会**同时放大击杀率**，若不同步下调经验，升级速度会比现状更快（与诉求反向）。
4. 三张图里怪物打**不破防**的玩家时被 `maxi(1, …)` 兜成 **1 点伤害**，自动喝药永不触发，**药水经济空转**。根因是防御侧为「14 槽聚合值」而攻击侧是单个数，两侧同乘 `Balance.scale(L−60)`，比值恒定。

## What Changes

- **新增 spawn 规格级倍率字段** `hpMultiplier` / `atkMultiplier`（位置：`bossSpawns[]` / `spawnPoints[]`，缺省 `1.0`，存量图零影响）。**不改 `data/endgame.json` 的 `norm`** —— 无尽回廊与百首禁域共用同 10 个 Boss 的基底，改 norm 无法区分两图攻击倍率。
- **`Combat.resolve()` 增加末位可选参数 `min_damage: int = 1`**，末行改 `maxi(min_damage, int(damage))`；**只有怪物 → 玩家**两处调用点传入比例下限 `_min_hit_on_player()`（`clampi(round(max_hp × 0.0025), 10, 60)`）。玩家 → 怪物保持默认 1。
- **聚金地脉改 6 堆 × 16 席**确定性布点（堆内 3 格间距、堆心间距 ≥ 24 格）、`normalCap 28 → 32`、`xpMultiplier 0.5 → 0.1`。
- **金币上调**：`DT_C7_Gold_Normal.goldRange [176,224] → [440,560]`（×2.5，均值 500）。
- **Boss 侧倍率与经验**：`c7_arena` 血 ×2.0 / 攻 ×1.0 / 经验 `1.0 → 0.5`；`c7_boss_field` 血 ×2.0 / 攻 ×1.5 / 经验 `0.5 → 0.25`。
- **BREAKING（测试断言同步）**：`tests/endgame_cycle_map_test.gd` 中写死的 `96 席/上限 28`、`金币 176–224`、`xpMultiplier 0.5` 等断言按新口径更新；**只放宽到新口径，不得删除用例或用放宽掩盖回退**。
- **文档同步**：`data/maps/ch07/**/README.md` 的人工说明句与 `MAP PARAMETERS` 标记区、产品 13 / 06 / 03（§3.2 伤害下限表述）、工程 59 的口径回写。

## Impact

- Affected specs：满级后循环玩法（M10 系列）、战斗结算基础公式、经济（金币产出与药水消耗）
- Affected code：
  - [combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd)（`resolve` 新增参数）
  - [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd)（倍率应用、`_min_hit_on_player()`、两处怪物→玩家调用点）
  - [spawner.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/spawner.gd)（转发新字段）
  - [build_c7_cycle_maps.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/build_c7_cycle_maps.py)（重排布点 + 倍率）
  - `data/maps/ch07/c7_gold_field/map.json`、`c7_boss_field/map.json`（生成器产出）、`c7_arena/map.json`（20 席逐条补字段）
  - [dropTables.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/dropTables.json)（`DT_C7_Gold_Normal.goldRange`）
  - `tests/endgame_cycle_map_test.gd`、`tests/smoke_test.gd`（新增有牙断言）
- **不改动**：`data/endgame.json`、`data/layouts/*`（布点变化不改变掩码形状，`c7_gold_field` / `c7_boss_field` 的 `validate_and_layout` 会重算固定格坐标）、`player.gd` 的两处玩家→怪物调用点、`LevelGap`、药水数值。

## ADDED Requirements

### Requirement: Spawn 规格级血量/攻击倍率

系统 SHALL 允许 `spawnPoints[]` / `bossSpawns[]` 通过 `hpMultiplier` / `atkMultiplier` 覆盖单点结算后的血量与攻击，缺省 `1.0`。

#### Scenario: 存量图不受影响
- **WHEN** 某地图点规格未写 `hpMultiplier` / `atkMultiplier`
- **THEN** 怪物实例的 `max_hp` / `attack_power` 与改动前逐值相等

#### Scenario: 无尽回廊 Boss 血量翻倍
- **WHEN** `c7_arena.bossSpawns[]` 带 `hpMultiplier: 2.0`
- **THEN** 该 Boss 的 `max_hp` 与 `hp` 等于 `norm.hp × Balance.scale(L−60) × 2.0`（四舍五入、下限 1）

### Requirement: 不破防伤害下限（仅怪物 → 玩家）

系统 SHALL 在怪物攻击玩家时施加上限 60、下限 10 的按比例伤害下限：`min_hit = clampi(round(GameState.max_hp() × 0.0025), 10, 60)`。

#### Scenario: 高防玩家仍持续掉血
- **WHEN** 玩家防御聚合值使 `atk×mult − def×0.5` 归零
- **THEN** 怪物对玩家的单次伤害 ≥ `min_hit`（≥ 10），自动喝药被触发；`miss` 仍为 0 伤害

#### Scenario: 玩家打怪保持原手感
- **WHEN** 玩家攻击怪物且不破防
- **THEN** 伤害仍为 1（`min_damage` 默认值），前 60 级「打不动高防 Boss」的既有手感与既有伤害断言不变

## MODIFIED Requirements

### Requirement: 聚金地脉产出与密度

`c7_gold_field` 的 96 个普通怪席位 SHALL 由「12×8 稀疏点阵」改为「**6 堆 × 16 席**」：堆内相邻格距 3 格，堆心互相间距 ≥ 24 格，避开入口与出口缓冲；`normalCap` SHALL 为 `32`；`xpMultiplier` SHALL 为 `0.1`；重生 `15s` 不变；单只金币 `DT_C7_Gold_Normal.goldRange` SHALL 为 `[440, 560]`。

### Requirement: 循环 Boss 血量与经验

`c7_arena.bossSpawns[]` 每条 SHALL 带 `hpMultiplier: 2.0`、`xpMultiplier: 0.5`；`c7_boss_field.bossSpawns[]` 每条 SHALL 带 `hpMultiplier: 2.0`、`atkMultiplier: 1.5`、`xpMultiplier: 0.25`。两图的 `respawnTime 600` / `bossCap`（20 / 18）SHALL 保持不变。
