extends Node
## GameState — 全局运行时状态（单例 / Autoload）。
##
## 持有角色、经济、进度、设置的运行时数据；启动时赋予初始参数
## （数值来源：docs/产品文档/04 角色成长系统 4.4 初始值）。
## 不持久化运行时节点对象——存档由 SaveManager 负责序列化这里的数据。

const SCHEMA_VERSION := 6

## 背包格数（5.8：40 格）与金币上限（6.2：999,999,999）。
const INVENTORY_SIZE := 40
const GOLD_CAP := 999999999

# 4.3 最大生命 / 法力派生常量（初始参数，试玩校准）
const BASE_HP := 50.0
const HP_PER_LV := 8.0
const HP_PER_ATK := 2.0
const HP_PER_DEF := 4.0
const BASE_MP := 30.0
const MP_PER_LV := 5.0

var player: Dictionary = {}
var gold: int = 0
var current_map: String = "camp"
var visited_maps: Array[String] = ["camp"]
var inventory: Array = []           # 背包物品实例（40 格，见 Inventory / 5.8）
var inventory_expansions: int = 0
var warehouse: Array = []           # 仓库物品，空位为 null（6.8）
var warehouse_expansions: int = 0
var owned_mounts: Array[String] = [] # 独立坐骑收藏，不占背包格（M4-4）
var active_mount: String = ""
var equipment: Dictionary = {}      # 已穿戴装备（槽 id → 实例，14 槽，见 Equipment / 5.1）
## 降品质提醒为会话状态：跨图保留，新游戏/成功读档清零；不进入存档或 settings。
var skip_equipment_downgrade_prompt := false
var pending_equipment_change: Dictionary = {}
var _equipment_request_sequence := 0
var panel_open: bool = false        # 是否有关闭式面板打开中（面板开启时屏蔽角色操控）
var _open_panels: Dictionary = {}   # 已打开面板 id 集合（多面板互斥，见 set_panel_open）
var quest_states: Dictionary = {}   # quest_id -> {"state": String, "progress": int}（M2 起；见 scripts/systems/quest.gd）
var quest_items: Dictionary = {}    # 第二章确定来源的任务物品；独立任务袋，不占背包格
var first_clear: Dictionary = {}    # boss_id -> bool（首通标记）
var unlocks: Dictionary = {}        # 解锁标记，如 {"chapter2": true}（M2：Q005 奖励 → 第二章入口）
var explored_maps: Dictionary = {}  # map_id -> {区块编号字符串: true}；存档为紧凑数组（M3-3）
var settings: Dictionary = {}
var hotbar: Array = []             # 12 格模板引用；背包整理、切图后保持绑定（M4-8）
## 主动技能冷却是本次会话运行态：跨图保留，读档/新游戏清零，不写存档。
var skill_cooldowns: Dictionary = {}
## 自身增益剩余秒数；与技能冷却同为跨图但不落档的运行态。
var active_buffs: Dictionary = {}
## 本次运行的菜单流程状态；不入档。切图与读档重建 Main 时保留 world。
var menu_mode: String = "menu"
## 自动战斗 / 自动拾取开关（M1-9，3.14）。**运行态开关，不写存档**
## （10.3：重启后自动战斗默认关闭）。决策机见 scripts/systems/auto_battle.gd。
var auto_battle_on: bool = false
var auto_pickup_on: bool = false

# ---- 世界时钟与怪物点刷新状态（M4-10：墓碑跨图保持）----
## 依据：产品文档 07 §7.9（怪物点刷新）。根因见工程文档 14 §1.1 ——
## 刷新倒计时原本存在场景运行态（`MonsterSpawner._points[i].timer`），切图重载场景即清零；
## 提升到本 Autoload（跨场景存活）后，跨图 / 挂机时间照常推进。

## 世界时钟（秒）：与 Consumable 冷却共用 `_process` 心跳，因此
## 面板打开照常推进、Esc 暂停菜单时**冻结**（get_tree().paused 生效）。
## **随存档落档**（`worldTime`，工程文档 14 §3.1 ④）：读档后从该值续算，
## 离线真实时间不计入（游戏内时钟语义，可预测）。
var world_time: float = 0.0

## 怪物点刷新状态：key = `"<map_id>#<monster_id>#<同种序号>"`（**稳定 key**，
## 不依赖数组下标 → 地图数据增减点不会错位，见 14 §5 R-a）
##   → { "readyAt": float（到点时的 world_time）, "pos": Vector2（死亡处） }
## 只记录**未刷新完成**的点；到点即清除（表不会无限增长，14 §5 R-d）。
var spawn_respawn: Dictionary = {}

## 未领取战利品（M6-0c / 创意 07 §11）：精英 / Boss 入包失败的掉落物，跨图 / 跨档保留，
## 直到领取或玩家主动丢弃（普通怪与玩家自行丢弃物仍按 60s 淡出旧规则）。
## key = map_id；value = Array[ { "uid": String, "batchId": String, "item": Dictionary, "pos": Vector2 } ]
## ⚠ 与 spawn_respawn 同构：encode / apply 负责 JSON 往返（Vector2 ↔ [x,y]）。
##   读档由 SaveManager.apply_to_game_state 调用，须在 `Game._ready` 重建地面物之前完成。
var unclaimed_loot: Dictionary = {}
var _unclaimed_seq: int = 0

## 读档待应用的玩家世界坐标（M1-10，10.3「当前地图与坐标」）。
## 写入方：SaveManager.apply_to_game_state；消费方：Game._ready（消费一次后 clear_save_pos）。
## has_save_pos = false 时按地图中心出生（新游戏 / 无坐标字段的旧档）。
var save_pos: Vector2 = Vector2.ZERO
var has_save_pos: bool = false

## 清除待应用的读档坐标（Game._ready 用完后调用，避免影响后续重载）。
func clear_save_pos() -> void:
	save_pos = Vector2.ZERO
	has_save_pos = false

## 清空面板登记（读档 / 重载世界前调用，避免旧面板状态残留）。
func close_all_panels() -> void:
	cancel_equipment_change()
	_open_panels = {}
	panel_open = false

func _ready() -> void:
	reset_to_defaults()

## 药水冷却心跳（M2.5）。挂在本 Autoload（常驻节点）而非 UI 节点上——
## 否则面板销毁会导致冷却永久停摆（见工程文档 12 §5 R-h）。
func _process(delta: float) -> void:
	Consumable.tick(delta)
	for skill_id in skill_cooldowns.keys():
		skill_cooldowns[skill_id] = maxf(0.0, float(skill_cooldowns[skill_id]) - delta)
	tick_buffs(delta)
	world_time += delta    # M4-10：世界时钟（面板打开照常走、暂停时冻结；见字段注释）

func tick_buffs(delta: float) -> void:
	for skill_id in active_buffs.keys():
		var remaining := maxf(0.0, float(active_buffs[skill_id]) - delta)
		if remaining <= 0.0:
			active_buffs.erase(skill_id)
			EventBus.buff_changed.emit(String(skill_id), 0.0)
		else:
			active_buffs[skill_id] = remaining

func buff_remaining(skill_id: String) -> float:
	return float(active_buffs.get(skill_id, 0.0))

func buff_effect_total(effect: String) -> float:
	var total := 0.0
	for skill_id in active_buffs.keys():
		var skill = DataLoader.get_entry("skills", String(skill_id))
		if skill is Dictionary:
			total += float((skill.get("effects", {}) as Dictionary).get(effect, 0.0))
	return total

func start_buff(skill_id: String) -> bool:
	var skill = DataLoader.get_entry("skills", skill_id)
	if not skill is Dictionary or String(skill.get("kind", "")) != "buff" or buff_remaining(skill_id) > 0.0:
		return false
	var duration := float(skill.get("duration", 0.0))
	if duration <= 0.0:
		return false
	active_buffs[skill_id] = duration
	EventBus.buff_changed.emit(skill_id, duration)
	return true

func clear_buffs() -> void:
	for skill_id in active_buffs.keys():
		EventBus.buff_changed.emit(String(skill_id), 0.0)
	active_buffs.clear()

## 基础属性模板（数值来源：docs/产品文档/04 角色成长系统 4.4 初始值）。
## 独立成函数：reset_to_defaults 与**读档字段补全**（SaveManager._migrate_player）共用，
## 保证旧档缺字段时补出来的默认值与新游戏完全一致（M1-10）。
func default_player() -> Dictionary:
	return {
		"name": "守护者",
		"level": 1,
		"xp": 0,
		"hp": 102,          # 派生：见 4.3，L1（攻12/防5）=> 102
		"mp": 35,           # 派生：BASE_MP30 + L1×5 => 35
		"attack": 12,
		"defense": 5,
		"criticalChance": 0.05,
		"criticalMultiplier": 1.5,
		"attackInterval": 0.8,
		"movementSpeed": 4.0,
		"dodge": 0,
		"block": 0,         # 首版不做（保留字段）
		"cdr": 0.0,
	}

## 设置模板（10.3：用户设置随存档保存；3.14 自动战斗默认关）。
func default_settings() -> Dictionary:
	return {
		"autoBattleDefault": false,   # 10.3：重启后自动战斗默认关闭
		"autoPickupDefault": false,
		"potionThreshold": 0.35,      # 3.14 喝药血量阈值
		"searchRadius": 12,           # 旧档兼容字段；搜怪改用当前可视区域
		"allowBoss": false,           # 3.14 自动战斗是否允许 Boss
		"dropFlyAnim": true,          # 10：拾取飞行动画（关 = 入包后立即消失）
		"masterVolume": 1.0,
		"sfxVolume": 1.0,
		"uiScale": 1.0,
		"musicVolume": 1.0,
		"screenShake": true,
		"strongFlash": true,
		"textScale": 1.0,
		"mapScale": 1.0,              # 地图显示大小＝相机 zoom（0.8–2.0）
		"displayScaleMode": "auto",   # M5-9c（09-A）：显示适配 自动/手动（auto = 不额外补偿，系统已完成密度换算）
		"displayScale": 1.0,          # M5-9c：仅手动模式生效的统一系数（0.75–1.5），三轴各乘这一次
		"fullscreen": false,
		"resolution": "auto",
		"qualityFilter": "all",
		"tutorialSeen": false,
		"firstBattleHintSeen": false,
		"colorblindMode": "off",
		"lowGearLevelLimit": 5,
		"lowGearMaxQuality": "common",
		"keyBindings": {},
	}

## 重置为初始状态（新建角色 / 初始化时调用）。
func reset_to_defaults() -> void:
	reset_equipment_prompt_session()
	player = default_player()
	gold = 0
	current_map = "camp"
	visited_maps = ["camp"]
	inventory = Inventory.create(INVENTORY_SIZE)
	inventory_expansions = 0
	warehouse_expansions = 0
	warehouse = Warehouse.create()
	owned_mounts = []
	active_mount = ""
	equipment = Equipment.create()
	panel_open = false
	_open_panels = {}
	quest_states = {}
	quest_items = {}
	first_clear = {}
	unlocks = {}
	explored_maps = {}
	auto_battle_on = false          # 10.3：重启后自动战斗默认关闭
	auto_pickup_on = false
	Consumable.reset()              # M2.5：药水冷却为运行态，重开 / 读档清零（不落档）
	skill_cooldowns = {}
	clear_buffs()
	world_time = 0.0                # M4-10：世界时钟与刷新状态重置（新游戏 / 初始化）
	spawn_respawn = {}
	unclaimed_loot = {}             # M6-0c：未领取战利品（新游戏 / 初始化清空）
	clear_save_pos()
	settings = SettingsRuntime.with_display_preferences(default_settings())
	hotbar = HotbarConfig.defaults()
	SettingsRuntime.apply_all()

func mark_visited(map_id: String) -> void:
	if not visited_maps.has(map_id):
		visited_maps.append(map_id)

func is_visited(map_id: String) -> bool:
	return visited_maps.has(map_id)

func set_hotbar_entry(index: int, entry: Variant) -> bool:
	if index < 0 or index >= HotbarConfig.SIZE or not HotbarConfig.valid_entry(entry):
		return false
	if hotbar[index] == entry:
		return true
	hotbar[index] = entry.duplicate(true) if entry is Dictionary else null
	EventBus.hotbar_changed.emit()
	return true

func swap_hotbar_entries(from_index: int, to_index: int) -> bool:
	if from_index < 0 or from_index >= HotbarConfig.SIZE or to_index < 0 or to_index >= HotbarConfig.SIZE:
		return false
	if from_index == to_index:
		return true
	var old = hotbar[from_index]
	hotbar[from_index] = hotbar[to_index]
	hotbar[to_index] = old
	EventBus.hotbar_changed.emit()
	return true

## 经验升级所需（4.4 公式：round(100 × L^1.6)）。
func xp_to_next(level: int) -> int:
	return int(round(100.0 * pow(float(level), 1.6)))

## 装备提供的属性加成汇总（14 槽，见 Equipment / 5.1）。
func equip_bonus() -> Dictionary:
	return Equipment.bonus(equipment)

## 总攻击力 = 基础攻击（player.attack，升级成长 4.4）+ 装备固定加成（5.2）。
## 装备**不改基础值**（5.1）：基础值与装备加成始终分离保存。
func total_attack() -> int:
	return int(player.attack) + int(round(float(equip_bonus().get("atk", 0.0))))

## 总防御力 = 基础防御 + 装备固定加成。
func total_defense() -> int:
	return int(player.defense) + int(round(float(equip_bonus().get("def", 0.0))))

## 派生的最大生命（4.3 公式；攻 / 防取**总属性**，装备 hp / hpPercent 进入固定 / 百分比项）。
func max_hp() -> int:
	var base := BASE_HP + float(player.level) * HP_PER_LV \
		+ float(total_attack()) * HP_PER_ATK + float(total_defense()) * HP_PER_DEF
	var b := equip_bonus()
	var pct := float(player.get("hpPercent", 0.0)) + float(b.get("hpPercent", 0.0))
	var flat := float(player.get("hpFlat", 0.0)) + float(b.get("hp", 0.0))
	return int(round(base * (1.0 + pct) + flat))

## 派生的最大法力（4.3 公式；装备 mp / mpPercent 进入固定 / 百分比项）。
func max_mp() -> int:
	var b := equip_bonus()
	var base := BASE_MP + float(player.level) * MP_PER_LV
	var pct := float(player.get("mpPercent", 0.0)) + float(b.get("mpPercent", 0.0))
	var flat := float(player.get("mpFlat", 0.0)) + float(b.get("mp", 0.0))
	return int(round(base * (1.0 + pct) + flat))

# ---- 数值变更（统一走事件广播，HUD 订阅刷新）----

## 受击扣血；返回是否死亡。HP 不低于 0。
func damage_player(amount: int) -> bool:
	if amount <= 0:
		return player.hp <= 0
	player.hp = max(0, int(player.hp) - amount)
	EventBus.player_hp_changed.emit(int(player.hp), max_hp())
	if player.hp <= 0:
		EventBus.player_died.emit()
		return true
	return false

## 治疗，不超过上限。
func heal_player(amount: int) -> void:
	player.hp = min(max_hp(), int(player.hp) + amount)
	EventBus.player_hp_changed.emit(int(player.hp), max_hp())

## 恢复法力，不超过上限（M2.5 蓝药；与 heal_player 对称）。
func restore_mp(amount: int) -> void:
	if amount <= 0:
		return
	player.mp = min(max_mp(), int(player.mp) + amount)
	EventBus.player_mp_changed.emit(int(player.mp), max_mp())

## 消耗法力；不足则返回 false（不扣）。供技能（M3）与测试使用。
func spend_mp(amount: int) -> bool:
	if amount <= 0:
		return true
	if int(player.mp) < amount:
		return false
	player.mp = int(player.mp) - amount
	EventBus.player_mp_changed.emit(int(player.mp), max_mp())
	return true

## 金币增减（下限 0，上限 GOLD_CAP，见 6.2）。返回实际入账额。
func add_gold(amount: int) -> int:
	var before := gold
	gold = clampi(gold + amount, 0, GOLD_CAP)
	var delta := gold - before
	EventBus.gold_changed.emit(gold)
	return delta

## 金币是否已达上限（6.2：达上限后不再拾取金币并提示）。
func gold_is_capped() -> bool:
	return gold >= GOLD_CAP

# ---- 背包（5.8；存储层见 scripts/systems/inventory.gd）----

## 物品入包。成功返回 true 并广播；背包满返回 false（不静默）。
func add_item(item: Dictionary) -> bool:
	var ok := Inventory.add(inventory, item)
	if ok:
		EventBus.inventory_changed.emit()
	return ok

## 移除指定格物品（丢弃 / 出售 / 穿戴时使用）。
func remove_item_at(index: int) -> Dictionary:
	var it := Inventory.remove_at(inventory, index)
	if not it.is_empty():
		EventBus.inventory_changed.emit()
	return it

## 背包已占用格数。
func inventory_used() -> int:
	return Inventory.used_slots(inventory)

# ---- 坐骑（M4-4）----

func collect_mount(mount_id: String) -> bool:
	if not DataLoader.get_entry("mounts", mount_id) is Dictionary or owned_mounts.has(mount_id):
		return false
	owned_mounts.append(mount_id)
	EventBus.mount_changed.emit()
	return true

func mount_speed_multiplier() -> float:
	if active_mount.is_empty():
		return 1.0
	var mount = DataLoader.get_entry("mounts", active_mount)
	if not mount is Dictionary or not owned_mounts.has(active_mount) or int(player.get("level", 1)) < int(mount.get("levelReq", 20)):
		return 1.0
	return 1.0 + maxf(0.0, float(mount.get("speedBonus", 0.0)))

func ride_mount(mount_id: String) -> Dictionary:
	var mount = DataLoader.get_entry("mounts", mount_id)
	if not mount is Dictionary or not owned_mounts.has(mount_id):
		return {"ok": false, "reason": Localization.tr_key("msg.game_state.p001")}
	var required := int(mount.get("levelReq", 20))
	if int(player.get("level", 1)) < required:
		return {"ok": false, "reason": Localization.tr_key("msg.game_state.p002") % required}
	active_mount = mount_id
	EventBus.mount_changed.emit()
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p003") % String(mount.get("name", mount_id)), "pickup")
	return {"ok": true}

func dismount() -> void:
	if active_mount.is_empty():
		return
	active_mount = ""
	EventBus.mount_changed.emit()
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p004"), "info")

func organize_inventory() -> bool:
	var changed := Inventory.organize(inventory)
	if changed:
		EventBus.inventory_changed.emit()
		EventBus.inventory_organized.emit()
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p005"), "info")
	return changed

func move_inventory_item(source: int, target: int, token: String) -> bool:
	if source < 0 or source >= inventory.size() or not inventory[source] is Dictionary \
			or not Warehouse.token_matches(inventory[source], token):
		return false
	if not Inventory.move_or_swap(inventory, source, target):
		return false
	EventBus.inventory_changed.emit()
	return true

func set_low_gear_filter(level_limit: int, max_quality: String) -> bool:
	if level_limit < 1 or level_limit > 100 or not Shop.QUALITY_ORDER.has(max_quality):
		return false
	settings.lowGearLevelLimit = level_limit
	settings.lowGearMaxQuality = max_quality
	EventBus.settings_changed.emit()
	return true

func is_low_gear(item: Dictionary) -> bool:
	return Shop.matches_low_gear(item, int(settings.get("lowGearLevelLimit", 5)),
		String(settings.get("lowGearMaxQuality", "common")))

func sell_low_gear() -> Dictionary:
	if int(player.get("level", 1)) < 15:
		return _trade_fail(Localization.tr_key("msg.game_state.p006"))
	var indices: Array[int] = []
	var total := 0
	for i in range(inventory.size()):
		if inventory[i] is Dictionary and is_low_gear(inventory[i]):
			indices.append(i)
			total += Shop.sell_price(inventory[i])
	if indices.is_empty():
		return _trade_fail(Localization.tr_key("msg.game_state.p007"))
	if gold + total > GOLD_CAP:
		return _trade_fail(Localization.tr_key("msg.game_state.p008"))
	for index in indices:
		inventory[index] = null
	add_gold(total)
	EventBus.inventory_changed.emit()
	EventBus.trade_done.emit("sell", "", total)
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p009") % [indices.size(), total], "pickup")
	return {"ok": true, "count": indices.size(), "gold": total}

func inventory_expand() -> Dictionary:
	var cost := Warehouse.next_cost(inventory_expansions)
	if cost < 0:
		return _warehouse_fail(Localization.tr_key("msg.game_state.p010"))
	if gold < cost:
		return _warehouse_fail(Localization.tr_key("msg.game_state.p011") % [cost, gold])
	var old_capacity := inventory.size()
	add_gold(-cost)
	inventory_expansions += 1
	inventory.resize(Warehouse.capacity(inventory_expansions))
	EventBus.inventory_changed.emit()
	EventBus.inventory_expanded.emit()
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p012") % [old_capacity, inventory.size(), cost], "pickup")
	return {"ok": true, "cost": cost, "capacity": inventory.size(), "reason": ""}

# ---- 仓库（M4-3；背包中的所有合法物品）----

func organize_warehouse() -> bool:
	var changed := Inventory.organize(warehouse)
	if changed:
		EventBus.warehouse_changed.emit()
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p013"), "info")
	return changed

func warehouse_store(inv_index: int, expected_id: String, target_index: int = -1) -> Dictionary:
	if inv_index < 0 or inv_index >= inventory.size() or not inventory[inv_index] is Dictionary:
		return _warehouse_fail(Localization.tr_key("msg.game_state.p014"))
	var item: Dictionary = inventory[inv_index]
	if not Warehouse.token_matches(item, expected_id):
		return _warehouse_fail(Localization.tr_key("msg.game_state.p015"))
	var destination := target_index
	if destination == -1:
		if not Inventory.add(warehouse, item):
			return _warehouse_fail(Localization.tr_key("msg.game_state.p016"))
	else:
		if destination < 0 or destination >= warehouse.size() or warehouse[destination] != null:
			return _warehouse_fail(Localization.tr_key("msg.game_state.p017"))
		warehouse[destination] = item.duplicate(true)
	inventory[inv_index] = null
	EventBus.inventory_changed.emit()
	EventBus.warehouse_changed.emit()
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p018") % ItemUtil.display_name(item), "pickup")
	return {"ok": true, "index": destination, "reason": ""}

func warehouse_take(store_index: int, expected_id: String, target_index: int = -1) -> Dictionary:
	if store_index < 0 or store_index >= warehouse.size() or not warehouse[store_index] is Dictionary:
		return _warehouse_fail(Localization.tr_key("msg.game_state.p019"))
	var item: Dictionary = warehouse[store_index]
	if not Warehouse.token_matches(item, expected_id):
		return _warehouse_fail(Localization.tr_key("msg.game_state.p015"))
	var destination := target_index
	if destination == -1:
		if not Inventory.add(inventory, item):
			return _warehouse_fail(Localization.tr_key("msg.game_state.p020"))
	else:
		if destination < 0 or destination >= inventory.size() or inventory[destination] != null:
			return _warehouse_fail(Localization.tr_key("msg.game_state.p021"))
		inventory[destination] = item.duplicate(true)
	warehouse[store_index] = null
	EventBus.inventory_changed.emit()
	EventBus.warehouse_changed.emit()
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p022") % ItemUtil.display_name(item), "pickup")
	return {"ok": true, "index": destination, "reason": ""}

func warehouse_expand() -> Dictionary:
	var cost := Warehouse.next_cost(warehouse_expansions)
	if cost < 0:
		return _warehouse_fail(Localization.tr_key("msg.game_state.p023"))
	if gold < cost:
		return _warehouse_fail(Localization.tr_key("msg.game_state.p024") % [cost, gold])
	var old_capacity := warehouse.size()
	add_gold(-cost)
	warehouse_expansions += 1
	warehouse.resize(Warehouse.capacity(warehouse_expansions))
	EventBus.warehouse_changed.emit()
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p025") % [old_capacity, warehouse.size(), cost], "pickup")
	return {"ok": true, "cost": cost, "capacity": warehouse.size(), "reason": ""}

func _warehouse_fail(reason: String) -> Dictionary:
	EventBus.toast_requested.emit(reason, "danger")
	return {"ok": false, "reason": reason}

# ---- 物品「使用」（M2.5；产品文档 09 §9.2「双击穿戴 / 使用」）----

## 使用背包中指定格的物品（背包双击 / 快捷键 1·2 / 自动喝药统一入口）。
## 按品类分流，返回 {ok, reason, ...}：
##   potion → Consumable.use（回血 / 回蓝 + 独立冷却）
##   equip  → 原穿戴路径（双击装备仍穿戴，行为不变）
##   misc / quest / 其他 → 明确提示「该物品无法使用」（不静默）
func use_item(inv_index: int) -> Dictionary:
	var inv: Array = inventory
	if inv_index < 0 or inv_index >= inv.size() or inv[inv_index] == null:
		return _use_fail(Localization.tr_key("msg.game_state.p026"))
	var it = inv[inv_index]
	if not (it is Dictionary):
		return _use_fail(Localization.tr_key("msg.game_state.p026"))
	var kind := String((it as Dictionary).get("kind", ""))
	match kind:
		"potion":
			return Consumable.use(inv_index)
		"equip":
			return equip_from_inventory(inv_index)
		"misc":
			if String((it as Dictionary).get("itemId", "")) == HotbarConfig.TOWN_SCROLL:
				return TravelItem.use_town_scroll(inv_index)
			if String((it as Dictionary).get("itemId", "")) == HotbarConfig.RANDOM_TICKET:
				return TravelItem.use_random_ticket(inv_index)
		_:
			return _use_fail(Localization.tr_key("msg.game_state.p027") % ItemUtil.display_name(it))
	return _use_fail(Localization.tr_key("msg.game_state.p027") % ItemUtil.display_name(it))

func _use_fail(reason: String) -> Dictionary:
	EventBus.toast_requested.emit(reason, "danger")
	return {"ok": false, "reason": reason}

# ---- 装备穿脱（5.1；槽位规则与属性汇总见 scripts/systems/equipment.gd）----

## 从背包穿上一件装备（slot_id 为空时自动选槽：优先同类空槽，否则替换）。
## 返回 {ok, reason, replaced}；失败广播原因（背包满 / 等级不足 / 槽位不匹配），不静默。
func equip_from_inventory(inv_index: int, slot_id: String = "") -> Dictionary:
	if not pending_equipment_change.is_empty():
		return {"ok": false, "pending": true, "reason": ""}
	if inv_index < 0 or inv_index >= inventory.size() or inventory[inv_index] == null:
		return {"ok": false, "reason": Localization.tr_key("msg.game_state.p026"), "replaced": {}}
	var item: Dictionary = inventory[inv_index]
	if String(item.get("instanceId", "")).is_empty():
		return _equipment_change_fail(Localization.tr_key("msg.equipment.invalid_instance"))
	var preview := Equipment.replacement_preview(equipment, item, slot_id)
	if not bool(preview.get("ok", false)):
		return _equipment_change_fail(String(preview.reason))
	if not Equipment.meets_level(item, int(player.level)):
		return _equipment_change_fail(Localization.tr_key("msg.equipment.p005") % Equipment.level_req(item))
	if int(player.get("hp", 0)) <= 0 or MapService.loading_active:
		return _equipment_change_fail(Localization.tr_key("msg.equipment.unavailable"))
	if bool(preview.downgrade) and not skip_equipment_downgrade_prompt:
		_equipment_request_sequence += 1
		preview["request_id"] = _equipment_request_sequence
		pending_equipment_change = preview.duplicate(true)
		EventBus.equipment_confirmation_requested.emit(preview.duplicate(true))
		return {"ok": false, "pending": true, "request_id": _equipment_request_sequence}
	return _commit_equipment_change(inv_index, String(preview.slot_id))

func confirm_equipment_change(request_id: int, skip_next: bool = false) -> Dictionary:
	if pending_equipment_change.is_empty() or int(pending_equipment_change.request_id) != request_id:
		return _equipment_change_fail(Localization.tr_key("msg.equipment.changed"))
	var preview := pending_equipment_change.duplicate(true)
	var index := -1
	var expected: Dictionary = preview.candidate
	var instance_id := String(expected.get("instanceId", ""))
	for i in range(inventory.size()):
		if inventory[i] is Dictionary and not instance_id.is_empty() \
				and String(inventory[i].get("instanceId", "")) == instance_id:
			index = i
			break
	var worn: Variant = equipment.get(String(preview.slot_id))
	var worn_snapshot: Dictionary = worn if worn is Dictionary else {}
	if index < 0 or inventory[index] != expected or worn_snapshot != preview.worn \
			or int(player.get("hp", 0)) <= 0 or MapService.loading_active:
		cancel_equipment_change()
		return _equipment_change_fail(Localization.tr_key("msg.equipment.changed"))
	# 明确保留原确认槽；物品/属性变化后不能将旧许可用于另一件物品。
	pending_equipment_change = {}
	var result := _commit_equipment_change(index, String(preview.slot_id))
	if bool(result.get("ok", false)) and skip_next:
		skip_equipment_downgrade_prompt = true
	EventBus.equipment_confirmation_closed.emit()
	return result

func cancel_equipment_change() -> void:
	if pending_equipment_change.is_empty():
		return
	pending_equipment_change = {}
	EventBus.equipment_confirmation_closed.emit()

func reset_equipment_prompt_session() -> void:
	cancel_equipment_change()
	skip_equipment_downgrade_prompt = false

func _equipment_change_fail(reason: String) -> Dictionary:
	EventBus.toast_requested.emit(reason, "danger")
	return {"ok": false, "reason": reason}

func _commit_equipment_change(inv_index: int, target: String) -> Dictionary:
	var item: Dictionary = inventory[inv_index]
	var res := Equipment.equip_from_inventory(
		equipment, inventory, target, inv_index, int(player.level))
	if bool(res.get("ok", false)):
		_after_equip_change()
		EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p028") + ItemUtil.display_name(item), "pickup")
	else:
		EventBus.toast_requested.emit(String(res.get("reason", Localization.tr_key("msg.game_state.p029"))), "danger")
	return res

## 卸下槽位装备（需背包空位，5.1）。返回 {ok, reason, item}。
func unequip_slot(slot_id: String) -> Dictionary:
	var res := Equipment.unequip(equipment, inventory, slot_id)
	if bool(res.get("ok", false)):
		var item: Dictionary = res.get("item", {})
		_after_equip_change()
		EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p030") + ItemUtil.display_name(item), "info")
	else:
		EventBus.toast_requested.emit(String(res.get("reason", Localization.tr_key("msg.game_state.p031"))), "danger")
	return res

func unequip_slot_to_inventory(slot_id: String, inv_index: int) -> Dictionary:
	var res := Equipment.unequip_to_index(equipment, inventory, slot_id, inv_index)
	if bool(res.get("ok", false)):
		_after_equip_change()
		EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p030") + ItemUtil.display_name(res.get("item", {})), "info")
	else:
		EventBus.toast_requested.emit(String(res.get("reason", Localization.tr_key("msg.game_state.p031"))), "danger")
	return res

## 穿脱后统一收尾（T06：穿戴后属性立即生效）：
## 广播装备 / 背包变更；上限可能降低时把当前 HP / MP 收敛到新上限（不补满、不按比例）。
func _after_equip_change() -> void:
	EventBus.equipment_changed.emit()
	EventBus.inventory_changed.emit()
	player.hp = mini(int(player.hp), max_hp())
	player.mp = mini(int(player.mp), max_mp())
	EventBus.player_hp_changed.emit(int(player.hp), max_hp())
	EventBus.player_mp_changed.emit(int(player.mp), max_mp())

# ---- 装备升星（M4-1）----

## source = "bag" / "worn"；key 是背包下标或装备槽 id。
## expected_id 防止选择后背包整理、穿脱导致错误实例被扣费。
func upgrade_equipment(source: String, key: Variant, expected_id: String,
		rng: RandomNumberGenerator = null, rune_ids: Array = []) -> Dictionary:
	var item: Dictionary = {}
	if source == "bag" and key is int and key >= 0 and key < inventory.size():
		var candidate = inventory[key]
		if candidate is Dictionary:
			item = candidate
	elif source == "worn" and key is String:
		var candidate = equipment.get(key)
		if candidate is Dictionary:
			item = candidate
	if item.is_empty() or expected_id.is_empty() or String(item.get("instanceId", "")) != expected_id:
		return _upgrade_fail(Localization.tr_key("msg.game_state.p032"))
	if String(item.get("kind", "")) != "equip":
		return _upgrade_fail(Localization.tr_key("msg.game_state.p033"))
	var star := int(item.get("star", 0))
	if star < 0 or star >= Upgrade.max_star():
		return _upgrade_fail(Localization.tr_key("msg.game_state.p034"))
	var price := Upgrade.cost(star)
	if price <= 0 or Upgrade.success_rate(star) <= 0.0:
		return _upgrade_fail(Localization.tr_key("msg.game_state.p035"))
	var plan := Upgrade.rune_plan(inventory, rune_ids)
	if not plan.get("ok", false):
		return _upgrade_fail(String(plan.get("reason", Localization.tr_key("msg.game_state.p036"))))
	if gold < price:
		return _upgrade_fail(Localization.tr_key("msg.game_state.p037") % [price, gold])
	for use in plan.uses:
		var index := int(use.index)
		var entry: Dictionary = inventory[index]
		var left := int(entry.get("count", 0)) - int(use.count)
		if left <= 0:
			inventory[index] = null
		else:
			inventory[index] = entry.duplicate(true)
			inventory[index].count = left
	add_gold(-price)
	var rate := Upgrade.final_rate(star, float(plan.bonus))
	var success := Upgrade.roll_success(star, rng, float(plan.bonus))
	if success:
		item["star"] = star + 1
		if source == "worn":
			EventBus.equipment_changed.emit()
			EventBus.player_hp_changed.emit(int(player.hp), max_hp())
			EventBus.player_mp_changed.emit(int(player.mp), max_mp())
	if (success and source == "bag") or not plan.uses.is_empty():
		EventBus.inventory_changed.emit()
	EventBus.upgrade_completed.emit()
	var spend := Localization.tr_key("msg.game_state.p038") % [price, int(plan.count)] if int(plan.count) > 0 else Localization.tr_key("msg.game_state.p039") % price
	var message := Localization.tr_key("msg.game_state.p040") % [ItemUtil.display_name(item), spend] if success \
		else Localization.tr_key("msg.game_state.p041") % [star, spend]
	EventBus.toast_requested.emit(message, "pickup" if success else "danger")
	return {"ok": true, "success": success, "cost": price, "star": int(item.get("star", 0)),
		"runesUsed": int(plan.count), "rate": rate, "reason": message}

func _upgrade_fail(reason: String) -> Dictionary:
	EventBus.toast_requested.emit(reason, "danger")
	return {"ok": false, "success": false, "cost": 0, "reason": reason}

# ---- 世界时钟与怪物点刷新状态（M4-10）----
## 契约：刷新倒计时由**世界时钟**（`world_time`）统一驱动，不再有第二套计时器。
## key 用 `map_id#monster_id#同种序号`（稳定），不用数组下标 —— 地图数据增减点不错位。

## 怪物点状态 key（稳定标识）。
func spawn_key(map_id: String, monster_id: String, ordinal: int) -> String:
	return "%s#%s#%d" % [map_id, monster_id, ordinal]

## 标记怪物点已死亡：记录「到点时刻」与「死亡位置」（跨图后墓碑在原处重建）。
func mark_spawn_dead(map_id: String, monster_id: String, ordinal: int,
		respawn_time: float, pos: Vector2) -> void:
	spawn_respawn[spawn_key(map_id, monster_id, ordinal)] = {
		"readyAt": world_time + maxf(0.0, respawn_time),
		"pos": pos,
	}

## 该点剩余刷新时间（秒）：> 0 = 仍在墓碑；<= 0 = 可刷新（顺带清除过期记录）。
func spawn_remaining(map_id: String, monster_id: String, ordinal: int) -> float:
	var key := spawn_key(map_id, monster_id, ordinal)
	if not spawn_respawn.has(key):
		return 0.0
	var record: Dictionary = spawn_respawn[key]
	var left := float(record.get("readyAt", 0.0)) - world_time
	if left <= 0.0:
		spawn_respawn.erase(key)
		return 0.0
	return left

## 清除某点状态（该点重生后调用）。
func clear_spawn_state(map_id: String, monster_id: String, ordinal: int) -> void:
	spawn_respawn.erase(spawn_key(map_id, monster_id, ordinal))

## 该点的死亡位置（无记录 → null，调用方回退随机位置）。
func spawn_dead_pos(map_id: String, monster_id: String, ordinal: int) -> Variant:
	var key := spawn_key(map_id, monster_id, ordinal)
	if not spawn_respawn.has(key):
		return null
	var record: Dictionary = spawn_respawn[key]
	var raw: Variant = record.get("pos", null)
	if raw is Vector2:
		return raw
	return null

## 存档编码：Vector2 → [x, y]（JSON 无 Vector2；见工程文档 14 §3.1 ④）。
func encode_spawn_respawn() -> Dictionary:
	var out: Dictionary = {}
	for key in spawn_respawn.keys():
		var record: Dictionary = spawn_respawn[key]
		var raw_pos: Variant = record.get("pos", Vector2.ZERO)
		var pos: Vector2 = raw_pos if raw_pos is Vector2 else Vector2.ZERO
		out[key] = {"readyAt": float(record.get("readyAt", 0.0)), "pos": [pos.x, pos.y]}
	return out

## 读档解码：[x, y] → Vector2。非法项**忽略而非拒档**（地图数据变动不应导致读档失败）。
func apply_spawn_respawn(raw: Variant) -> void:
	spawn_respawn = {}
	if not (raw is Dictionary):
		return
	for key in (raw as Dictionary).keys():
		var record: Variant = raw[key]
		if not (record is Dictionary):
			continue
		var at: Variant = (record as Dictionary).get("readyAt", null)
		if not (at is int or at is float) or not is_finite(float(at)):
			continue
		spawn_respawn[String(key)] = {
			"readyAt": float(at),
			"pos": _decode_pos((record as Dictionary).get("pos", null)),
		}

## [x, y] → Vector2；非法 → Vector2.ZERO。
func _decode_pos(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		var arr: Array = raw
		if (arr[0] is int or arr[0] is float) and (arr[1] is int or arr[1] is float):
			return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO

# ---- 未领取战利品（M6-0c；创意 07 §11）----
## 精英 / Boss 入包失败的掉落物登记于此：跨图 / 跨档保留，直到领取或玩家主动丢弃。
## uid 全局唯一（跨图查找即可注销，调用方无需记 map_id）。

## 登记一件未领取战利品，返回其唯一 uid（领取成功时据此注销）。
func add_unclaimed_loot(map_id: String, batch_id: String, item: Dictionary, pos: Vector2) -> String:
	if map_id.is_empty() or item.is_empty():
		return ""
	_unclaimed_seq += 1
	var uid := "u_%d_%d" % [Time.get_ticks_msec(), _unclaimed_seq]
	if not unclaimed_loot.has(map_id):
		unclaimed_loot[map_id] = []
	(unclaimed_loot[map_id] as Array).append({
		"uid": uid, "batchId": batch_id, "item": item.duplicate(true), "pos": pos,
	})
	return uid

## 注销某条未领取记录（领取成功后，§11.3）。uid 全局唯一，故跨图查找。返回是否命中。
func remove_unclaimed_loot(uid: String) -> bool:
	if uid.is_empty():
		return false
	for map_id in unclaimed_loot.keys():
		var rows: Array = unclaimed_loot[map_id]
		for i in range(rows.size()):
			if String((rows[i] as Dictionary).get("uid", "")) == uid:
				rows.remove_at(i)
				if rows.is_empty():
					unclaimed_loot.erase(map_id)
				return true
	return false

## 某图当前未领取记录（深拷贝，供重建地面物）。
func unclaimed_loot_for(map_id: String) -> Array:
	if not unclaimed_loot.has(map_id):
		return []
	return (unclaimed_loot[map_id] as Array).duplicate(true)

## 某图未领取件数（供界面 / 批次摘要提示，§11.6）。
func unclaimed_count(map_id: String) -> int:
	var rows: Variant = unclaimed_loot.get(map_id, [])
	return (rows as Array).size() if rows is Array else 0

## 存档编码：Vector2 → [x, y]（JSON 无 Vector2；与 encode_spawn_respawn 同构）。
func encode_unclaimed_loot() -> Dictionary:
	var out: Dictionary = {}
	for map_id in unclaimed_loot.keys():
		var rows: Array = []
		for record in (unclaimed_loot[map_id] as Array):
			if not (record is Dictionary):
				continue
			var pos_v: Variant = (record as Dictionary).get("pos", Vector2.ZERO)
			var p: Vector2 = pos_v if pos_v is Vector2 else Vector2.ZERO
			var item_v: Variant = (record as Dictionary).get("item", {})
			rows.append({
				"uid": String((record as Dictionary).get("uid", "")),
				"batchId": String((record as Dictionary).get("batchId", "")),
				"item": (item_v as Dictionary).duplicate(true) if item_v is Dictionary else {},
				"pos": [p.x, p.y],
			})
		out[String(map_id)] = rows
	return out

## 读档解码：[x, y] → Vector2。非法项**忽略而非拒档**（地图数据变动不应导致读档失败）。
func apply_unclaimed_loot(raw: Variant) -> void:
	unclaimed_loot = {}
	_unclaimed_seq = 0
	if not (raw is Dictionary):
		return
	for map_id in (raw as Dictionary).keys():
		var rows: Variant = (raw as Dictionary)[map_id]
		if not (rows is Array):
			continue
		var clean: Array = []
		for record in (rows as Array):
			if not (record is Dictionary):
				continue
			var item_v: Variant = (record as Dictionary).get("item", {})
			if not (item_v is Dictionary) or (item_v as Dictionary).is_empty():
				continue
			clean.append({
				"uid": String((record as Dictionary).get("uid", "")),
				"batchId": String((record as Dictionary).get("batchId", "")),
				"item": (item_v as Dictionary).duplicate(true),
				"pos": _decode_pos((record as Dictionary).get("pos", null)),
			})
		if not clean.is_empty():
			unclaimed_loot[String(map_id)] = clean

# ---- 自动战斗 / 自动拾取开关（M1-9，3.14 / 4.6）----

## 设置自动战斗开关（F 键）。返回新状态。决策机订阅本信号以重置锚点。
func set_auto_battle(on: bool) -> bool:
	if auto_battle_on == on:
		return auto_battle_on
	auto_battle_on = on
	EventBus.auto_state_changed.emit(auto_battle_on, auto_pickup_on)
	var msg := Localization.tr_key("msg.game_state.p042") if on else Localization.tr_key("msg.game_state.p043")
	if on and auto_pickup_on:
		msg += Localization.tr_key("msg.game_state.p044")
	EventBus.toast_requested.emit(msg, "info")
	return auto_battle_on

## 切换自动战斗（F）。
func toggle_auto_battle() -> bool:
	return set_auto_battle(not auto_battle_on)

## 设置自动拾取开关（G 键；9.9：仅控制**自动战斗时**是否顺路走向掉落物，
## 手动靠近本来就会自动入包）。返回新状态。
func set_auto_pickup(on: bool) -> bool:
	if auto_pickup_on == on:
		return auto_pickup_on
	auto_pickup_on = on
	EventBus.auto_state_changed.emit(auto_battle_on, auto_pickup_on)
	EventBus.toast_requested.emit(
		Localization.tr_key("msg.game_state.p045") if on else Localization.tr_key("msg.game_state.p046"), "info")
	return auto_pickup_on

## 切换自动拾取（G）。
func toggle_auto_pickup() -> bool:
	return set_auto_pickup(not auto_pickup_on)

# ---- 面板互斥（M1-7 / M1-8）----

## 登记 / 注销一个已打开的面板；任一面板打开即置 panel_open（player.gd 据此屏蔽操控）。
## 多面板互斥由各面板订阅 EventBus.panel_opened 自行关闭实现（I 背包 / E 货郎）。
func set_panel_open(panel_id: String, open: bool) -> void:
	if open:
		_open_panels[panel_id] = true
	else:
		_open_panels.erase(panel_id)
	panel_open = not _open_panels.is_empty()

## 仅 NPC 会话暂停挂机；普通可并开的信息面板不影响自动决策。
func npc_dialog_open() -> bool:
	for panel_id in ["shop", "quest", "carter", "blacksmith", "warehouse", "upgrade"]:
		if _open_panels.has(panel_id):
			return true
	return false

# ---- 货郎交易（6.4；算价与物品构造见 scripts/systems/shop.gd）----

## 向货郎购买一件商品。返回 {ok, reason, item, price}。
## 失败原因明确广播提示（金币不足 / 背包满 / 不售此物），不静默。
func shop_buy(shop_id: String, item_id: String) -> Dictionary:
	var price := Shop.buy_price(shop_id, item_id)
	if price < 0:
		return _trade_fail(Localization.tr_key("msg.game_state.p047"))
	var item := Shop.make_item(item_id)
	if item.is_empty():
		return _trade_fail(Localization.tr_key("msg.game_state.p048") % item_id)
	if not Inventory.has_space_for(inventory, item):
		return _trade_fail(Localization.tr_key("msg.game_state.p049"))
	if gold < price:
		return _trade_fail(Localization.tr_key("msg.game_state.p037") % [price, gold])
	add_gold(-price)
	add_item(item)
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p050") % [ItemUtil.display_name(item), price], "pickup")
	EventBus.trade_done.emit("buy", item_id, price)
	return {"ok": true, "reason": "", "item": item, "price": price}

## 出售背包中指定格的装备（6.4：货郎只收购装备）。返回 {ok, reason, item, price}。
## silent = true 时不广播单件 toast（供面板批量出售后自行汇总，避免刷屏）。
func shop_sell(inv_index: int, silent: bool = false) -> Dictionary:
	if inv_index < 0 or inv_index >= inventory.size() or inventory[inv_index] == null:
		return _trade_fail(Localization.tr_key("msg.game_state.p026"))
	var item: Dictionary = inventory[inv_index]
	if not Shop.can_sell(item):
		return _trade_fail(Localization.tr_key("msg.game_state.p051"))
	var price := Shop.sell_price(item)
	var label := ItemUtil.display_name(item)
	remove_item_at(inv_index)
	add_gold(price)
	if not silent:
		EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p052") % [label, price], "pickup")
	EventBus.trade_done.emit("sell", String(item.get("itemId", "")), price)
	return {"ok": true, "reason": "", "item": item, "price": price}

## 结算一批暂存待售的装备（6.4「确认出售」）。托盘内容由出售界面持有，本函数只做算价与入账。
## 返回 {count, gold}；无可售项时返回 {count: 0, gold: 0}（不扣物、不广播）。
func shop_sell_staged(items: Array) -> Dictionary:
	var total := 0
	var n := 0
	for it in items:
		if it is Dictionary and Shop.can_sell(it):
			total += Shop.sell_price(it)
			n += 1
	if n == 0:
		return {"count": 0, "gold": 0}
	add_gold(total)
	EventBus.trade_done.emit("sell", "", total)
	return {"count": n, "gold": total}

## 把暂存装备退回背包（关闭面板未确认 / 点托盘格取回）。会就地移除已退回项。
## 返回实际退回件数；背包满的件保留在托盘由调用方提示（不静默丢失，6.4）。
func shop_unstage(items: Array) -> int:
	var back := 0
	var i := items.size() - 1
	while i >= 0:
		var it = items[i]
		if it is Dictionary and add_item(it):
			items.remove_at(i)
			back += 1
		i -= 1
	return back

## 该装备是否优于同类型已穿戴装备（6.4 一键出售排除判据 / 5.9 评分）。
## 同类型槽全空 → 不算升级件（可出售）。
func is_upgrade_over_worn(item: Dictionary) -> bool:
	var kind := Equipment.item_kind(item)
	if kind.is_empty():
		return false
	var best := 0.0
	var has_worn := false
	for sid in Equipment.slots_for_kind(kind):
		var w = equipment.get(sid)
		if w is Dictionary:
			has_worn = true
			best = maxf(best, Equipment.score(w))
	if not has_worn:
		return false
	return Equipment.score(item) > best

## 交易失败统一出口：广播明确原因（9.6），返回统一结构。
func _trade_fail(reason: String) -> Dictionary:
	EventBus.toast_requested.emit(reason, "danger")
	return {"ok": false, "reason": reason, "item": {}, "price": 0}

## 增加经验，并按 4.4 处理（多级连升、剩余结转）。
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	player.xp = int(player.xp) + amount
	EventBus.xp_gained.emit(amount)
	while int(player.xp) >= xp_to_next(int(player.level)):
		player.xp = int(player.xp) - xp_to_next(int(player.level))
		_level_up()
	EventBus.player_xp_changed.emit(int(player.xp), xp_to_next(int(player.level)))

## 升级：属性成长 + 按 4.3「升级保留当前 HP / MP 百分比」结转。
func _level_up() -> void:
	var prev_hp := max_hp()
	var prev_mp := max_mp()
	var hp_ratio := float(player.hp) / float(max(1, prev_hp))
	var mp_ratio := float(player.mp) / float(max(1, prev_mp))
	player.level = int(player.level) + 1
	player.attack = int(player.attack) + 2   # 4.4：每级 攻 +2
	player.defense = int(player.defense) + 1 # 4.4：每级 防 +1
	player.hp = int(round(float(max_hp()) * hp_ratio))
	player.mp = int(round(float(max_mp()) * mp_ratio))
	EventBus.player_leveled.emit(int(player.level))
	EventBus.player_hp_changed.emit(int(player.hp), max_hp())
	EventBus.player_mp_changed.emit(int(player.mp), max_mp())
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p053") % int(player.level), "levelup")

## 广播全部数值（HUD 初始化 / 读档后同步）。
func emit_all() -> void:
	EventBus.gold_changed.emit(gold)
	EventBus.mount_changed.emit()
	EventBus.equipment_changed.emit()
	EventBus.inventory_changed.emit()
	EventBus.player_leveled.emit(int(player.level))
	EventBus.player_hp_changed.emit(int(player.hp), max_hp())
	EventBus.player_mp_changed.emit(int(player.mp), max_mp())
	EventBus.player_xp_changed.emit(int(player.xp), xp_to_next(int(player.level)))
