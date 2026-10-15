# A · 核心循环与战斗结算

> 问题域：`01-审计计划.md` §2 问题域 A。
> 基线快照：`773b7d1`；执行日期：2026-10-15。
> 判定标准：完整度 A–E、缺陷 P0–P3、证据等级 E1–E4 —— 均取自 `00-总体方法论.md` §4。
> 证据手段：静态阅读（E2）+ 隔离测试实测（E1）。实测命令：`python3 tools/run_isolated_tests.py <TestName>`。

---

## 1. 覆盖范围与未覆盖项

### 1.1 已覆盖

- 伤害结算纯函数： [combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L1-L49)。
- 玩家侧战斗入口与受击保护： [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L317-L364)、[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L461-L570)。
- 怪物侧 AI / 精英词缀 / Boss 阶段 / 首通 / 死亡结算： [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L146-L190)、[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L240-L291)、[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L370-L379)、[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L685-L737)。
- 掉落结算： [loot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/loot.gd#L26-L101)。
- 等级差经验： [level_gap.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/level_gap.gd#L1-L9)。
- 死亡惩罚与复活两路径： [death_penalty.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/death_penalty.gd#L1-L32)、[death_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/death_panel.gd#L57-L118)。
- 刷新 / 墓碑： [spawner.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/spawner.gd#L112-L246)、[boss_tombstone.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/boss_tombstone.gd#L1-L31)。
- 首通事件与存档链： [event_bus.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/event_bus.gd#L24)、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L1065-L1089)。
- 自动战斗（与手动共用结算）： [auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L1-L345)。
- 数据表： [monsters.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/monsters.json)、[skills.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/skills.json)、[mounts.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/mounts.json)、[miscItems.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/miscItems.json)。
- 产品基准：`产品文档/00`（核心循环图）、`03`（§3.2/§3.5/§3.8/§3.13/§3.14）、`04`（§4.7/§4.8）。

### 1.2 未覆盖（本次判定为「推断」或未评）

- `ground_item.gd` / `consumable.gd` 的地面拾取与药水使用细节（属 E/F 域主评）；本域仅确认「掉落 → 地面物 → 认领」链路存在。
- HUD / 飘字 / Toast 的具体呈现实现（属 F 域），本域只确认事件已广播。
- 任务系统内部推进逻辑（属独立域），本域只确认 `monster_died` / `boss_first_clear` 已发事件。
- 未做手动完整试玩（探索→战斗→掉落→升级→Boss→解锁全流程人手走查），故涉及「手感 / 观感」的结论均标推断。
- 未运行重量级 `SmokeTest`；`smoke_test.gd` 中相关断言按 E2/E3 引用。

---

## 2. 完整度评估（A–E 逐项 + 依据）

### 2.1 核心循环节点（问题 A-1）

| 产品 00 核心循环节点 | 分级 | 依据 |
|---|---|---|
| 探索地图 | **B** | 跨图由 `TravelExit` / 车夫 / 迷雾等实现（属地图/UI 域）；本域仅确认「有实现、门禁生效」，未评完整体验。 |
| 战斗 | **A** | [combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L30-L49) 纯函数结算；手动 [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L546-L570) 与自动 [auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L295-L304) 共用同一入口；有飘字/白闪/硬直/无敌帧反馈。 |
| 掉落（XP/装/药/金） | **A** | [loot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/loot.gd#L26-L101) 按 `dropTables` 结算；金币独立入账（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L731-L737)）；精英/Boss 批次持久化（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L744)）。 |
| 任务进度 | **B**（跨域） | `EventBus.monster_died` / `boss_first_clear` 已广播（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L708-L710)、[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L378)）；任务内部推进归任务域评。 |
| 拾取 / 使用（换装/嗑药） | **B** | 链路存在（`GroundItem` 认领 + `Consumable.use`，见 [auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L353-L361) 复用同一接口）；本域未通读 `ground_item.gd`/`consumable.gd`，缺自动化验证判 B。 |
| 升级 / 成长 | **A** | [game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L1065-L1089) 多级连升 + HP/MP 百分比结转 + 升级 Toast + `player_leveled` 事件；反馈齐全。 |
| 挑战精英 / Boss | **A** | 精英词缀接线（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L168-L190)）；Boss 三阶段接线（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L240-L291)）；`BossReviewTest` 实测 PASS（E1，见 §4）。 |
| 解锁下一区域 | **A** | 首通写 `unlocks.chapter2`（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L370-L379)），门禁由 [map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L183-L191) 的 `requiresUnlock` + `GameState.unlocks` 生效；`BossReviewTest` 实测 PASS（E1）。 |

> 结论：核心循环 8 节点中无 C/D 级，**链路本身不断链**。B 级项集中在跨域（探索、任务、拾取），非战斗结算本域缺陷，且均记录了理由。

### 2.2 公式与机制比对（问题 A-2）

| 产品条款 | 文档口径 | 代码实现 | 判定 |
|---|---|---|---|
| §3.2 基础伤害 | `max(1, floor(atk×系数 − def×0.5))` | [combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L40) `maxf(1.0, floorf(...))` | **一致** |
| §3.2 暴击 | `roll < criticalChance → floor(base×critMult)` | [combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L43-L46) | **一致** |
| §3.5 概率 Miss | `clamp(dodge/(dodge+50), 0, 0.75)` | [combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L7-L8)、[combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L23-L26) | **一致**（DODGE_K=50、封顶 0.75） |
| §3.8 暴击率 ≤75% | — | [combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L9) + [combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L43) `clampf(...,0,0.75)` | **一致** |
| §3.8 暴击倍率 ≤5.0 | — | [combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L10) + [combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L46) | **一致** |
| §3.8 攻击间隔 ≥0.2s | — | [combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L11)；玩家 [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L410-L412)、怪物 [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L609) 均经 `maxf(MIN_ATTACK_INTERVAL,...)` | **一致** |
| §3.8 冷却缩减 ≤50% | 属性结算时截断 | 代码**未接线**：`cdr` 仅被收集/展示（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L167)、[character_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/character_panel.gd#L189)），冷却按原值直接写入（[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L486)） | **偏差**（见 P2-1） |
| §3.8 格挡不做 | 首版不做 | `block` 仅保留字段（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L166)），不参与结算 | **一致（E）** |
| §3.4 受击硬直 0.2–0.4s | — | [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L21) `HITSTUN = 0.25` | **一致** |
| §3.4 无敌帧 0.5s | — | [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L20) `IFRAME = 0.5`；[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L320-L322) 无敌帧内返回 0 | **一致** |
| §3.4 击退 / 击倒 | 部分攻击造成位移/倒地 | 代码**无**击退/击倒实现 | **缺失**（见 P3-1） |
| §3.13 等级差经验 | `clamp(1−(pLv−mLv)×0.04, 0.2, 1.5)` | [level_gap.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/level_gap.gd#L5-L9)；由 [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L727) 调用 | **一致且已接线** |
| §3.13 越级伤害 dmgMult | `1+(mLv−pLv)×0.02`，上限 1.3 | 代码**无** `dmgMult` 实现（全库 `.gd` 无该逻辑） | **缺失**（见 P2-2） |

---

## 3. 问题清单

> 本域未发现 P0/P1。以下按严重度排列；跨域项（拾取/任务/UI）不在此重复。

### P2-1 冷却缩减（`cdr`）属性悬空，装备词条无实际效果

- **位置**：属性定义 [game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L166-L167)；展示 [character_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/character_panel.gd#L189)；冷却写入 [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L486)、[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L476)。
- **现象**：`cdr` 作为可收集属性在角色面板展示，但技能冷却一律按 `skill.cooldown` 原值写入，从不参与缩减计算；产品 §3.8 要求的「冷却缩减 ≤50%」上限也因此无从生效。
- **复现条件**：任意装备带 `cdr` 词条，施放 `earth_cleave` 后 `skill_cooldowns["earth_cleave"]` 恒为 4.0，与 `cdr` 无关。
- **影响**：装备 `cdr` 词条为「死属性」，玩家感知与配置预期不符；不影响主链路走通。
- **建议**：在冷却写入处统一乘以 `1 − clamp(cdr_总, 0, 0.5)`，并把 `cdr` 纳入缓存失效路径。
- **证据等级**：E2。

### P2-2 越级伤害倍率（产品 §3.13 `dmgMult`）未实现

- **位置**：经验实现了 [level_gap.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/level_gap.gd#L5-L9)；伤害侧无对应实现，[combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L30-L49) 仅接收 `multiplier`，无人注入越级系数。调用方 [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L557-L563)、[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L614-L618) 均传技能系数 / 1.0。
- **现象**：产品定义「玩家低于怪等级时伤害略增、怪打玩家同理（上限 1.3）」，代码只实现了经验差，未实现伤害差。
- **复现条件**：低等级角色攻击高等级怪，伤害与同级怪一致，无越级加成。
- **影响**：机制缺口，影响数值手感与「适度越级挑战」设计意图；不改动核心链路。
- **建议**：在 `Combat.resolve` 之外由调用方按 `LevelGap` 计算 `dmgMult` 并并入 `multiplier`，或扩展 `resolve` 签名；补齐等级差单测。
- **证据等级**：E2（无 `.gd` 命中 `dmgMult`/越级伤害逻辑）。

### P2-3 死亡面板「回安全区复活」失败路径静默无反馈

- **位置**：[death_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/death_panel.gd#L95-L113) `revive_camp()` —— L99、L108 两处 `return false`。
- **现象**：非营地死亡时，若当前场景无 `Game` 节点或 `_prepare_travel` 失败，按钮点击后无任何提示，面板仍停留；玩家无从判断原因。
- **复现条件**：在非标准场景（测试 / 异常状态）下死亡后点击「回安全区复活」。
- **影响**：违反 AGENT.md §9「失败路径要有明确反馈、不静默」——属边界体验问题，非主路径。
- **建议**：两处失败分支补 `EventBus.toast_requested` 提示（如「暂时无法返回安全区」）。
- **证据等级**：E2。

### P3-1 受击保护缺少击退 / 击倒

- **位置**：[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L317-L332)（仅硬直 + 无敌帧 + 闪烁）。
- **现象**：产品 §3.4 列「击退 / 击倒（部分攻击造成位移或短暂倒地）」，代码无位移 / 倒地实现。
- **影响**：ARPG 手感缺一档；不影响链路正确性。
- **建议**：按 §3.4 增加可配置 `knockback` 位移与 `knockdown` 状态（倒地期间不可行动但享无敌帧）。
- **证据等级**：E2。

### P3-2 第一章远程怪无投射物表现（机制可用、反馈缺失）

- **位置**：[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L164-L166) 读取 `attackRange.kind`；[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L495-L498) 仅对 `monster_id.begins_with("c2_")` 走 [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L624-L643) 投射物，其余走 `_do_attack`。
- **现象**：`ash_wraith`（[monsters.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/monsters.json#L86-L113)，`attackRange.kind=ranged`、`range=6.0`）在 6 格距离进入 `ATTACK` 并以瞬时方式结算伤害，无飞行动画/投射物表现；`is_ranged` 对该怪事实上未生效于表现层。
- **影响**：远程怪「保持距离攻击」在数值上成立，但视觉反馈缺失，玩家可能误判为瞬移伤害。
- **建议**：将投射物路径从 `c2_` 前缀扩展到 `is_ranged` 判定（或数据字段驱动），补齐反馈。
- **证据等级**：E2。

### P3-3 `monsters.json` 多字段运行时代码从未读取（数据悬空）

- **位置**：[monsters.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/monsters.json) 全表；代码侧无任何 `.gd` 命中这些键。
- **现象**：以下字段配置存在但运行时代码从不读取：
  - `accuracy`（产品 §3.5 计划用于「怪物命中对抗」）——**机制未实现**；
  - `resistType`（产品 §3.6 明确「预留」）——预留字段；
  - `monsterType`、`spawnWeight`、`tier`、`mpBase` ——数据冗余 / 未接线。
- **影响**：`accuracy` 是唯一带机制语义的悬空项（当前全表为 0，暂无功能影响）；其余为预留或冗余，属配置噪声。
- **建议**：`accuracy` 若确定纳入 §3.5 则补实现，否则从 Schema 移除或标注「预留」；`monsterType`/`spawnWeight`/`tier`/`mpBase` 明确保留意图或删除。
- **证据等级**：E2。

### P3-4 `bossSkill.phases` 部分字段冗余未读取

- **位置**：[monsters.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/monsters.json#L258-L281)；读取处 [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L246-L291)。
- **现象**：代码仅消费 `hpBelow` / `behavior` / `warnDelay` / `addAttackSpeedPct` / `summon` / `summonCount` / `radius` / `cooldown`；配置中的 `hpAbove` 与 `warn`（布尔）从未被读取。
- **影响**：字段冗余，不影响行为（阶段行为已由 `hpBelow` 正确驱动）。
- **建议**：删除或改为文档说明；保持「配置字段 = 代码消费字段」单一事实源。
- **证据等级**：E2。

### P3-5 `skills.json` 两个技能「数据已配置但不可施放」（已知缺口，记事实）

- **位置**：[skills.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/skills.json#L60-L90)（`armor_break` / `spirit_storm`）；入口过滤 [hotbar_config.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/hotbar_config.gd#L8)（`ACTIVE_SKILLS` 仅 4 项）、[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L417)、[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L463)。
- **现象**：`armor_break`（`defensePierce` / `debuff`）、`spirit_storm`（`hits` 多段）数据存在，但不入 `ACTIVE_SKILLS`，无法绑定 / 施放；对应 `defensePierce`、`hits` 亦无实现。
- **影响**：产品 §3.3 已明确二者「仅展示资料，不可配置或施放」，故**属声明内的 E 级缺口，不作为缺陷**；仅记录事实。
- **证据等级**：E2 / E3。

### P3-6 复活路径的自动存档时机重叠（可维护性）

- **位置**：[death_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/death_panel.gd#L85-L90) 先 `inventory_changed`（可能触发保存）再显式 `SaveManager.request_autosave()`。
- **现象**：原地复活可能在同一帧内触发两次保存请求（推断，取决于 `request_autosave` 是否去抖）。
- **影响**：最坏为一次多余写盘，无正确性风险（去抖机制见 [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L253)）。
- **建议**：确认 `request_autosave` 去抖覆盖该场景，或合并为单一保存入口。
- **证据等级**：E4（推断）。

---

## 4. 证据与复核方法

### 4.1 实测（E1）

| 命令 | 结果 | 覆盖结论 |
|---|---|---|
| `python3 tools/run_isolated_tests.py BossReviewTest` | **PASS**（`[BossReview] 全部通过 ✅`） | Boss 60%/30% 边界、践踏预警时序、狂暴召唤唯一、首通唯一（`clears == 1`）、Q005 推进、300s 墓碑、到期刷新、读档保留首杀与 `chapter2`、世界释放清理（[boss_review_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/boss_review_test.gd#L44-L132)）。 |
| `python3 tools/run_isolated_tests.py DeathChoiceTest` | **PASS** | 死亡暂停 + 面板显示、死亡关闭自动战斗、等待期间不自动复活、无卷不可原地复活、消耗卷复活并恢复满血蓝、营地免费复活不产生物品（[death_choice_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/death_choice_test.gd#L23-L39)）。 |
| `python3 tools/run_isolated_tests.py DeathDropTest` | **PASS** | 死亡只掉一件背包装备、保留原实例、药水/已穿戴/仓库不受影响、无背包装备无额外惩罚、重复死亡不多掉、原地复活可重新拾取（[death_drop_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/death_drop_test.gd#L31-L48)）。 |
| `python3 tools/run_isolated_tests.py SkillCombatTest` | **PASS**（`[SkillCombatTest] 全部通过 ✅`） | 主动技能命中上限、耗蓝/冷却只结算一次、冷却/蓝量/等级不足不施放、自动战斗复用玩家入口（[skill_combat_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/skill_combat_test.gd#L38-L136)）。 |

均以退出码 0 + 输出含 PASS + 无 `SCRIPT ERROR` 判定通过。

### 4.2 静态复核（E2）—— 关键行号索引

- 伤害公式 / 上限 / Miss：[combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L7-L49)。
- 精英词缀： [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L168-L190)。
- Boss 阶段： [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L240-L291)。
- 首通唯一结算： [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L370-L379)（先置 `first_clear` 再 emit）+ [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L686-L688)（`is_dead` 守卫，`_die` 重入直接返回）。
- 掉落结算： [loot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/loot.gd#L26-L45)。
- 等级差经验调用点： [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L727)。
- 死亡惩罚唯一触发： [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L334-L352)（`is_dead` 守卫）。
- 复活两路径： [death_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/death_panel.gd#L75-L113)。
- 刷新状态登记与墓碑： [spawner.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/spawner.gd#L195-L223)。
- 解锁门禁： [map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L183-L191)。
- 额外回归基准（本次未跑，按 E3 引用）： [smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L584-L623)（伤害/Miss/上限）、[smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L751-L754)（等级差经验）、[chapter_one_acceptance.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/chapter_one_acceptance.gd#L145-L161)（首杀与解锁）。

### 4.3 复现指令

```
python3 tools/run_isolated_tests.py BossReviewTest
python3 tools/run_isolated_tests.py DeathChoiceTest
python3 tools/run_isolated_tests.py DeathDropTest
python3 tools/run_isolated_tests.py SkillCombatTest
```

---

## 5. 落地优化方案

按「先闭合机制缺口、后补反馈」排序：

1. **冷却缩减接线（P2-1）**：新增单一入口 `LevelGap`/`Combat` 之外的最小工具（如 `Cooldown.apply(base, cdr, reduction_cap)`），在 [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L476) / [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L486) 与自动战斗施放入口统一调用；同步 `cdr` 缓存失效；补单测断言 `cdr=0.5 → 冷却减半`。
2. **越级伤害 dmgMult（P2-2）**：在 `Combat.resolve` 增加可选 `level_pressure` 形参或由调用方计算并入 `multiplier`；以 [level_gap.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/level_gap.gd) 同文件新增 `damage_multiplier(pLv, mLv)`，封顶 1.3；在玩家 / 怪物两处调用点接线；补边界单测（同等级 1.0、越级封顶 1.3）。
3. **死亡面板失败反馈（P2-3）**：为 [death_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/death_panel.gd#L99)、[death_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/death_panel.gd#L108) 两处补 Toast。
4. **远程怪投射物（P3-2）**：把 [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L495) 的 `c2_` 前缀判定改为 `is_ranged`，复用既有 `MonsterProjectile`。
5. **击退 / 击倒（P3-1）**：按 §3.4 扩展 `PlayerCharacter.apply_damage`，位移与倒地状态列入运行态（不入档）。
6. **数据表收敛（P3-3 / P3-4）**：`monsters.json` 明确 `accuracy`/`resistType` 的取舍（实现或标预留）；删除 `hpAbove`/`warn` 冗余或改注释；`skills.json` 的 `armor_break`/`spirit_storm` 保持「仅展示」标注，避免误判为已接线。

> 以上均为**建议**，本次审查按方法论 §7 不改动任何源码 / 配置 / 数据。

---

## 6. 与既有文档差异说明

1. **第一轮 P1（Boss 流程未接线）已闭环，与 `1a339d0` 表述一致**：现状代码确实读取了 `bossSkill.phases`（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L246-L291)）、写入 `first_clear` 并应用 `firstClearReward.unlock`（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L370-L379)）、创建 300s 墓碑并按点重生（[spawner.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/spawner.gd#L195-L223)），且 `BossReviewTest` 实测 PASS。第一轮结论可判「闭环」。
2. **刷新计时的跨图 / 跨档语义已超出第一轮回复的描述**：第一轮回复称「刷新点 / 墓碑计时仍属当前地图实例，离图释放、重进重建，不实现跨图或离线累积」。现基线代码已按 M4-10 重构为全局状态：`_remaining` 读 `GameState.spawn_remaining`、死亡时 `GameState.mark_spawn_dead` 登记、由 `world_time` 驱动（[spawner.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/spawner.gd#L5-L12)、[spawner.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/spawner.gd#L134-L136)、[spawner.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/spawner.gd#L201-L207)）。**报告差异**：回复时点的「不跨图」已不再准确；现行实现可跨图 / 跨档保持刷新剩余时间（详见工程文档 14）。建议以现状为准更新该条表述。
3. **产品 §3.13 只实现了一半**：文档把「等级差」定义为经验差 + 伤害差两段，代码只落地经验差；`dmgMult` 段缺失（P2-2）。属实现偏差，非文档冲突。
4. **产品 §3.8「冷却缩减 ≤50%」与产品 §3.3 表格**：`cdr` 在属性面板与词条池中存在，但无任何缩减实现（P2-1）；文档「超限部分在属性结算时截断」目前无从生效。
5. **`docs/产品需求梳理.md` 提及的 `firstClearClaimed` 额外保证 1 件 ≥稀有装备**：现行 [monsters.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/monsters.json#L283-L285) 的 `firstClearReward` 仅 `{unlock:"chapter2"}`，无「首杀额外保底装备」字段，代码亦未实现。该条来自**归档草案**（`docs/产品需求梳理.md`，已被 `docs/产品文档/` 取代），与产品 03 §3.12 的「结算首次通关奖励 → 推进 Q005 → 解锁入口」一致，故**不作为缺陷**，仅记录为「草案留存项」。
6. **排除项确认**：本次未将 `ArtSampleTest`、`ChapterOneArtTest`、`QualityFrameTest`、`IconIntegrationTest` 等既有失败基线列为新问题；未把「第二章地图 / 任务 / 怪物内容」与「具体数值调平」纳入扣分。

---

## 附：本域完整度总评（供 Z 域汇总引用）

- 核心循环 8 节点：无 C/D 级；A 级 5 项、B 级 3 项（探索 / 任务 / 拾取，均属跨域且记录理由）。
- 战斗结算公式与文档**逐项一致**（伤害 / 暴击 / Miss / 四项上限 / 受击保护时长）。
- 死亡与复活两路径**闭环且无重复结算**（E1 实测）。
- Boss 三阶段 / 首通唯一 / 墓碑刷新**闭环**（E1 实测），第一轮 P1 已闭环。
- 未闭环项集中在**机制缺口与悬空数据**：`cdr` 无效果、越级伤害缺失、击退/击倒缺失、远程怪无投射物、`monsters.json` 部分字段悬空 —— 均为 P2/P3，**不阻断核心交付**。
