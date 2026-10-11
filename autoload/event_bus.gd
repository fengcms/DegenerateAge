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
signal player_xp_changed(current: int, maximum: int)
signal target_changed(target: Node)

# ---- 物品 / 经济 ----
signal item_dropped(item_id: String)
signal item_picked(item_id: String)
signal gold_changed(amount: int)
signal inventory_changed()

# ---- 任务 ----
signal quest_accepted(quest_id: String)
signal quest_progressed(quest_id: String, current: int, required: int)
signal quest_completed(quest_id: String)

# ---- 系统 ----
signal toast_requested(text: String, kind: String)
signal map_changed(map_id: String)
signal data_loaded()
signal settings_changed()
