extends Node
## EventBus — 全局事件总线（单例 / Autoload）。
##
## 目的：解耦系统间通信。系统之间通过 signal 订阅 / 发布通信，
## 不互相持有强引用，便于 AI 与人均可独立修改各系统。
## 枚举的 signal 为脚手架预置，阶段开发时按需补充（保持命名集中在此处）。

# ---- 战斗 ----
signal damage_dealt(target: Node, amount: int, is_critical: bool)
signal monster_died(monster_id: String)
signal player_died()

# ---- 成长 ----
signal xp_gained(amount: int)
signal player_leveled(new_level: int)

# ---- 玩家数值（HUD 实时刷新，M1-3）----
signal player_hp_changed(current: int, maximum: int)
signal player_mp_changed(current: int, maximum: int)
signal player_sitting_changed(sitting: bool)
signal player_xp_changed(current: int, maximum: int)
signal target_changed(target: Node)
signal boss_first_clear(monster_id: String)

# ---- 物品 / 经济 ----
signal item_dropped(item_id: String)
signal item_picked(item_id: String)
signal loot_spawned(item: Dictionary)
signal gold_changed(amount: int)
signal inventory_changed()
signal inventory_organized()
signal equipment_changed()
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
signal quest_panel_requested(npc_name: String)

# ---- 地图 / 车夫（M3）----
signal carter_panel_requested(npc_name: String)
signal map_traveled(from_id: String, to_id: String)

# ---- 铁匠 / 升星（M4）----
signal blacksmith_panel_requested(npc_name: String, greeting: String)
signal upgrade_panel_requested()

# ---- 仓库（M4-3）----
signal warehouse_panel_requested(npc_name: String)
signal warehouse_changed()

# ---- 坐骑（M4-4）----
signal mount_changed()
signal mount_panel_requested()

# ---- 系统 ----
signal toast_requested(text: String, kind: String)
signal panel_opened(panel_id: String)
signal map_changed(map_id: String)
signal fog_changed(map_id: String)
signal map_panel_requested()
signal data_loaded()
signal settings_changed()
signal hotbar_changed()
