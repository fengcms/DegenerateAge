# 核心完整度审查 · G · 错误处理与边界

> 审查对象：《末法纪元：最后的守护者》（Godot 4.7.2 / GDScript）核心系统的**错误处理与边界**健壮性。
> 基线快照：`773b7d1`。判定准则来源：`AGENT.md` §9（节点、信号与异步生命周期 / 输入、反馈与资源维护 / 数据、数值与存档）。
> 配套：`00-总体方法论.md`（§4 判定标准、§6 报告结构）、`01-审计计划.md`（§2 问题域 G）。
> 本报告为**静态阅读为主**的结论：未运行任何测试命令，凡未经实测的判断均显式标注「（推断）」。

---

## 1. 覆盖范围与未覆盖项

### 1.1 已覆盖（本次回答的 7 个问题）

| 编号 | 问题 | 主要证据文件 |
|---|---|---|
| Q1 | 失败路径是否有明确玩家可见反馈、不静默 | `quest.gd`、`shop.gd`、`upgrade.gd`、`travel_item.gd`、`consumable.gd`、`game.gd`、`save_manager.gd` |
| Q2 | 重复输入/重复信号/异步重入是否造成重复结算 | `quest.gd`、`monster.gd`、`travel_item.gd`、`game_state.gd`、`ground_item.gd` |
| Q3 | `await`/`call_deferred`/定时器恢复后是否重校验 | `map_service.gd`、`game.gd`、`ui_layer.gd`、`monster.gd`、`save_manager.gd` |
| Q4 | 信号是否重复连接/未断开、切图后是否更新旧节点 | `autoload/*.gd`、`scripts/ui/*.gd`、`player.gd`、`auto_battle.gd`、`ground.gd` |
| Q5 | 状态机（死亡/暂停/对话/接管/切图/读档）是否留残留 | `player.gd`、`auto_battle.gd`、`game.gd`、`monster.gd` |
| Q6 | 日志是否含模块/ID/场景/原因、限频、是否泄漏敏感存档 | `save_manager.gd`、`monster.gd`、`ground_item.gd`、`main.gd` |
| Q7 | 共享 Dictionary/Array/Resource 是否被就地污染 | `item_factory.gd`、`inventory.gd`、`equipment.gd`、`monster.gd`、`player.gd`、`ground_item.gd` |

### 1.2 未覆盖项（与方法论 §2 排除项一致，不作为缺陷）

- 美术资源、后续章节的地图/任务/怪物内容、具体数值配置的填充与调平、第二章及以后功能开发。
- 未覆盖项若影响核心机制正确性，本报告只记录事实，不展开修复方案。
- 已核实的既有失败基线（`ArtSampleTest`、`ChapterOneArtTest`、`QualityFrameTest`、`IconIntegrationTest`）不计入本域结论。
- 工作区协作者未提交改动（`docs/测试反馈.md`、`scripts/ui/shop_panel.gd`、`tests/ShopBuyLayoutTest.*`）未纳入判定。

---

## 2. 完整度评估（A–E 分级 + 依据）

**问题域 G 总评：B 基本可用。**

判定依据：本域主路径的失败反馈、复合操作「先验证后提交」与重复结算防护**已闭环且质量较高**（多数子项达 A），但存在两处一般性问题（P2）与若干建议项（P3），且这些边界缺少自动化验证，按方法论 §4.1「主路径可走通、但边界/异常存在未处理项或缺少自动化验证」应判 B。

| 子问题 | 分级 | 依据 |
|---|---|---|
| Q1 失败反馈不静默 | **A** | 各系统统一 `_fail()` 广播 danger toast（`quest.gd`、`travel_item.gd`、`upgrade.gd`、`game_state.gd` 的 `_trade_fail`/`_upgrade_fail`）；存盘失败明确提示。见 §3.1 |
| Q2 重复结算防护 | **A** | 发奖按状态机幂等、购物/升星先验证后提交、怪物死亡与首通结算幂等、地面物登记幂等。见 §3.2 |
| Q3 异步恢复重校验 | **B** | 关键路径（场景装配、加载完成、延迟 toast、UI 延迟应用）均有重校验；个别 `call_deferred` 无显式有效性复核（推断风险低）。见 §3.3 |
| Q4 信号生命周期 | **B** | 无重复连接累积；但普遍依赖引擎「对象释放自动断开」的隐式契约，缺显式 `_exit_tree` 防御（见 P2-2）。见 §3.4 |
| Q5 状态机残留 | **A** | 死亡/暂停/对话/接管/切图/读档均有明确清理与取消路径。见 §3.5 |
| Q6 日志卫生 | **B** | 多数错误日志含模块前缀与原因；存盘自校验失败缺字段级日志（P2-1）、续档日志打印进度数值（P3-1）。见 §3.6 |
| Q7 共享可变对象 | **A** | 实例化入口统一 `duplicate(true)`；模板只读、实例独立。见 §3.7 |

---

## 3. 发现的问题（P0–P3）

> 说明：本次静态审查**未发现 P0 或 P1**——未发现可复现的进度丢失、崩溃、重复结算或静默失败。以下为 P2 与 P3。

### P2-1 存档自校验失败缺少可诊断信息（Q6）

- **位置**：[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L182)（`save_slot` 中 `not _is_valid_save(data)` 分支，L182-184）。
- **现象与复现条件**：当运行态采集出的 `data` 未通过 `_is_valid_save`（`save_manager.gd` L830-936 的详尽字段校验）时，`save_slot` 只广播一条泛化提示 `msg.save_manager.p003` 并 `return false`，**没有 `push_error` 也没有指出具体是哪一字段/哪一资源校验失败**。与之对照，写盘失败分支有 `push_error("[SaveManager] 保存失败：%s" % path)`（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L195)）。
- **影响**：玩家侧能感知「存档失败」，但一旦是新版本引入了非法运行态，开发者无法从日志定位违例字段，排查成本高。不违反「不静默」（有提示），但违反 AGENT.md §9「错误日志写清模块、资源 ID、场景和原因」。
- **建议**：在 L183 分支补 `push_error`，或将 `_is_valid_save` 从返回 bool 扩展为返回 `{ok, field, reason}`，把失败字段写入日志（保持玩家提示不变）。
- **证据等级**：E2。

### P2-2 信号订阅普遍未显式断连，依赖引擎「对象释放自动断开」隐式契约（Q4）

- **位置**（代表性订阅点，均在 `_ready` 直接连接全局 `EventBus`，无对应 `_exit_tree` 断开）：
  - [auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L103)、[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L224)（L224、L230）、[ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd#L98)。
  - UI 层：[hud.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/hud.gd#L50)（L50-67，共 14 条）、[character_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/character_panel.gd#L20)、[skill_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/skill_panel.gd#L11)、[warehouse_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/warehouse_panel.gd#L34)、[quest_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/quest_panel.gd#L42)、[mount_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/mount_panel.gd#L20)、[shop_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/shop_panel.gd#L60)、[upgrade_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/upgrade_panel.gd#L24)、[death_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/death_panel.gd#L12)、[boss_health_bar.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/boss_health_bar.gd#L37)、[item_slot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/item_slot.gd#L142)、[equipment_comparison_tooltip.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/equipment_comparison_tooltip.gd#L7)、[flow_feedback.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/flow_feedback.gd#L16)、[map_canvas.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/map_canvas.gd#L38)、[ui_layer.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/ui_layer.gd#L5)。
  - 对照：唯有 [audio_cues.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/audio_cues.gd#L47) 实现了 `_exit_tree` 显式断连。
- **现象与复现条件**：上述节点在被 `queue_free`/场景卸载释放后，其连接**由 Godot 在对象析构时自动移除**，因此正常流程（切图 = `reload_current_scene()` 整场景重建）不产生重复连接累积，也未发现「切图后向旧节点更新 UI」的实际路径。风险在于：一旦某 UI 节点未来改为**不随整场景重建**地反复创建/销毁（如浮动 tooltip、动态插入的 `ItemSlot`），同一 `EventBus` 信号上会叠加多次连接，导致一次事件触发多次回调。
- **影响**：当前版本无可复现故障（推断）；属结构性隐患，随 UI 复杂度上升而放大。
- **建议**（二选一，保持最小改动）：①明确「UI 一律随整场景重建、生命周期等同 main 场景」的约定并写入注释；②对可能被动态创建/销毁的节点（`equipment_comparison_tooltip`、`item_slot`）补 `_exit_tree` 显式 `disconnect`，并在连接前加 `is_connected` 卫式。
- **证据等级**：代码事实 E2；「当前无可复现故障、仅在动态节点上存在隐患」为 E4（推断）。

### P3-1 续档日志打印玩家进度数值（Q6）

- **位置**：[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L348)（`_emit_resume_toast`，L348-350）。
- **现象**：`print("[SaveManager] 续档完成：Lv%d 金币 %d 地图 %s 背包 %d 格" ...)` 将等级、金币、地图、背包占用写入 stdout。同类还有 [game.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L151) 打印出生点坐标。
- **影响**：AGENT.md §9 要求错误日志「不输出敏感存档内容」。此处为进度摘要而非完整存档转储，且仅在续档时一次，未构成泄漏，但属口径灰区（若正式发行保留 stdout 日志，会在玩家机器上留下进度信息）。
- **建议**：正式构建下收敛为调试级别日志或移除；至少不打印金币/背包等可变进度数值。
- **证据等级**：E2（代码事实）；「是否构成泄漏」为 E4（推断，取决于发行期日志策略）。

### P3-2 部分错误日志缺少资源 ID / 场景上下文（Q6）

- **位置**：[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L195)（`push_error("[SaveManager] 保存失败：%s" % path)` 仅含路径）。
- **对照正面样例**：[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L149)（`"[Monster] 未找到怪物模板 '%s'"` 含 ID）、[loot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/loot.gd#L149)（含 `pool_id` 与套起点）。
- **影响**：多槽/多地图下，仅凭路径不足以快速定位是哪个槽、当前地图或触发场景。
- **建议**：统一在错误日志模板中附带 `slot`、`current_map` 等上下文键值。
- **证据等级**：E2。

### P3-3 跨模块共享可变字典缺少显式所有权约定（Q7）

- **位置**：[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L229)（`skill_cooldowns = GameState.skill_cooldowns`，L229）。
- **现象**：`PlayerCharacter.skill_cooldowns` 与 `GameState.skill_cooldowns` **是同一个字典引用**，施法时在 `player` 侧就地写入（[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L476) 与 L486 `skill_cooldowns[skill_id] = ...`）。设计上冷却为全局运行态、不落档，行为正确；但该共享关系无注释说明，未来若有人对 `player.skill_cooldowns` 做 `duplicate` 或整体替换而不回写 `GameState`，将出现冷却双份不一致。
- **影响**：当前无故障（推断）；属可维护性风险。
- **建议**：在 `player.gd` L229 处补一行注释，声明「该字典为 GameState 冷却运行态的唯一实例，禁止整体替换」，或改由统一入口（`GameState`）读写冷却。
- **证据等级**：E2。

---

## 3.1 Q1 详证：失败路径反馈不静默（结论：A）

失败反馈在各系统统一落到 `EventBus.toast_requested.emit(reason, "danger")`，未见静默吞掉的主路径：

- **任务**：`Quest._fail()`（[quest.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/quest.gd#L545)）统一广播。`deliver()` 逐条校验并给原因：模板缺失、状态未完成、交付人/地图不符、任务物品不足、奖励物配置无效（[quest.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/quest.gd#L247) L247-294）。
- **购物**：`GameState.shop_buy` 逐条校验并 `_trade_fail`：不售此物、背包满、金币不足（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L980) L980-990）；出售同类（L999 起）。
- **升星**：`GameState.upgrade_equipment` 逐条校验并 `_upgrade_fail`：实例漂移、非装备、已满星、价格/成功率非法、如意不足、金币不足（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L701) L701-726）。
- **旅行**：`TravelItem` 回城卷/随机券全部失败条件在扣物前校验并 `_fail`（[travel_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/travel_item.gd#L6) L6-61）；`MapService.travel_to`/`request_walk` 校验链失败均 `_fail`（[map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L334) L334-353、L266-297）。
- **消耗品**：`Consumable.use` 冷却中/满值/非法格均 `_fail`（[consumable.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/consumable.gd#L58) L60-83）；`silent=true`（仅自动战斗内部尝试）刻意不广播，属限频设计而非玩家侧静默。
- **技能/路径**：`cast_skill` 等级/冷却/蓝量/目标无效返回 false（[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L461) L461-485）；路径不可达由 `Game._tick_quest_navigation` 广播 danger（[game.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L73) L92/106/114/128/134）。
- **存档写入失败**：`save_slot` 广播 `msg.save_manager.p006` 并 `push_error`（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L194) L194-197）；读档失败明确返回 message 并提示（L277/L338）。
- **背包满**：`Inventory.add` 返回 false（[inventory.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/inventory.gd#L65)），调用方均先预检或留地并节流提示（`ground_item._try_pickup` 的 `_blocked_cd`，[ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L300)）。

## 3.2 Q2 详证：重复结算防护（结论：A）

- **发奖幂等**：`deliver()` 要求 `state_of(quest_id) == STATE_COMPLETED`（[quest.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/quest.gd#L251)），成功后 `_write(STATE_REWARDED)`（L319），二次调用即被状态拦截。奖励物品**先试入包副本**再提交（`pending_inventory := GameState.inventory.duplicate(true)`，L289-294），杜绝「发了金币却丢装备」的半完成态。
- **首通幂等**：`Monster._settle_first_clear` 以 `GameState.first_clear` 标志短路（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L370) L371）。
- **死亡结算幂等**：`Monster._die` 以 `is_dead` 短路（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L684)）；`_settle_rewards` 受 `suppress_rewards` 与单入口 `_die` 双重约束（L723）。
- **购物/升星先验证后提交**：`shop_buy` 先校验再 `add_gold(-price)`+`add_item`（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L980)）；`upgrade_equipment` 先算 `rune_plan` 与金币校验，再扣费/扣如意（L722-736）。升星失败（roll 未过）仍扣金币与如意属**产品既定规则**（`upgrade.gd` 头部注释 L3），非缺陷。
- **旅行不消耗/不穿墙**：随机券先找到「可通行 + 距原点 ≥4 格 + 同连通区」落点再扣物（[travel_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/travel_item.gd#L59) L59-92，`_random_destination` 最多 128 次尝试）；回城卷先验证再扣 1 张（L25-31）。跨场景事务失败由 `MapService.rollback_travel` 恢复金币/地图/坐标（[map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L391)）。
- **喝药冷却**：`Consumable` 以运行态 `_cd` 拦截重复使用，满值不浪费、恢复按缺口截断（[consumable.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/consumable.gd#L76) L76-89）。
- **地面物认领幂等**：`GroundItem._register_unclaimed` 以 `_claimed or not claim_uid.is_empty()` 短路（[ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L186)）。掉落批次一次性抽取（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L738) L738-741）。

## 3.3 Q3 详证：异步恢复重校验（结论：B）

- **场景装配重校验**：`Game._ready` 在提交出行前复核 `pending_travel` 与地面/玩家/生成器就绪，否则回滚并重载（[game.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L137) L138-143）；`commit_arrival` 复核 `to` 是否等于当前地图，不符则回滚（[map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L372) L376-378）。
- **加载回调 token 防过期**：`_reload_world_now` 用 `_loading_token` 快照，`_finish_loading` 校验 token 一致才收尾（[map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L426) L428-429）。
- **延迟 toast 不引用节点**：`Monster._emit_toast_delayed` 回调只捕获文本、`process_always=false`（暂停冻结），死亡后节点释放不影响（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L835) L835-844）。
- **延迟应用校验节点存活**：`UiLayer._apply_new_text` 以 `instance_from_id` + `is_ancestor_of` 复核（[ui_layer.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/ui_layer.gd#L11) L11-14）。
- **每帧复核目标有效性**：`AutoBattle._physics_process` 复核 player/目标/战利品实例（[auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L145) L147、L246、L421）；`Game._process` 复核 `_pending_npc`/`_pending_exit` 的 `is_instance_valid`+`is_inside_tree`（[game.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L40) L41/51）。
- **待补强（推断）**：`death_panel.gd` 的 `_show_after_death.call_deferred()`（[death_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/death_panel.gd#L12)）与 `main.gd` 的 `initialize_if_current.call_deferred()`（[main.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/main.gd#L12)）未见显式有效性复核；因二者节点随场景存活且时序固定，风险低（E4）。

## 3.4 Q4 详证：信号生命周期（结论：B，见 P2-2）

- 全局 `EventBus` 订阅者分两类：**常驻 Autoload**（`save_manager`、`map_service`、`quest_service`、`audio_cues`、`audio` 等，连接一次终身有效，无释放问题）与**场景内节点**（Player/AutoBattle/Ground/各 UI 面板）。
- 场景内节点均在 `_ready` 连接且在对象释放时由引擎自动移除连接；因切图走 `reload_current_scene()` 整场景重建（[map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L405) L405-424），重建后各自 `_ready` 再连接一次，不会叠加。**未发现「切图后仍向旧节点更新 UI」的可复现路径**。
- 唯一显式实现断连的是 `audio_cues.gd`（[audio_cues.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/audio_cues.gd#L47)）。其余依赖隐式契约——即 P2-2。

## 3.5 Q5 详证：状态机残留（结论：A）

- **死亡**：`PlayerCharacter._begin_death` 幂等（`is_dead` 短路，[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L334) L334-352）：清 buff、停移动/攻击、清 `_pending_skill_id`、`select_target(null)`、关自动战斗、执行掉落惩罚。`AutoBattle._physics_process` 死亡分支优先于手动接管计时并转 OFF（[auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L163) L163-168）。
- **暂停**：自动战斗检测 `get_tree().paused` → RECOVER（[auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L190)）。
- **NPC 对话**：进入时清走位意图并置 `_npc_dialog_suspended`，退出时复位（L175-187）。
- **手动接管**：`begin_manual_override` 立即清目标/战利品/漫游（[auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L210) L210-217）。
- **切图/读档**：`reset_after_travel` 丢弃旧世界目标/走位/攻击意图（含 `_player.clear_travel_intent()`），保留 F/G 开关（[auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L124)）；`Game._ready` 装配后调用（[game.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L156) L156-159）。
- **面板接管**：`panel_open` 时清普攻/移动/待发技能（[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L284) L284-287）；`Game._process` 在 `panel_open` 或死亡时清 `_pending_npc`/`_pending_exit`（[game.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L36) L36-39）。

## 3.6 Q6 详证：日志卫生（结论：B）

- **正面**：错误日志普遍带模块前缀（`[SaveManager]`/`[Main]`/`[Monster]`/`[Loot]`/`[AutoBattle]`/`[Game]`）；`Loot._pick_equip_template` 含 `pool_id`+套起点（[loot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/loot.gd#L149)）；`Monster._load_template` 含怪物 ID（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L149)）。
- **限频**：地面「背包已满」提示节流 `BLOCK_TOAST_CD=1.5s`（[ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L27)）；自动战斗药水失败 `silent=true`；掉落聚合为单条提示。
- **问题**：见 P2-1（自校验无字段日志）、P3-1（续档打印进度数值）、P3-2（部分日志缺 ID/场景）。存档落档本身（`_collect`，[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L123)）含完整 player/inventory，但**未打印**，符合「不输出敏感存档内容」。

## 3.7 Q7 详证：共享可变对象（结论：A）

- **实例化入口统一深拷贝**：`ItemFactory.make_equip_roll` 的 `rawBaseAttrs` 用 `duplicate(true)`（[item_factory.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_factory.gd#L96)）；`Inventory.add` 对入包物品 `duplicate(true)`（[inventory.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/inventory.gd#L65)）；`Equipment.equip_from_inventory` 直接交换实例字典、不复制共享模板（[equipment.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L156)）。
- **模板只读**：`Monster._load_template` 只读取 `DataLoader` 返回的模板；`_roll_affixes` 对每个词缀 `entry.duplicate(true)` 后再叠加（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L169) L174-188），不污染共享词缀表。
- **掉落实例独立**：`Loot.roll` 每件返回新字典（[loot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/loot.gd#L26)）；`Monster._spawn_drop` 把该独立实例交给 `GroundItem.item`（[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L861)），入包时再经 `Inventory.add` 复制。
- **合理就地修改**：`TravelItem` 对**背包中的实际实例**就地减 `count`（[travel_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/travel_item.gd#L28) L28、L63）属预期；`Upgrade.rune_plan` 生成扣除计划前不修改背包（[upgrade.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/upgrade.gd#L24)）。
- **唯一共享引用**：见 P3-3（`player.skill_cooldowns` 与 `GameState.skill_cooldowns` 同引用）。

---

## 4. 证据与复核方法

### 4.1 方法

- **静态阅读**（E2 为主）：逐文件通读上表脚本，交叉核对 `AGENT.md` §9 条文。
- **交叉对照**（E3）：对照 `00-总体方法论.md` §4 判定标准、`01-审计计划.md` §2 问题域 G 细则。
- **未执行**（按任务要求）：不运行 `tools/run_isolated_tests.py`，故本报告无 E1 运行证据；凡涉「是否可复现」的判断均标注 E4（推断）。

### 4.2 复核命令

以下命令仅用于复核文件与行号（只读，不修改不提交）：

```bash
# 存档校验失败分支
sed -n '182,197p' autoload/save_manager.gd
# 续档日志
sed -n '347,355p' autoload/save_manager.gd
# 事件总线全局订阅（UI/Autoload）
rg -n "EventBus\.[a-z_]+\.connect" autoload scripts
# 唯一的显式断连
rg -n "func _exit_tree" autoload scripts
# 发奖幂等与先试入包
sed -n '247,320p' scripts/systems/quest.gd
# 升星先验证后提交
sed -n '701,753p' autoload/game_state.gd
# 随机券不穿墙
sed -n '44,96p' scripts/systems/travel_item.gd
# 死亡/首通幂等
sed -n '684,717p;370,379p' scripts/entities/monster.gd
# 切图重载与回滚
sed -n '355,432p' autoload/map_service.gd
```

### 4.3 相关既有测试（本域覆盖参考，未运行）

| 测试文件 | 覆盖点 |
|---|---|
| [review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd) | 背包批量入包原子性、不修改调用方物品、穿脱原子性、存档校验/备份恢复/坏档不改进度 |
| [random_ticket_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/random_ticket_test.gd) | 随机券无世界/死亡不消耗、成功才消耗、落点可通行/同连通区 |
| [death_drop_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/death_drop_test.gd) | 死亡惩罚只掉一件、重复死亡不多掉（幂等） |
| [death_choice_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/death_choice_test.gd) | 死亡暂停/复活/免费回营地/自动战斗关闭 |
| [input_feedback_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/input_feedback_test.gd) | 输入路由、面板阻断、手动接管计时、目标释放清理 |
| [flow_feedback_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/flow_feedback_test.gd) | 加载/配置异常/首屏引导的可见反馈 |

> 说明：这些测试已给出 E1 级回归能力，但**本域中若干边界（信号未断连累积、存档自校验失败日志、续档日志脱敏）尚无对应断言**，属 Q6/Q4 缺自动化验证，是 G 域判 B 的直接依据之一。

---

## 5. 落地优化方案

按代价从低到高、互不耦合，可分派执行：

1. **补存档自校验失败日志（P2-1，最小改动）**
   - `save_manager.gd` L182-184：在 `return false` 前加 `push_error("[SaveManager] 存档数据自校验失败：槽 %d 地图 %s" % [slot, GameState.current_map])`。
   - 进阶（可选）：将 `_is_valid_save` 改为返回 `{ok, field, reason}`，仅日志侧消费，玩家提示不变。影响面小、可单独提交。

2. **明确信号生命周期契约（P2-2）**
   - 方案 A（零代码）：在 `EventBus` 顶部注释中声明「UI 一律随 main 场景重建；如引入非场景生命周期的动态节点，须在 `_exit_tree` 显式断开」。
   - 方案 B（防御）：为 `equipment_comparison_tooltip.gd`、`item_slot.gd` 等可能被动态创建/销毁的节点补 `_exit_tree` 断连 + 连接前 `is_connected` 卫式。改动局部、无行为变化。

3. **日志脱敏与上下文（P3-1、P3-2）**
   - 将 `_emit_resume_toast` 的进度摘要降级为调试开关控制或移除；为 `push_error` 统一补充 `slot`/`current_map` 上下文键值。

4. **共享可变对象所有权注释（P3-3）**
   - `player.gd` L229 补注释，声明 `skill_cooldowns` 为 GameState 冷却运行态的唯一实例、禁止整体替换。

5. **补齐自动化断言（跨域协作）**
   - 建议在既有 `ReviewRegressionTest` 追加：① 存档自校验失败路径的日志/返回值断言；② 反复创建销毁订阅节点后不出现重复回调的断言。归入 H 域测试覆盖工作。

> 全部改造均属「完善性」改动，不涉及玩法与数值变更；按 AGENT.md §10，每项独立提交并附前后对比。

---

## 6. 与既有文档的差异说明

- **与 `00-总体方法论.md` / `01-审计计划.md` 的一致性**：本报告严格按方法论 §6 六段结构与 §4 分级判定撰写；证据等级遵循 E1–E4 规范，未实测项一律标注「推断」。范围与排除项与 §2 完全一致。
- **与 `AGENT.md` §9 的关系**：本域判定以 §9 为唯一准则来源。发现的问题是 §9 三条子项（错误日志含原因、防信号重复连接、共享对象可修改性）的**未完全覆盖处**，而非违反。
- **与第一轮审阅的关系**：本次静态审查**未发现 P0/P1**，即未复现第一轮所述「静默失败/重复结算」类问题的遗留；发现项均为 P2/P3 级别的完善建议，与第一轮的修复结论无冲突。
- **与相邻问题域的边界**：存档迁移与备份恢复的**正确性**归 C 域；本域的存档相关结论仅限「失败反馈与日志卫生」。测试可信度与覆盖率归 H 域。
- **本报告的定位限制**：静态为主、未运行测试，Q3/Q4 中标注 E4 的项（延迟回调风险、动态节点重复连接隐患）需在后续实测中确认，方可升级为实测结论。

---

### 交付物

| 文件 | 内容 | 核心发现 |
|---|---|---|
| `docs/审阅报告/核心完整度审查/G-错误处理与边界.md` | 本报告 | 本域总评 **B**；无 P0/P1；2 项 P2（存档自校验缺字段日志、信号断连依赖隐式契约）+ 3 项 P3；失败反馈、重复结算防护、共享对象隔离三个子项达 A。 |
