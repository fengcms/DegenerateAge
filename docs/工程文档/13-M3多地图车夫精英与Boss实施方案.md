# 13 M3 多地图 / 车夫 / 精英 / Boss 实施方案

> **状态**：**已拍板；批次 1「出行骨架」已完成**（2026-10-12 —— 用户对 Q1–Q8 **全部按推荐**，见 §8 / §10；执行记录见 §11）
> **日期**：2026-10-12
> **上游依据**：产品文档 `07`（地图关卡与怪物）、`06`（经济与 NPC）、`03` §3.12/3.13/3.14/3.15、`09` §9.1/9.5/9.13；工程文档 `02` §6（M3 施工图）、`08` §5（M3 恢复清单）
> **上游已完成**：M0 脚手架 / M1 货郎经济闭环 / M2 任务系统 / M2.5 消耗品与自动喝药

---

## 1. 目标

从「一张图刷怪」升级为**完整第一章流程**：

```
幸存者营地(安全区 L1)
      │ 车夫（跨图）
      ▼
试炼野外(L1–5) ──→ 灰烬之地(L5–9) ──→ 腐化源头(L10 Boss区)
  精英狼王            远程怪登场          腐化巨兽（三阶段）+ 墓碑
```

出口判据（`工程文档 02` §6）：
1. 无头回归通过；
2. **T08 / T09 / T12 / T13 / T14 / T15 全部通过**；
3. 能从营地出发，经车夫跨图，打到第一章 Boss 并触发首杀标记。

---

## 2. 现状核查（结论先行：**数据层几乎全就绪，M3 主要是接线 + 补缺口**）

### 2.1 已就绪（可直接复用，**不要重造**）

| 项 | 现状 | 位置 |
|---|---|---|
| **4 张地图定义** | `size` / `tierRange` / `safeZone` / `recommendedLevel` / **`carterLinks`** / `spawnPoints` / `bossSpawn` 全部齐 | `data/maps.json` |
| **精英数据** | `elite_wolf_king` 已带 `affixes:["fast"]` + `specialAttack:"slow"` | `data/monsters.json` |
| **Boss 三阶段数据** | `boss_corrupted_beast.bossSkill.phases`：`hpAbove 0.6 chase_claw` / `hpBelow 0.6 aoe_stomp(warn)` / `hpBelow 0.3 enrage_summon(+30%攻速, 召 2 只)` | `data/monsters.json` |
| **Boss 首通奖励** | `firstClearReward: {unlock:"chapter2"}` | `data/monsters.json` |
| **5 张掉落表** | 含 `DT_Ash_L1`(L5–9) / `DT_Boss_L1`（含 rune 产出） | `data/dropTables.json` |
| **当前地图字段** | `GameState.current_map`（默认 `camp`） | `autoload/game_state.gd:24` |
| **首杀标记** | `GameState.first_clear`（`boss_id -> bool`） | `autoload/game_state.gd:30` |
| **解锁标记** | `GameState.unlocks`（`{chapter2: true}`） | `autoload/game_state.gd:31` |
| **地图变更信号** | `EventBus.map_changed(map_id)` **已定义、未使用** | `autoload/event_bus.gd:51` |
| **存档链** | `SaveManager` 已采集 / 应用 `currentMap` + `firstClear` + `unlocks` | `autoload/save_manager.gd:99/104/105/287/292` |
| **读档出生点机制** | `GameState.has_save_pos` / `save_pos` / `clear_save_pos()`，`game.gd::_ready()` 已消费 | `autoload/game_state.gd:45`、`game.gd:54` |
| **按地图生成怪** | `MonsterSpawner.spawn_from_map(map_id)` **接口已预留** | `scripts/world/spawner.gd:38` |
| **地图数据加载** | `IsoGround.map_id`（`@export`）+ `_load_map()` 读 `maps.json` | `scripts/world/ground.gd:9/24` |
| **任务范围校验** | `Quest._in_scope()` 已按最终设计读 `mapScope` vs `current_map` | `scripts/systems/quest.gd:181` |
| **自动战斗底座** | 10 态状态机 + **卡住检测 → 3 次不推进 → 8s 黑名单改选**（T08 基础）+ **manualOverride 手动接管**（T09） | `scripts/systems/auto_battle.gd:48–86` |
| **本地化预留** | `ui.carter.travel = "前往地图"`、`toast.map_unlocked = "新区域已解锁"` | `data/localization.json` |
| **怪物死因链** | `Monster._die()` → `died` / `EventBus.monster_died` | `scripts/entities/monster.gd:247` |

### 2.2 缺口（M3 要补的）

| # | 缺口 | 影响 | 现状证据 |
|---|---|---|---|
| **G1** | **无地图切换 API** | M3-1 | 全文无 `change_map` / `travel_to` / `reload_current_scene` |
| **G2** | `IsoGround.map_id` 在 `Game.tscn` **硬编码 `"camp"`**；`game.gd` 用 `TEST_SPAWNS` 硬编码 | M3-1 | `scenes/Game.tscn`、`game.gd:10` |
| **G3** | **无车夫 NPC**（`role` 只有 `shop`/`quest`）；`maps.json` **无车夫费用字段** | M3-2 | `npc.gd:22`、`maps.json` 无 `cost`/`fee` |
| **G4** | **无小地图渲染、无战争迷雾**（`MapPanel` 只有地图名 + 坐标占位） | M3-3 | `scenes/ui/Hud.tscn:254–289` |
| **G5** | 代码**未读** `affixes` / `specialAttack` | M3-4 | `monster.gd` 全文无 `affix` |
| **G6** | 代码**未读** `bossSkill.phases`；无警示圈 / 无召唤 / **无墓碑** / **无首杀结算** | M3-5 | `monster.gd` 全文无 `bossSkill` / `tombstone` / `first_clear` |
| **G7** | **无区域等级梯度、无等级差** `expMult` / `dmgMult` | M3-6 | `Combat` 无 `dmgMult`；`_settle_rewards` 直接给 `xpReward` |
| **G8** | **无 Tab 目标锁定**（无锁定目标 / 无指示圈 / 无 HUD 目标同步 / 无超距走位） | M3-7 | `game.gd` InputMap 无 `target_lock` |
| **G9** | **T13 暂停无收益 / T14 死亡关自动战斗**未核查实现 | M3-8 | `player._begin_death()` 未见关闭自动战斗 |
| **G10** | `quests.json` Q002–Q005 `mapScope` 仍是 M2 临时值 `["camp"]` + `_m2Temp` | 恢复清单 | `data/quests.json:21/34/47/60` |
| **G11** | `TEST_ELITES`（精英/Boss 测试点）+ debug 守卫仍在 | 恢复清单 | `game.gd:23/73` |
| **G12** | `TEST_NPCS` 硬编码（含长老） | 恢复清单 | `game.gd:36` |

---

## 3. 子步骤拆解（对应 `工程文档 02` §6）

### M3-1 多地图加载与切换

**交付物**：地图切换服务 + `game.gd` 改为「按 `GameState.current_map` 数据驱动装配」。
**实现要点**：

1. 新增 `scripts/systems/map_service.gd`（`MapService`）：
   - `travel_to(map_id) -> Dictionary`（`{ok, reason}`）：`①` 目标存在 → `②` 解锁校验（`carterLinks` 拓扑 + `unlocks`）→ `③` 扣费（M3-2）→ `④` 写 `GameState.current_map` → `⑤` 写 `GameState.save_pos`（落该图出生点）→ `⑥` `get_tree().reload_current_scene()`；
   - `current_map_data()` / `map_display_name()` / `is_unlocked(map_id)`。
2. `game.gd`：删 `TEST_SPAWNS` / `TEST_ELITES`，改 `_spawner.spawn_from_map(GameState.current_map)`；`IsoGround.map_id` 由 `game.gd` 在 `_ready()` 里按 `GameState.current_map` 注入（**保留 `Game.tscn` 的默认值只作编辑器预览**）。
3. `bossSpawn` 走 `spawner`（M3-5 启用墓碑逻辑）。
4. HUD 地图名/坐标：已连 `EventBus.map_changed` → 切图后自动刷新（`hud.gd:90`）。

**验收判据（T15）**：切图后坐标正确（落在新图中心/出生点）、实体全新（无上一张图的怪/NPC/掉落残留）、无重复事件注册。

**🔴 关键技术选择见 §4 D1。**

### M3-2 车夫跨图

**交付物**：车夫 NPC + `CarterPanel.tscn` + 费用数据。
**实现要点**：

1. `maps.json` 每图新增车夫数据（**见 §4 D2 的字段方案**）。
2. `npc.gd` 的 `role` 新增 `"carter"`；`game.gd::_try_interact()` 加 `carter` 分支 → `EventBus.carter_panel_requested.emit(npc.npc_name)`。
3. 新增 `scripts/ui/carter_panel.gd` + `scenes/ui/CarterPanel.tscn`（**与 `QuestPanel` 同构**：标题 + 目的地列表，每行「目的地名 / 推荐等级 / 费用 / 前往按钮」，金币不足 → 按钮禁用 + 原因提示）。
4. 前往 → `MapService.travel_to(to_id)`；失败理由明确（未解锁 / 金币不足 / 已达该图）。

**验收判据**：营地↔试炼野外免费/低价；试炼野外→灰烬之地→腐化源头需付费；**中转拓扑与 `07` §7.8 一致**（不能从营地直达灰烬之地）。

### M3-3 战争迷雾与小地图揭示 —— ✅ 已完成（2026-10-12）

**交付物**：`MapPanel` 升级为真小地图 + 迷雾遮罩 + 大地图弹窗（`M` 键 / 点小地图）。
**实现要点**：

1. `scripts/systems/fog.gd`（`Fog`）：已探索集合（**块粒度 `4×4` 格**，60×60 → 15×15 = 225 块/图，体积可控）；`reveal(cell)` 以玩家为中心揭 8 格半径；`is_explored(cell)`。
2. `Hud.gd`：`MapPanel` 内加 `Minimap`（`Control` + `_draw()` 画菱形地图轮廓 + 已探索块 + 玩家点 + 目标点）。
3. 大地图弹窗：新增 `MapBigPanel.tscn`（整图 + 已探索遮罩 + 任务目标点/Boss 点标记）。
4. **是否入档见 §4 D4。**

**验收判据**：已探索常显、未探索暗显；接取任务后目标点在图上出现；重进该图（若入档）保留探索进度。

### M3-4 精英与词缀 —— ✅ 已完成（2026-10-12）

**交付物**：词缀表 + 生效逻辑 + 外观/名称区分。
**实现要点**：

1. 新增 `data/affixes.json`：`狂暴(攻+30%/攻速+20%)` / `寒霜(减速20% 2s)` / `坚硬(防+50%)` / `迅捷(移速+30%)` / `召唤(死亡召2只)` / `吸血(伤害5%回血)`（对应 `07` §7.7）。
2. `monsters.json` 精英改配 `affixPool: ["fast","frost",...]`（**随机池**，见 §4 D5）+ `affixCount: [1,2]`；保留 `specialAttack`。
3. `monster.gd`：`_load_template()` 后按池随机抽 1–2 条 → 应用到 `attack_power` / `attack_interval` / `defense` / `move_speed_px` / 附伤（减速/吸血）/ 死亡召唤。
4. 外观：精英描金边 + 名称前缀（如「迅捷的裂爪狼王」）。

**验收判据**：精英带词缀生效（数值可测）；名称/外观与普通怪区分。

### M3-5 Boss 与阶段行为

**交付物**：Boss 三阶段 + 警示圈 + 墓碑 + 首杀结算。
**实现要点**：

1. `monster.gd` 读 `bossSkill.phases`，按 `hp_ratio()` 切阶段：
   - `>60%`：普通追击 + 爪击（现有逻辑）；
   - `<60%`：周期性 `aoe_stomp`——**先画地面警示圈 → 延迟 0.8s → 对圈内结算**（`warn:true`）；自动战斗不得跳过（3.14 硬性规则）；
   - `<30%`：`enrage_summon`——攻速 ×1.3 + 召唤 `summonCount` 只 `summon` 怪（一次性，不重复）。
2. **墓碑**：Boss 死亡 → 生成 `Tombstone`（`data/maps.json` 的 `bossSpawn.respawnTime` = 300s 倒计时显示）→ 倒计时结束重生。
3. **首杀结算**：`Monster._die()` 若 `kind=="boss"` 且 `!GameState.first_clear[boss_id]` → 置 `true` + `EventBus.boss_first_clear.emit(boss_id)` → 应用 `firstClearReward.unlock`（`chapter2`）。
4. Q005 的 objective 是 `kill boss_corrupted_beast ×1`，**复用现成 `monster_died` 链**即可推进（首杀标记与任务推进互相独立）。

**验收判据（T12）**：Boss 首杀唯一（第二次击杀不再给首通奖）；三阶段行为可观测。

### M3-6 区域等级梯度 / 等级差

**交付物**：`spawnLevel` 受 `tierRange` 约束；`expMult` / `dmgMult`（`03` §3.13）。
**实现要点**：

1. `spawner` 生成时按 `maps.json.tierRange` + 怪物点 `level` 定 `spawn_level`（现状已可传 `level`）。
2. `Combat.resolve()` 增越级 `dmgMult`；`Monster._settle_rewards()` 的经验走 `expMult`。
3. **🔴 见 §4 D7 —— 这会改动 M1 已校准的 TTK 与升级曲线。**

**验收判据**：高等级怪更强；高等级回低图经验衰减符合公式。

### M3-7 Tab 目标锁定 + 超距走位

**交付物**：Tab 循环锁定 + 脚下高亮圈/名称条 + HUD 目标区同步 + 超距自动走位。
**实现要点**：

1. `project.godot` InputMap 加 `target_lock`（`Tab`）。
2. `game.gd` 维护 `locked_target`；Tab 在**可视区域内敌对单位**间按距离升序循环（无锁定 → 最近；有锁定 → 下一个；空 → Toast「附近无目标」）。
3. 指示：`Monster` 加「被锁定」高亮圈 + `Hud.TargetPanel` 同步（头像/名称/血蓝——HUD 已有 `TargetPanel`）。
4. 攻击入口（Space / 左键 / 技能格）作用于锁定目标；**超距 → 复用 `AutoBattle` 的 `pathToTarget` 走位**（3.15 明确「不另写一套」）。
5. 退出锁定：目标死亡/消失/切图；空闲右键**保留**锁定（9.10）。

**验收判据**：Tab 循环切换正确；超距自动走位到范围内再攻击。

### M3-8 手动 / 自动接管互斥

**交付物**：T08 / T09 / T13 / T14 全部通过。
**实现要点**：

| 场景 | 现状 | 动作 |
|---|---|---|
| **T08** 不可达目标自动改选 | 🟡 已有黑名单机制（3 次不推进 → 8s 黑名单） | 补冒烟用例验证 |
| **T09** 手动接管自动战斗 | 🟡 已有 `manualOverride` + 3s 恢复 | 补冒烟用例验证 |
| **T13** 暂停无收益增长 | ❓ 未核查 | 确认「暂停/失焦/面板打开」时是否完全停决策（3.14：暂停/后台 → 停决策） |
| **T14** 死亡自动关自动战斗 | ❌ `player._begin_death()` 未见关闭 | **新增**：死亡时 `GameState.set_auto_battle(false)` |

**验收判据**：4 项各有冒烟断言 + 实机可复现。

---

## 4. 关键设计决策（**待拍板**）

### D1 地图切换机制 —— 🔴 影响 M3-1 全部

```
方案 A：重载当前场景（reload_current_scene）+ GameState.save_pos 传位置
   ✅ 与现有架构一致（has_save_pos / clear_save_pos 就是为此设计）
   ✅ T15「清旧实体」天然满足（整场景重建）
   ✅ 内存/事件注册一次性归零，无残留风险
   ⚠ UI 面板状态/T oast 历史重建（可接受）

方案 B：原地卸载 Game 下实体 + 换 map_id 重建（UI/玩家实例保留）
   ✅ 更快、不闪
   🔴 需手动清理 Npcs/Spawner/LootRoot/Monsters/DamageNumbers + 重连信号
   🔴 漏一处 → 事件重复注册 / 孤儿节点 / 内存增长（正是 T15 要防的）
```

> **推荐 A**：项目里 `GameState.save_pos` + `clear_save_pos` 的整套机制**本来就是给「重载场景式切图」准备的**（`game.gd:54` 注释写明「M1-10，10.3 当前地图与坐标」）。选 A 等于顺着既有设计走，风险最低。

### D2 车夫费用与拓扑数据 —— 🔴 数值变更（铁律：必须用户确认）

产品 `06` §6.6 只说「点击扣金币切换地图」，**未给数值**。现状 `carterLinks` 是纯字符串数组（`["wild_trial"]`），**无费用字段**。

```
方案 A：新增平行字段（不改现有结构，风险最低）
  maps.json 每图加：
    "carterFees": { "wild_trial": 30 }        ← 按目标图 id 记费用
  保留 "carterLinks": ["wild_trial"]          ← 拓扑不变，Quest._in_scope / 现有读取点零影响

方案 B：升级 carterLinks 为对象数组
  "carterLinks": [ { "to": "wild_trial", "cost": 30 } ]
  🔴 牵动所有读 carterLinks 的地方（含 08 §8.3 支线范围重算）
```

> **推荐 A** + 推荐费用表（按目标图 `recommendedLevel` 递增，**待用户确认**）：

| 路线 | 推荐费用 | 依据 |
|---|---|---|
| 营地 → 试炼野外 | **0**（首个出行免费） | 新手引导，避免开局卡死 |
| 试炼野外 → 营地 | 20 | 回城 |
| 试炼野外 → 灰烬之地 | 50 | L6 图 |
| 灰烬之地 → 试炼野外 | 50 | |
| 灰烬之地 → 腐化源头 | 100 | L10 图 |
| 腐化源头 → 灰烬之地 | 100 | |

### D3 车夫 UI 形态

```
方案 A：新建 CarterPanel.tscn（与 QuestPanel 同构，列表 + 前往按钮）   ← 推荐
方案 B：做通用「对话 + 菜单」框架（6.3 完整设计，M4 才需要）
```

> **推荐 A**：M2 的 `QuestPanel` 已验证同构面板模式，复制风险最低；6.3 的通用对话框架留给 M4/M5-5。

### D4 迷雾「已探索」是否入档

```
方案 A：入档（explored: { mapId: [块索引...] }，块粒度 4×4）
   ✅ 重进保留探索进度（符合 7.4 探索体验）
   ⚠ 存档体积：4 图 × 225 块 → 稀疏存储可控（也可 base64 位图）

方案 B：不入档（每次进图重置）
   ✅ 存档零负担
   🔴 「探索揭示」体验打折扣（重进即全黑）
```

> **推荐 A（块粒度 4×4 + 稀疏数组）**：`07` §7.4 明确「探索揭示」是设计目标；块粒度把体积压到 1/16。

### D5 精英词缀：数据写死 vs 运行时随机池 —— 影响「数据驱动」铁律

```
现状：elite_wolf_king 写死 "affixes": ["fast"]

方案 A：新增 data/affixes.json + monsters.json 配 affixPool，运行时随机抽 1–2 条   ← 推荐
   ✅ 符合 07 §7.7「随机取 1–2 条（数据可配）」
   ✅ 符合项目铁律「新增内容 = 加 JSON，不改代码」
方案 B：沿用写死 affixes 列表
   ❌ 与 07 §7.7「随机」口径不符
```

> **推荐 A**。

### D6 Boss 首杀结算口径

```
方案 A：Monster._die() 内判 kind==boss && !first_clear[id] → 置 true + emit + 应用 unlock   ← 推荐
方案 B：由任务系统（Q005）反向驱动
```

> **推荐 A**：`03` §3.12 的顺序是「结算首通奖 → 推进 Q005 → 解锁入口」，首杀是**独立事实**（`first_clear` 字段早已存在且入档），与任务推进解耦更稳。

### D7 等级差（`03` §3.13）启用范围 —— 🔴 影响 M1 已校准数值

```
公式：expMult = clamp(1 - (playerLv - monsterLv) × 0.04, 0.2, 1.5)
      dmgMult = clamp(1 + (monsterLv - playerLv) × 0.02, 1.0, 1.3)

方案 A：全量启用（严格按公式）        → 会改变 07 文档复核的 TTK（野狼 3.6s 等）
方案 B：M3 只启用 expMult，dmgMult 延后 → 升级曲线变化可控，TTK 不动
方案 C：M3 暂不启用，等 M4 技能接线后一并校准   ← 最保守
```

> **推荐 B**：`expMult` 是「防高等级回低图刷」的核心（不影响 TTK，只影响升级速度）；`dmgMult` 会改动已校准战斗数值 → 留给「M4 技能系统接线后统一重跑校准（07 文档）」。**若选 A/C 请明确。**

### D8 Tab 锁定与自动战斗的优先级

`03` §3.15 已明确：「手动攻击期间若开启 `F` 自动战斗，**自动决策接管目标选择，忽略手动锁定**」。

> **不做选项，直接按产品文档实现**：`F` 开启时锁定失效（但保留 `locked_target` 不丢失），关闭后恢复。

---

## 5. 风险登记

| # | 风险 | 等级 | 缓解 |
|---|---|---|---|
| **R-a** | 地图切换实体清理不彻底 → 事件重复注册 / 孤儿节点 / 内存增长 | 🔴 高 | 选 D1-A（整场景重载）；`SoakTest` 增加切图脉冲；`alive_count()` / 孤儿节点断言 |
| **R-b** | `dmgMult` / `expMult` 上马 → 改变 M1 已校准 TTK 与升级曲线 | 🔴 高 | 选 D7-B（只上 `expMult`）；若上 `dmgMult` 须重跑 `tools/balance_check.py` |
| **R-c** | `carterLinks` 结构变更牵动现有读取点 | 🟡 中 | 选 D2-A（新增平行字段，不动 `carterLinks`） |
| **R-d** | 迷雾入档增大存档体积 | 🟡 中 | 块粒度 4×4 + 稀疏数组；必要时 base64 位图 |
| **R-e** | Boss 警示圈 AOE 秒杀玩家（L10 攻击 22 × 范围） | 🔴 高 | 警示圈延迟 0.8s + 明确可见；伤害按 `Combat.resolve` 正常结算（不额外放大） |
| **R-f** | **`TEST_ELITES` 移除时机**：移除后 Q004/Q005 在单图期会再次卡死 | 🔴 高 | **必须 M3-1/M3-5 完成后**才移除；移除后 `quests.json` 的 `mapScope` 同步恢复真值 |
| **R-g** | Tab 锁定与自动战斗目标选择互相干扰 | 🟡 中 | 按 D8 实现（`F` 开时忽略锁定） |
| **R-h** | 车夫费用是**新数值**，属「数值变更」 | 🟡 中 | 遵守铁律：**用户确认 §4 D2 费用表后才落地** |
| **R-i** | 切图后玩家坐标越界（目标图尺寸不同：营地 40×40 / 野外 60×60 / 源头 50×50） | 🟡 中 | 复用 `IsoGround.clamp_to_map()`；出生点统一取「安全区中心」或「地图入口点」 |

---

## 6. 执行清单（R1–R13）

| # | 待办 | 文件 | 批次 |
|---|---|---|---|
| **R1** | `maps.json` 补车夫费用（D2-A）+ 各图 `npcs` 数组（货郎/车夫/任务官数据化） | `data/maps.json` | 1 |
| **R2** | 新增 `MapService`（`travel_to` / 解锁校验 / 扣费 / 写 `save_pos` / 重载场景） | `scripts/systems/map_service.gd`（新） | 1 |
| **R3** | `game.gd` 改为数据驱动装配（`spawn_from_map` + `npcs` 注入 + 按图生成 Boss 点）；移除 `TEST_SPAWNS` / `TEST_ELITES` / `TEST_NPCS` + debug 守卫 | `scripts/world/game.gd`、`scenes/Game.tscn` | 1 |
| **R4** | 车夫 NPC（`role="carter"`）+ `CarterPanel`（目的地 / 推荐等级 / 费用 / 前往） | `npc.gd`、`scripts/ui/carter_panel.gd`（新）、`scenes/ui/CarterPanel.tscn`（新）、`scenes/Main.tscn` | 1 |
| **R5** | **恢复清单**：`quests.json` Q002–Q005 `mapScope` 还原真值 + 移除 `_m2Temp`；支线 S001/S002 按「附属地图 `M ∪ carterLinks(M)`」重算 | `data/quests.json` | 1 |
| **R6** | 精英词缀：新增 `data/affixes.json` + `monster.gd` 读 `affixPool` 随机抽 1–2 条并生效 + 精英外观/名称区分 | `data/affixes.json`（新）、`data/monsters.json`、`monster.gd` | 2 |
| **R7** | Boss 三阶段（`bossSkill.phases`）+ 警示圈 + 狂暴召唤 + **墓碑倒计时重生** + **首杀结算** | `monster.gd`、新增 `scripts/entities/tombstone.gd` | 3 |
| **R8** | 等级差：`Combat` 增 `dmgMult`（若 D7 选 A）；`Monster._settle_rewards` 经验走 `expMult` | `scripts/systems/combat.gd`、`monster.gd` | 2 |
| **R9** | Tab 锁定 + 指示圈 + HUD 目标区同步 + 超距走位（复用 `AutoBattle.pathToTarget`） | `project.godot`、`game.gd`、`monster.gd`、`hud.gd` | 2 |
| **R10** | M3-8 互斥收口：T14 死亡关自动战斗（新增）；T08/T09 补测；T13 核查修缺口 | `player.gd`、`game_state.gd` | 1 |
| **R11** | 小地图 + 迷雾 + 大地图弹窗（含 D4 入档决策） | `scripts/systems/fog.gd`（新）、`hud.gd`、`scenes/ui/MapBigPanel.tscn`（新） | 2 |
| **R12** | 冒烟新增用例：切图清零（T15）/ 车夫扣费+拓扑 / 首杀唯一（T12）/ 等级差 / Tab 锁定 / 死亡关自动（T14） | `tests/smoke_test.gd` | 各批 |
| **R13** | 三层验证 + 专项回归（`SoakTest` 加切图脉冲；**须先关游戏会话**）+ 文档同步 + 提交推送 | — | 各批 |

---

## 7. 实施顺序与分批建议

M3 规模 ≈ M1 + M2 之和（8 子步骤 / 6 验收场景 / 12 缺口）。**建议分 3 批推进**，每批结束都跑三层验证 + 提交：

```
批次 1「出行骨架」  M3-1 多地图 + M3-2 车夫 + M3-8 互斥收口 + 恢复清单
  目标：能从营地经车夫跨图；T08/T09/T13/T14/T15 全绿
  依赖：无（M3 的地基）
        │
        ▼
批次 2「探索与内容」 M3-3 迷雾小地图 + M3-4 精英词缀 + M3-6 等级差 + M3-7 Tab 锁定
  目标：探索揭示 + 精英带词缀 + Tab 锁定；等级差（按 D7 范围）
        │
        ▼
批次 3「Boss 收官」  M3-5 Boss 三阶段 + 墓碑 + 首杀
  目标：完整第一章流程贯通；T12 通过；出口全项
```

> **一次性全做也可行**，但批次 3 的 Boss 战依赖批次 1 的多图与批次 2 的等级差，且 `TEST_ELITES` 的移除时机（R-f）必须在 M3-1/M3-5 之后 —— 分批能把风险切开。

---

## 8. 待拍板项（Q1–Q8）—— ✅ 已全部拍板（2026-10-12，**全部按推荐**）

| # | 问题 | 选项 | **拍板结果** |
|---|---|---|---|
| **Q1** | 推进方式 | ① 分 3 批 ② 一次性全做 | ✅ **① 分 3 批** |
| **Q2** | 地图切换机制（D1） | ① 重载场景 + `save_pos` ② 原地重建实体 | ✅ **① 重载场景 + `save_pos`** |
| **Q3** | 车夫费用（D2） | ① 按推荐费用表 ② 全免费 ③ 你指定 | ✅ **① 按推荐费用表**（营地→野外 0／野外→营地 20／野外→灰烬 50／灰烬→源头 100） |
| **Q4** | 等级差启用范围（D7） | ① 全量（含 `dmgMult`） ② 只上 `expMult` ③ M3 暂不启用 | ✅ **② 只上 `expMult`**（`dmgMult` 延后到 M4，避免动 M1 已校准 TTK） |
| **Q5** | 车夫 UI（D3） | ① 新建 `CarterPanel` ② 通用对话框架 | ✅ **① 新建 `CarterPanel`** |
| **Q6** | 迷雾是否入档（D4） | ① 入档（块粒度 4×4） ② 不入档 | ✅ **① 入档（块粒度 4×4）** |
| **Q7** | 精英词缀（D5） | ① 数据表 + 随机池 ② 沿用写死 | ✅ **① `affixes.json` + 随机池** |
| **Q8** | Boss 首杀口径（D6） | ① 怪物侧独立结算 ② 任务侧驱动 | ✅ **① 怪物侧独立结算** |

---

## 9. 验收与验证口径

每批结束必跑：

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . --import                    # A0 新增 class_name 后必跑
"$GODOT" --headless --path . res://tests/SmokeTest.tscn  # A 冒烟：退出码 0
"$GODOT" --headless --path . --quit                      # B 启动回归：0 SCRIPT ERROR + 配置校验通过
```

专项：
- **切图卫生（T15）**：切图前后 `get_tree().get_nodes_in_group("enemies")` / 孤儿节点数 / `EventBus` 连接数对比。
- **首杀唯一（T12）**：击杀 Boss → 置 `first_clear` → 再杀一次 → 断言不重复发奖。
- **等级差**：同怪同装备在等级差 0 / +5 / −5 下 TTK 与经验对比（若启用 `dmgMult` 须重跑 `tools/balance_check.py`）。
- **SoakTest**：加「周期性切图」脉冲；⚠ **跑之前必须关掉游戏会话**（M2 轮已踩过「实时会话互抢存档」）。
- **玩家存档未被污染**：测试前后 `md5(slot_1.json)` 一致。

M3 出口（`工程文档 02` §6）：
- [ ] 无头回归通过
- [ ] T08 / T09 / T12 / T13 / T14 / T15 全部通过
- [ ] 能从幸存者营地出发，经车夫跨图，打到第一章 Boss 并触发首杀标记

---

## 10. 拍板结果（✅ 已确认，2026-10-12）

| # | 决策 |
|---|---|
| Q1 | ✅ 分 3 批推进 |
| Q2 | ✅ 重载场景 + `save_pos`（D1-A） |
| Q3 | ✅ 按推荐费用表（营地→野外 0 / 野外→营地 20 / 野外→灰烬 50 / 灰烬→源头 100） |
| Q4 | ✅ 只上 `expMult`（`dmgMult` 延后 M4） |
| Q5 | ✅ 新建 `CarterPanel` |
| Q6 | ✅ 迷雾入档（块粒度 4×4） |
| Q7 | ✅ `affixes.json` + 随机池 |
| Q8 | ✅ 怪物侧独立结算首杀 |

> 口径已落地至代码 / 数据；执行证据见 §11。

---

## 11. 执行记录

### 批次 1「出行骨架」—— ✅ 已完成（2026-10-12）

**范围**：M3-1 多地图加载与切换 / M3-2 车夫跨图 / M3-8 互斥收口 + M3 恢复清单（执行清单 R1–R5、R10、R12、R13）。

**交付物（新增）**：

| 文件 | 说明 |
|---|---|
| `autoload/map_service.gd` | Autoload `MapService`：`travel_to` / `reload_world` / `entry_point` / `destinations` / `current_npcs` / `current_boss` / `is_unlocked` / `fee_to` |
| `scripts/ui/carter_panel.gd` + `scenes/ui/CarterPanel.tscn` | 车夫面板（与 `QuestPanel` 同构：目的地 / 推荐等级 / 费用 / 前往按钮） |
| `tests/carter_shot.gd` + `tests/CarterShot.tscn` | 车夫面板截图工具（营地 1 条 / 灰烬之地 2 条两态） |

**修改文件**：

- `data/maps.json`：4 图补 `carterFees` / `requiresUnlock` / `npcs`；营地 `spawnPoints` 补 3 只 `training_dummy`。
- `data/quests.json`：Q002–Q005 `mapScope` 还原真值、移除 `_m2Temp`；S001 / S002 按 `M ∪ carterLinks(M)` 重算。
- `autoload/data_loader.gd`：新增 §3b 引用校验（`carterLinks` / `carterFees` 目标存在且连通；`npcs.role` ∈ shop/quest/carter；shop NPC `shopId` 必须在 `shops.json`）。
- `autoload/event_bus.gd`：新增 `carter_panel_requested(npc_name)` / `map_traveled(from_id, to_id)`。
- `scripts/world/ground.gd`：`_ready()` 按 `GameState.current_map` 载图（`Game.tscn` 的 `@export map_id` 降级为编辑器预览默认值）。
- `scripts/world/game.gd`：删 `TEST_SPAWNS` / `TEST_ELITES` / `TEST_NPCS`；改 `spawn_from_map(current_map)` + `MapService.current_boss()` + `MapService.current_npcs()`；新增 `_cell_of()` / `_notify_arrival()`；`_try_interact()` 加 `role == "carter"` 分支。
- `scenes/Main.tscn`：挂载 `CarterPanel`（`id="8_carter"`，QuestPanel 之后、DragLayer 之前）。
- `project.godot`：注册 Autoload `MapService`。
- `tests/smoke_test.gd`：新增 `_test_map_travel()`（数据 / 拓扑 / 免费线 / 4 类拒绝分支 / 成功扣费与写 `save_pos` / Boss 点）+ `_test_map_reload()`（T15）；修 3 处旧断言。
- `tests/quest_shot.gd`：`_ready()` 补 `GameState.current_map = "wild_trial"`。

**关键实现口径**：

- **切图两步走**：`travel_to()` 只改状态（不触发重载，为无头可测）；`reload_world()` 单独 `get_tree().call_deferred("reload_current_scene")`，由 `CarterPanel` 调用。
- **`carterFees` 平行字段**：`carterLinks` 结构不变（拓扑语义），费用单独记 → 现有读取点零影响。
- **`save_pos` 一次性消费**：`Game._ready()` 消费后 `has_save_pos=false`。

**验证证据**：

| 项 | 命令 | 结果 |
|---|---|---|
| A0 导入扫描 | `--headless --path . --import` | exit 0 / 0 error |
| A 冒烟 | `--headless --path . res://tests/SmokeTest.tscn` | **exit 0 / 全部通过 ✅** |
| B 启动回归 | `--headless --path . --quit` | exit 0 / **0 SCRIPT ERROR** / `配置校验通过 ✅` |
| 截图 | `res://tests/CarterShot.tscn` | 营地 1 条 / 灰烬之地 2 条（50 金可点、100 金禁用）✅ |
| 存档未污染 | `md5(slot_1.json)` 前后 | 一致（`aa851f96fa16b4ff456332f04743fc14`） |
| **反向验证** | 临时破坏 `ground.gd` 的 `map_id = cur` | 冒烟立即报「地面应加载到当前地图，实际 camp」+「试炼野外尺寸应为 60×60，实际 (40,40)」→ 还原后通过 ✅ |

**M3-8 出口项状态**：T13（暂停无收益）/ T14（死亡关自动战斗）核查确认 **M1-9 已实现**（在 `auto_battle.gd` 侧，非 `player._begin_death()`）—— 批次 1 只补验证，无需改代码；T15 由新增 `_test_map_reload` 覆盖；T08 / T09 已有机制，冒烟用例在批次 2 补全。

**剩余批次（M3-3 / M3-4 已完成，继续按节点推进）**：

- **批次 2「探索与内容」**：M3-3 / M3-4 ✅；待做 M3-6 等级差（只上 `expMult`）/ M3-7 Tab 锁定。
- **批次 3「Boss 收官」**：M3-5 Boss 三阶段 + 墓碑 + 首杀（T12）。


### 批次 2 首节点 M3-3 —— ✅ 已完成（2026-10-12）

**交付**：4×4 区块 / 8 格半径探索，圆形小地图、M 大地图、实际刷新点上的任务 / Boss 标记、本图点击行走、存档 schema 2 的 `exploredMaps`。任务点强制显示只揭示标记，不揭示地形；普通 NPC / Boss 点在探索后显示。怪物死亡后保留刷新点，重生时更新实际位置。

**验收环境**：macOS Apple M1 Max，Godot 4.7.2。测试工程和存档使用独立目录，未覆盖玩家存档。

| 验收 | 结果 |
|---|---|
| 导入与启动 | 导入无脚本错误；启动配置校验通过，退出码 0 |
| 完整 `tests/SmokeTest.tscn` | 全部通过；包括区块边缘、圆半径、重复揭示、异常字段过滤、旧档迁移、存取往返、离图返回保留探索 |
| 移动与生命周期 | 地图点击实际移动、自动战斗接管、面板互斥、后台阻断、手动取消、释放场景后断开迷雾信号均通过 |
| `tests/MapShot.tscn` 图形交互 | 实际 Viewport 鼠标事件、M / Esc 键事件、图外拒绝、点击行走及 Boss 标记检查通过；1280×800 截图核对通过 |
| 原生鼠标 | 点击小地图展开；点击营地目标后从 `(20,20)` 走至 `(30,10)`，探索范围随之增加 |

冒烟内损坏存档用例会主动产生 JSON 解析错误日志，此为预期故障注入；测试结果以全部断言通过为准。本次也修正旧 `_test_world` 未释放场景导致的测试间实体污染。

**范围边界**：地图面板沿用现有规则，阻断玩家命令和自动行为，并非全世界暂停。点击仅支持当前图，复用现有开放场地移动；跨图任务导航、障碍网格寻路仍在后续范围。没有增加实时普通怪追踪。T08 / T09 完整收口继续随 M3-7，T12 随 M3-5；本节点不代表整批 M3 完成。

**下一节点（已更新）**：M3-6 等级差（只上 `expMult`）→ M3-7 Tab 锁定 → 批次 3 Boss 收官。


### 批次 2 节点 M3-4 —— ✅ 已完成（2026-10-12）

交付六词缀配置、出生时随机取 1–2 条、数值及战斗效果、精英金边和名称前缀。保留 `specialAttack: slow` 并接入同一减速处理；寒霜不与其叠乘。召唤物使用普通野狼模板、继承精英等级及普通怪奖励，不建立刷新点。吸血依据实际扣血，保留小数累计，避免低伤害下取整为零导致效果失效。

Godot 4.7.2 / macOS 隔离工程验证：导入无脚本错误，完整 SmokeTest 全部通过；新增断言覆盖攻击/攻速/防御/移速、减速到期实际速度恢复、吸血上限及无敌帧、死亡仅召唤两只、禁止递归召唤、随机池不重复且不改共享模板、错误配置拒绝。冒烟损坏存档注入的 JSON 报错为既有预期日志。

`tests/AffixShot.tscn` 在真实图形渲染下显示六种精英；1280×800 截图确认名称、金边、目标 HUD 可见。截图只是视觉检查，数值效果以回归断言验证。测试使用独立存档，未修改玩家存档。

剩余：M3-6 仅经验等级差 → M3-7 Tab 锁定 → M3-5 Boss 阶段/墓碑/首杀。本节点没有实现 Boss 阶段行为。
