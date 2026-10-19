extends Node
## EventBus — 全局事件总线（单例 / Autoload）。
##
## 目的：解耦系统间通信。系统之间通过 signal 订阅 / 发布通信，
## 不互相持有强引用，便于 AI 与人均可独立修改各系统。
## 枚举的 signal 为脚手架预置，阶段开发时按需补充（保持命名集中在此处）。
##
## 【订阅生命周期约定（G-P2-2）】订阅方在 `_ready` 直接 `connect`，**不逐个实现 `_exit_tree` 断开**：
## 引擎在节点释放时会自动断开其作为 Callable 目标的所有连接（对象释放即失效）。
## 世界侧节点的生命周期与 main 场景一致（整场景重建时一并释放），故无需显式 disconnect；
## 若将来出现「生命周期短于场景」的动态节点（如临时 tooltip / 拖拽槽位），
## 需在该节点内补 `_exit_tree` 显式 `disconnect`，并在连接前用 `is_connected` 卫式。
## 作为范式参照：`autoload/audio_cues.gd` 已实现显式断连。

# ---- 战斗 ----
signal damage_dealt(target: Node, amount: int, is_critical: bool)
signal monster_died(monster_id: String)
signal player_died()

# ---- 成长 ----
signal player_leveled(new_level: int)

# ---- 玩家数值（HUD 实时刷新，M1-3）----
signal player_hp_changed(current: int, maximum: int)
signal player_mp_changed(current: int, maximum: int)
signal player_sitting_changed(sitting: bool)
signal player_xp_changed(current: int, maximum: int)
signal target_changed(target: Node)
signal boss_first_clear(monster_id: String)
## Boss 顶部血条（M6-0a / 创意 07 §4）：Monster 在受击 / 阶段变更 / 进入仇恨 / 死亡时广播。
## `hp <= 0` 表示死亡，HUD 据此触发淡出。
## M10-3b（P-7）：首参 `boss_id` = `Monster.get_instance_id()`，多目标血条据此区分实例
## （`monster_id` 同种可重复、`display_name` 可重名，都不能当身份）。
signal boss_hp_changed(boss_id: int, boss_name: String, hp: int, max_hp: int, phase: int)

# ---- 物品 / 经济 ----
signal item_picked(item_id: String)
signal gold_changed(amount: int)
signal inventory_changed()
signal inventory_organized()
signal inventory_expanded()
## 未领取战利品因超上限被系统丢弃（M6-0c 上限）：携带 uid，供在场地面物自行销毁。
signal unclaimed_loot_evicted(uid: String)
signal equipment_changed()
## 装备实例收藏状态变化；存档需及时记录，且不把它误当穿戴属性变化。
signal equipment_favorite_changed()
signal equipment_confirmation_requested(preview: Dictionary)
signal equipment_confirmation_closed()
signal upgrade_completed()

# ---- NPC / 交易（M1-8）----
signal shop_open_requested(shop_id: String)
signal shop_close_requested()
signal trade_mode_changed(active: bool)
signal trade_done(kind: String, item_id: String, price: int)

# ---- 自动战斗 / 自动拾取（M1-9，3.14 / 4.6）----
signal auto_state_changed(battle: bool, pickup: bool)
signal auto_phase_changed(phase: String)

# ---- 任务（M2）----
signal quest_accepted(quest_id: String)
signal quest_progressed(quest_id: String, current: int, required: int)
signal quest_completed(quest_id: String)
signal quest_rewarded(quest_id: String)
## 任一任务状态落账后通知世界表现层；放弃也会触发，旧细分信号继续供业务使用。
signal quest_state_changed()
signal quest_panel_requested(npc_name: String)

# ---- 地图 / 车夫（M3）----
## M10-7：第二参区分两种语义 —— `false` 当地车夫（只列同集群 `destinations()`），
## `true` 随身车夫（七分组全 36 图 + `travel_anywhere`）。同一个面板节点两种模式。
signal carter_panel_requested(npc_name: String, portable: bool)
## M10-5：追猎令牌面板请求（与 `carter_panel_requested` 同构 —— 只传标题，
## 面板自己调 `BossToken.rows()` 取数据）。
signal boss_token_panel_requested(title: String)
signal map_traveled(from_id: String, to_id: String)

# ---- 铁匠 / 升星（M4）----
signal blacksmith_panel_requested(npc_name: String, greeting: String)
signal upgrade_panel_requested()
## M10-8：铁匠服务菜单第二项（装备重铸）请求。
signal reforge_panel_requested()
## 铁匠三种合成服务共用窗口，mode 为 EquipmentFusion 中的稳定服务 ID。
signal equipment_fusion_panel_requested(mode: String)
## 合成工作台与背包的并排会话开关；预选材料不进入背包以外的容器。
signal fusion_mode_changed(active: bool)
signal equipment_fusion_close_requested()

# ---- 仓库（M4-3）----
signal warehouse_panel_requested(npc_name: String)
signal warehouse_changed()

# ---- 坐骑（M4-4）----
signal mount_changed()
signal mount_panel_requested()

# ---- 系统 ----
signal toast_requested(text: String, kind: String)
signal panel_opened(panel_id: String)
## 统一关闭全部关闭式面板（F-P3-2）：`GameState.close_all_panels` 广播此事件，
## 各面板在 `_ready` 订阅后调 `set_open(false)`，使面板中间态（货郎出售托盘、快捷栏拖放
## 模式、菜单流程态等）与登记清空成对回退，不再依赖「调用点必然伴随场景重载」。
signal panels_close_requested()
signal map_changed(map_id: String)
signal fog_changed(map_id: String)
signal map_panel_requested()
signal data_loaded()
signal loading_changed(active: bool, message: String)
signal settings_changed()
signal hotbar_changed()
