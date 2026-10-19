extends Node
## GameState — 全局运行时状态（单例 / Autoload）。
##
## 持有角色、经济、进度、设置的运行时数据；启动时赋予初始参数
## （数值来源：docs/产品文档/04 角色成长系统 4.4 初始值）。
## 不持久化运行时节点对象——存档由 SaveManager 负责序列化这里的数据。

## 背包格数（5.8：40 格）与金币上限（6.2：999,999,999）。
const INVENTORY_SIZE := 40
const GOLD_CAP := 999999999
## 未领取战利品件数上限（M6-0c 追加上限）。超限时按登记顺序丢弃最旧记录，
## 并广播事件令对应地面物销毁，避免长挂机下节点数与存档体积单调增长。
## M10-3（P-9 / D-13）：改为**按图分级** —— 本值只是缺省，地图可在 `maps.json`
## 用 `unclaimedLootCap` 覆盖（循环图配 200：一轮 10 只 × 7–10 件必须装得下）。
## 注意：分流前是「跨全部地图总数 ≤ 20」，一张图刷满会把别的图的记录挤掉；
## 改为逐图判定后，记录只受**本图**上限约束。
const UNCLAIMED_LOOT_CAP := 20

## 存档校验上界（C-P3-1）。战斗侧已有明确上界者直接引用 `Combat`（暴击率 / 暴伤 / 攻击间隔），
## 其余取宽松上限——目的仅为拦「明显异常或被篡改」的值，不作为数值调平口径。
## M10-0：等级上限 999 → 9999、属性上限 999,999 → 99,999,999（产品 13 §9.3 Q-9）。
## 两者**必须同批抬**：`Balance.base_attack(9999) = 28,339,142`，若只抬等级，
## 1915 级就会从属性校验口被判定为「被篡改」而整档拒收（P-16）。
## 9999 的选型理由：E(9999) ≈ 7.5×10^10，仍在 int64 与 JSON 双精度（2^53）余量内；
## 再往上 `pow` 返回的 float 先失真，护栏就不再可信。
const PLAYER_LEVEL_CAP := 9999
## 一键出售等级筛选上限：与玩家等级上限对齐，避免「界面能设、后端拒收」的静默失败。
## 选用 9999 而非更大值：等同 PLAYER_LEVEL_CAP 余量边界，超出即代表「不限制等级」。
const LOW_GEAR_LEVEL_MAX := 9999
const PLAYER_STAT_CAP := 99999999.0
const PLAYER_MOVE_SPEED_CAP := 100.0
## 冷却缩减上限（产品 03 §3.8 / 04 §4.2：≤50%）。结算按加法累加后截断到本上限（D7）。
const PLAYER_CDR_CAP := 0.5

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
## 本次会话最近骑过的坐骑；下马后快捷键优先重新骑它，不另增存档字段。
var preferred_mount: String = ""
var equipment: Dictionary = {}      # 已穿戴装备（槽 id → 实例，14 槽，见 Equipment / 5.1）
## 降品质提醒为会话状态：跨图保留，新游戏/成功读档清零；不进入存档或 settings。
var skip_equipment_downgrade_prompt := false
var pending_equipment_change: Dictionary = {}
var _equipment_request_sequence := 0
var panel_open: bool = false        # 是否有关闭式面板打开中；普通面板不阻断角色操控
var _open_panels: Dictionary = {}   # 已打开面板 id 集合（多面板互斥，见 set_panel_open）
var quest_states: Dictionary = {}   # quest_id -> {"state": String, "progress": int}（M2 起；见 scripts/systems/quest.gd）
var quest_items: Dictionary = {}    # 第二章确定来源的任务物品；独立任务袋，不占背包格
## E1（工程文档 30 §4）：持久任务发奖计划 —— quest_id -> {item, bonus}。
## 带随机成分的奖励实例在首次有效交付尝试时一次抽定并存入此处，满包等失败重试复用同一
## 实例与词条，领奖成功后才清除；失败重试不得成为洗词条入口。
var quest_reward_plans: Dictionary = {}
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

## 货郎交易托盘内的暂存件数（E-P3-4）。托盘物品已从背包移出却尚未落档，
## 故 > 0 时 SaveManager 挂起自动存档（否则交易中被触发的自动存档会把它们漏掉）。
## 由 ShopPanel 在托盘变更 / 退回处同步；面板关闭退回后自然归 0。运行态，不落档。
var trade_staged_count: int = 0

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
## F-P3-2：先广播统一关闭事件，各面板回退自身中间态（货郎出售托盘退回、快捷栏拖放模式、
## 菜单流程态等），再清空登记——两者成对，不再依赖「调用点必然伴随场景重载」。
func close_all_panels() -> void:
	cancel_equipment_change()
	EventBus.panels_close_requested.emit()
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
	return true

func clear_buffs() -> void:
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
		"autoReviveOnDeath": false,   # 死亡后自动原地复活并恢复战斗（需背包有复活卷）
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
		"sellGearPreset": SellGearPolicy.CAUTIOUS,
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
	preferred_mount = ""
	equipment = Equipment.create()
	panel_open = false
	_open_panels = {}
	trade_staged_count = 0          # E-P3-4：新游戏 / 读档清空托盘暂存计数
	quest_states = {}
	quest_items = {}
	quest_reward_plans = {}
	first_clear = {}
	unlocks = {}
	explored_maps = {}
	auto_battle_on = false          # 10.3：重启后自动战斗默认关闭
	auto_pickup_on = false
	# C-P3-4：菜单流程态为本次会话运行态（不落档），重置/新游戏后回到主菜单，避免残留 "world"。
	menu_mode = "menu"
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

## 经验升级所需（M10-0 起走 Balance 曲线；L ≤ 60 与旧的 round(100 × L^1.6) 逐位一致）。
func xp_to_next(level: int) -> int:
	return Balance.xp_to_next(level)

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

## 总冷却缩减 = 基础 + 装备词条，**按加法累加**后截断到上限（D7 / 产品 03 §3.8「超限部分在结算时截断」）。
## 唯一口径入口：展示与施放冷却都读这里，避免各调用点各算一遍。
func total_cdr() -> float:
	return clampf(float(player.get("cdr", 0.0)) + float(equip_bonus().get("cdr", 0.0)), 0.0, PLAYER_CDR_CAP)

## 施放冷却 = 基础冷却 × (1 − 总冷却缩减)。技能冷却是运行态（切图保留、读档重建）。
func cooldown_after_cdr(base_cooldown: float) -> float:
	return maxf(0.0, base_cooldown) * (1.0 - total_cdr())

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
	preferred_mount = mount_id
	EventBus.mount_changed.emit()
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p003") % String(mount.get("name", mount_id)), "pickup")
	return {"ok": true}

func dismount() -> void:
	if active_mount.is_empty():
		return
	active_mount = ""
	EventBus.mount_changed.emit()
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p004"), "info")

## 骑乘/下马快捷入口：优先最近骑过的坐骑，否则选收藏中第一只已解锁坐骑。
## 不修改收藏与存档结构；失败时沿用骑乘等级提示。
func toggle_mount() -> bool:
	if not active_mount.is_empty():
		dismount()
		return true
	if owned_mounts.is_empty():
		EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.mount_empty"), "danger")
		return false
	var candidate := preferred_mount if owned_mounts.has(preferred_mount) else ""
	if candidate.is_empty():
		for mount_id in owned_mounts:
			var template: Variant = DataLoader.get_entry("mounts", mount_id)
			if template is Dictionary and int(player.get("level", 1)) >= int(template.get("levelReq", 20)):
				candidate = mount_id
				break
	if candidate.is_empty():
		candidate = owned_mounts[0]
	var result := ride_mount(candidate)
	if not bool(result.get("ok", false)):
		EventBus.toast_requested.emit(String(result.get("reason", Localization.tr_key("msg.game_state.p001"))), "danger")
		return false
	return true

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
	if level_limit < 1 or level_limit > LOW_GEAR_LEVEL_MAX or not Shop.QUALITY_ORDER.has(max_quality):
		return false
	settings.lowGearLevelLimit = level_limit
	settings.lowGearMaxQuality = max_quality
	EventBus.settings_changed.emit()
	return true

## 保存装备清包预设；旧数字阈值仅留作旧档读取，不影响新清单。
func set_sell_gear_preset(preset: String) -> bool:
	if not SellGearPolicy.valid_preset(preset):
		return false
	settings.sellGearPreset = preset
	EventBus.settings_changed.emit()
	return true

## 按稳定实例 ID 切换装备收藏；可覆盖背包、穿戴与仓库，成功后只广播所在容器变化。
func set_equipment_favorite(instance_id: String, favorite: bool) -> bool:
	if instance_id.is_empty():
		return false
	for i in range(inventory.size()):
		if inventory[i] is Dictionary and String(inventory[i].get("instanceId", "")) == instance_id:
			var item: Dictionary = inventory[i]
			item.favorite = favorite
			inventory[i] = item
			EventBus.inventory_changed.emit()
			EventBus.equipment_favorite_changed.emit()
			return true
	for slot in equipment.keys():
		if equipment[slot] is Dictionary and String(equipment[slot].get("instanceId", "")) == instance_id:
			var item: Dictionary = equipment[slot]
			item.favorite = favorite
			equipment[slot] = item
			EventBus.equipment_changed.emit()
			EventBus.equipment_favorite_changed.emit()
			return true
	for i in range(warehouse.size()):
		if warehouse[i] is Dictionary and String(warehouse[i].get("instanceId", "")) == instance_id:
			var item: Dictionary = warehouse[i]
			item.favorite = favorite
			warehouse[i] = item
			EventBus.warehouse_changed.emit()
			EventBus.equipment_favorite_changed.emit()
			return true
	return false

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

## 生成当前角色背包装备清单；只读，界面可据此勾选，交易时须再次重核。
func preview_equipment_sale() -> Array[Dictionary]:
	return SellGearPolicy.build_preview(inventory, int(player.get("level", 1)), equipment,
		String(settings.get("sellGearPreset", SellGearPolicy.CAUTIOUS)))

## 确认前按实例 ID 重定位并核对快照、预设、装备比较、价格和收藏状态。
## 返回 {ok, indices, items, total, reason}；无副作用，供直卖和货郎批量暂存复用。
func validate_equipment_sale(rows: Array[Dictionary], allow_risky: bool = false) -> Dictionary:
	if rows.is_empty():
		return {"ok": false, "reason": "请选择要处理的装备"}
	var by_id := {}
	for i in range(inventory.size()):
		if inventory[i] is Dictionary and String(inventory[i].get("kind", "")) == "equip":
			by_id[String(inventory[i].get("instanceId", ""))] = i
	var seen := {}
	var indices: Array[int] = []
	var items: Array[Dictionary] = []
	var total := 0
	var level := int(player.get("level", 1))
	var preset := String(settings.get("sellGearPreset", SellGearPolicy.CAUTIOUS))
	for row in rows:
		var instance_id := String(row.get("instance_id", ""))
		if instance_id.is_empty() or seen.has(instance_id) or not by_id.has(instance_id):
			return {"ok": false, "reason": "装备清单已变化，请重新核对"}
		seen[instance_id] = true
		var i: int = by_id[instance_id]
		var item: Dictionary = inventory[i]
		if item != row.get("item_snapshot", {}) or not Shop.can_sell(item) \
				or level != int(row.get("player_level", -1)) or preset != String(row.get("preset", "")):
			return {"ok": false, "reason": "装备清单已变化，请重新核对"}
		var current := SellGearPolicy.entry(item, i, level, equipment, preset)
		if int(current.get("price", -1)) != int(row.get("price", -2)) \
				or bool(current.get("protected_upgrade", false)) != bool(row.get("protected_upgrade", false)) \
				or bool(current.get("default_selected", false)) != bool(row.get("default_selected", false)):
			return {"ok": false, "reason": "装备清单已变化，请重新核对"}
		if not bool(current.get("default_selected", false)) and not allow_risky:
			return {"ok": false, "reason": "所选装备需要再次确认"}
		indices.append(i)
		items.append(item)
		total += Shop.sell_price(item)
	return {"ok": true, "indices": indices, "items": items, "total": total, "reason": ""}

## Lv15 后按玩家核对的实例清单整批直卖；任一前置条件失败则背包与金币均不变。
func sell_selected_equipment(rows: Array[Dictionary], allow_risky: bool = false) -> Dictionary:
	if int(player.get("level", 1)) < 15:
		return {"ok": false, "reason": "达到 15 级后才可在背包直接出售装备"}
	var checked := validate_equipment_sale(rows, allow_risky)
	if not bool(checked.get("ok", false)):
		return checked
	var total := int(checked.total)
	if total > GOLD_CAP - gold:
		return {"ok": false, "reason": "金币已接近上限，请减少待售装备"}
	for index in checked.indices:
		inventory[index] = null
	add_gold(total)
	EventBus.inventory_changed.emit()
	EventBus.trade_done.emit("sell", "", total)
	return {"ok": true, "count": rows.size(), "gold": total, "reason": ""}

## 货郎在托盘空格足够时整批取出已核对装备；先增暂存计数防止中途自动存档。
## 托盘最终归属仍由 ShopPanel 负责；调用前须确认交易会话有效且托盘确有空格。
func take_equipment_for_sale(rows: Array[Dictionary], available_slots: int,
		allow_risky: bool = false) -> Dictionary:
	if rows.size() > available_slots:
		return {"ok": false, "reason": "出售托盘空位不足，请减少勾选"}
	var checked := validate_equipment_sale(rows, allow_risky)
	if not bool(checked.get("ok", false)):
		return checked
	trade_staged_count += rows.size()
	for index in checked.indices:
		inventory[index] = null
	EventBus.inventory_changed.emit()
	return {"ok": true, "items": checked.items, "count": rows.size(), "gold": int(checked.total), "reason": ""}

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
			return _use_misc(inv_index, it as Dictionary)
		_:
			return _use_fail(Localization.tr_key("msg.game_state.p027") % ItemUtil.display_name(it))
	return _use_fail(Localization.tr_key("msg.game_state.p027") % ItemUtil.display_name(it))

## M10-4（P-6）：杂项按数据表 `useType` 分发，不再按 itemId 硬编码 ——
## 否则每加一件「面板道具」都要回来改这段，正是 P-6 的病根。
## `townPortal / randomTeleport` 仍调原函数（内部自校验 itemId，行为零变化）；
## `panel` 走 `PanelRouter`；其余用途（playAnimation / revive / quest / 空）保持原兜底提示。
func _use_misc(inv_index: int, item: Dictionary) -> Dictionary:
	var tpl: Variant = DataLoader.get_entry("miscItems", String(item.get("itemId", "")))
	if not tpl is Dictionary:
		return _use_fail(Localization.tr_key("msg.game_state.p027") % ItemUtil.display_name(item))
	match String((tpl as Dictionary).get("useType", "")):
		"townPortal":
			return TravelItem.use_town_scroll(inv_index)
		"randomTeleport":
			return TravelItem.use_random_ticket(inv_index)
		"panel":
			var res := PanelRouter.open(String((tpl as Dictionary).get("panelId", "")))
			if not bool(res.get("ok", false)):
				return _use_fail(String(res.get("reason", "")))
			return {"ok": true, "reason": ""}
	return _use_fail(Localization.tr_key("msg.game_state.p027") % ItemUtil.display_name(item))

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

## 按背包装备快照执行三种铁匠合成；任何校验失败都不改背包或金币。
## UI 传入打开预览时的完整实例字典，确认时按 instanceId 重定位，避免整理后误耗。
func forge_equipment(mode: String, selected: Array[Dictionary], target_kind: String = "",
		rng: RandomNumberGenerator = null) -> Dictionary:
	var needed := 2 if mode == EquipmentFusion.STAR_TRANSFER else 4
	if selected.size() != needed or mode not in [EquipmentFusion.GOLD_TO_PURPLE,
			EquipmentFusion.PURPLE_TARGET, EquipmentFusion.STAR_TRANSFER]:
		return {"ok": false, "reason": "请选择正确数量的装备"}
	var by_id := {}
	for i in range(inventory.size()):
		if inventory[i] is Dictionary:
			by_id[String(inventory[i].get("instanceId", ""))] = i
	var indices: Array[int] = []
	var items: Array[Dictionary] = []
	var seen := {}
	for snapshot in selected:
		var id := String(snapshot.get("instanceId", ""))
		if id.is_empty() or seen.has(id) or not by_id.has(id):
			return {"ok": false, "reason": "材料已变化，请重新选择"}
		seen[id] = true
		var index: int = by_id[id]
		if inventory[index] != snapshot:
			return {"ok": false, "reason": "材料已变化，请重新选择"}
		indices.append(index)
		items.append(inventory[index])
	var plan := EquipmentFusion.plan_transfer(items[0], items[1]) if mode == EquipmentFusion.STAR_TRANSFER \
		else EquipmentFusion.plan_four(items, mode, target_kind)
	if not bool(plan.get("ok", false)):
		return plan
	var cost := int(plan.get("cost", 0))
	if gold < cost:
		return {"ok": false, "reason": "金币不足：需要 %d 金币" % cost}
	var output_kind := String(plan.get("target_kind", ""))
	if mode == EquipmentFusion.GOLD_TO_PURPLE:
		var kinds := Equipment.slot_kinds()
		output_kind = kinds[(rng.randi_range(0, kinds.size() - 1) if rng != null else randi_range(0, kinds.size() - 1))]
	var output := EquipmentFusion.make_output(int(plan.tier), output_kind, rng)
	if output.is_empty():
		return {"ok": false, "reason": "目标装备生成失败，未消耗材料"}
	if mode == EquipmentFusion.STAR_TRANSFER:
		output.star = Upgrade.max_star()
	if not SaveManager._valid_item(output):
		return {"ok": false, "reason": "目标装备校验失败，未消耗材料"}
	var output_index := indices[0]
	for index in indices:
		inventory[index] = null
	inventory[output_index] = output
	if cost > 0:
		add_gold(-cost)
	EventBus.inventory_changed.emit()
	EventBus.trade_done.emit("forge", String(output.get("itemId", "")), cost)
	return {"ok": true, "item": output, "index": output_index, "cost": cost, "reason": ""}

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

# ---- 装备重铸（M10-8）----

## 重铸一件装备的全部词条。`source` = "bag" / "worn"，`key` 是背包下标或装备槽 id
## （与 `upgrade_equipment` 同构）；`expected_id` 防止选择后背包整理导致错误实例被扣费。
##
## 🔑 **先掷后扣**：`ItemFactory.reroll_affixes` 是纯函数、不改 item、无副作用，掷成功才扣钱。
## 于是「扣了钱没重铸」这条错误路径根本不存在 —— 比「先扣、失败再退款」少一条分支。
## 品质 / 星级 / 基底 / instanceId 一律不动，只写回 `affixes` / `pctAttrs`（无需改存档 schema）。
func reforge_equipment(source: String, key: Variant, expected_id: String,
		rng: RandomNumberGenerator = null) -> Dictionary:
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
		return _reforge_fail(Localization.tr_key("msg.game_state.p032"))
	var guard := Reforge.can_reforge(item)
	if not bool(guard.get("ok", false)):
		return _reforge_fail(String(guard.get("reason", Localization.tr_key("msg.reforge.p003"))))
	var price := Reforge.cost(Equipment.level_req(item))
	if price <= 0:
		return _reforge_fail(Localization.tr_key("msg.reforge.p004"))
	if gold < price:
		return _reforge_fail(Localization.tr_key("msg.game_state.p037") % [price, gold])
	var rolled := ItemFactory.reroll_affixes(item, rng)
	if not bool(rolled.get("ok", false)):
		return _reforge_fail(Localization.tr_key("msg.reforge.p003"))
	var unchanged := ItemUtil.affix_lines(item) == ItemUtil.affix_lines({
		"affixes": rolled.affixes, "pctAttrs": rolled.pctAttrs,
	})
	add_gold(-price)
	item["affixes"] = rolled.affixes
	item["pctAttrs"] = rolled.pctAttrs
	if source == "worn":
		EventBus.equipment_changed.emit()
		EventBus.player_hp_changed.emit(int(player.hp), max_hp())
		EventBus.player_mp_changed.emit(int(player.mp), max_mp())
	else:
		EventBus.inventory_changed.emit()
	var message := Localization.tr_key("msg.reforge.p005") % [ItemUtil.display_name(item), price]
	EventBus.toast_requested.emit(message, "pickup")
	return {"ok": true, "cost": price, "affixes": rolled.affixes, "pctAttrs": rolled.pctAttrs,
		"unchanged": unchanged, "reason": message}

func _reforge_fail(reason: String) -> Dictionary:
	EventBus.toast_requested.emit(reason, "danger")
	return {"ok": false, "cost": 0, "unchanged": false, "reason": reason}

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
	_evict_unclaimed_overflow()
	return uid

## 未领取战利品总件数（跨全部地图）。
func unclaimed_total() -> int:
	var n := 0
	for map_id in unclaimed_loot.keys():
		n += (unclaimed_loot[map_id] as Array).size()
	return n

## uid 中的登记序号（`u_<ticks>_<seq>`）；无法解析时回退为大值（视为最新，最后才淘汰）。
func _unclaimed_seq_of(uid: String) -> int:
	var parts := uid.split("_")
	if parts.size() >= 3 and parts[2].is_valid_int():
		return int(parts[2])
	return 1 << 62

## 本图未领取上限（M10-3 / P-9 / D-13）：读 `maps.json` 的 `unclaimedLootCap`，
## 未配置 → `UNCLAIMED_LOOT_CAP`（普通图 20）。循环图配 200。
func unclaimed_loot_cap(map_id: String) -> int:
	var m: Variant = DataLoader.get_entry("maps", map_id)
	if m is Dictionary and (m as Dictionary).has("unclaimedLootCap"):
		return maxi(1, int((m as Dictionary).get("unclaimedLootCap", UNCLAIMED_LOOT_CAP)))
	return UNCLAIMED_LOOT_CAP

## 超出**本图**上限时按 FIFO（登记顺序）丢弃该图最旧记录，并广播 `unclaimed_loot_evicted`
## 令仍在场的对应地面物销毁。返回被丢弃的 uid 列表。
## M10-3：由「跨全部地图总数」改为逐图判定 —— 否则在循环图刷一轮就会把别的图的记录挤掉。
func _evict_unclaimed_overflow() -> Array:
	var evicted: Array = []
	var evicted_map: Array = []
	for map_id in unclaimed_loot.keys():
		var rows: Array = unclaimed_loot[map_id]
		var cap := unclaimed_loot_cap(String(map_id))
		while rows.size() > cap:
			var oldest_index := -1
			var oldest_seq := 1 << 62
			for i in range(rows.size()):
				var seq := _unclaimed_seq_of(String((rows[i] as Dictionary).get("uid", "")))
				if seq < oldest_seq:
					oldest_seq = seq
					oldest_index = i
			if oldest_index < 0:
				break
			var uid := String((rows[oldest_index] as Dictionary).get("uid", ""))
			# 无 uid 或注销失败时中断，避免死循环（防御异常数据）。
			if uid.is_empty() or not remove_unclaimed_loot(uid):
				break
			evicted.append(uid)
			evicted_map.append(String(map_id))
	for i in range(evicted.size()):
		var map_id := String(evicted_map[i])
		push_warning("[GameState] 地图 %s 的未领取战利品超上限(%d)，丢弃最旧记录：%s"
			% [map_id, unclaimed_loot_cap(map_id), evicted[i]])
		EventBus.unclaimed_loot_evicted.emit(String(evicted[i]))
	return evicted

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
	# 防御旧档：读入后若超出上限，先裁剪再供场景重建。
	_evict_unclaimed_overflow()

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

## 常驻浮窗面板（F-P3-1）：四者可彼此并开，其余面板打开时它们统一关闭。
const FLOATING_PANEL_IDS := ["inventory", "character", "skill", "mount"]
## NPC 会话面板：打开期间暂停自动战斗挂机（普通可并开的信息面板不影响自动决策）。
const NPC_DIALOG_PANEL_IDS := ["shop", "quest", "carter", "blacksmith", "warehouse", "upgrade", "reforge", "equipment_fusion"]
## 真正接管键盘的流程面板；普通信息与 NPC 面板可在操作角色时保持打开。
const WORLD_INPUT_BLOCKING_PANEL_IDS := ["menu", "settings", "save", "death", "equipment_confirm"]

## 登记 / 注销一个已打开的面板；panel_open 只描述可见状态，不再代表世界输入禁用。
## 多面板互斥由各面板订阅 EventBus.panel_opened 自行关闭实现（I 背包 / E 货郎），
## 但「可并开集合」只在本文件声明（见 panels_coexist），面板侧仅查询、不自带名单（F-P3-1）。
func set_panel_open(panel_id: String, open: bool) -> void:
	if open:
		_open_panels[panel_id] = true
	else:
		_open_panels.erase(panel_id)
	panel_open = not _open_panels.is_empty()

## 判断是否有模态流程或正在编辑的文字接管键盘；供角色、世界和快捷栏共用。
## 面板遮住的鼠标区域仍由 GUI 命中处理，不靠本判据把整张地图封住。
func world_controls_blocked() -> bool:
	for panel_id in WORLD_INPUT_BLOCKING_PANEL_IDS:
		if _open_panels.has(panel_id):
			return true
	var focus := get_viewport().gui_get_focus_owner()
	return focus != null and focus.is_visible_in_tree() and (focus is LineEdit or focus is TextEdit)

## 面板互斥查询（F-P3-1）：`opened_id` 打开时，本面板 `self_id` 是否应保持打开。
## 仅「同一面板」或「同属常驻浮窗组」可并开；货郎交易会话中的背包例外由背包 / 货郎面板自身处理。
func panels_coexist(opened_id: String, self_id: String) -> bool:
	if opened_id == self_id:
		return true
	if (opened_id == "equipment_fusion" and self_id == "inventory") \
			or (opened_id == "inventory" and self_id == "equipment_fusion"):
		return true
	return opened_id in FLOATING_PANEL_IDS and self_id in FLOATING_PANEL_IDS

## 仅 NPC 会话暂停挂机。
func npc_dialog_open() -> bool:
	for panel_id in NPC_DIALOG_PANEL_IDS:
		if _open_panels.has(panel_id):
			return true
	return false

# ---- 货郎交易（6.4；算价与物品构造见 scripts/systems/shop.gd）----

## 同步交易托盘暂存件数（E-P3-4）。调用点：ShopPanel 的托盘变更与退回出口。
func set_trade_staged_count(count: int) -> void:
	trade_staged_count = maxi(0, count)

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
	# E-P3-1：预检与提交同为同步逻辑，单线程下不会失败；一旦将来插入 await（异步入包动画）
	# 便可能「扣钱不给货」，此处显式校验并退还金币，不静默。
	if not add_item(item):
		add_gold(price)
		return _trade_fail(Localization.tr_key("msg.game_state.p049"))
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p050") % [ItemUtil.display_name(item), price], "pickup")
	EventBus.trade_done.emit("buy", item_id, price)
	return {"ok": true, "reason": "", "item": item, "price": price}

## 出售背包中指定格的装备（6.4：货郎只收购装备）。返回 {ok, reason, item, price}。
## silent = true 时不广播单件 toast（供面板批量出售后自行汇总，避免刷屏）。
## 金币容量不足时不扣物；成功返回的 price 与实际入账同值。
func shop_sell(inv_index: int, silent: bool = false) -> Dictionary:
	if inv_index < 0 or inv_index >= inventory.size() or inventory[inv_index] == null:
		return _trade_fail(Localization.tr_key("msg.game_state.p026"))
	var item: Dictionary = inventory[inv_index]
	if not Shop.can_sell(item):
		return _trade_fail(Localization.tr_key("msg.game_state.p051"))
	var price := Shop.sell_price(item)
	if price > GOLD_CAP - gold:
		return _trade_fail("金币已接近上限，请减少待售物品")
	var label := ItemUtil.display_name(item)
	remove_item_at(inv_index)
	var gained := add_gold(price)
	if not silent:
		EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p052") % [label, gained], "pickup")
	EventBus.trade_done.emit("sell", String(item.get("itemId", "")), gained)
	return {"ok": true, "reason": "", "item": item, "price": gained}

## 结算一批暂存待售的装备（6.4「确认出售」）。托盘内容由出售界面持有，本函数只做算价与入账。
## 返回 {ok, count, gold, reason}；空托盘、不可售物或金币上限失败时不结算。
func shop_sell_staged(items: Array) -> Dictionary:
	var total := 0
	var n := 0
	for it in items:
		if not it is Dictionary or not Shop.can_sell(it):
			return {"ok": false, "count": 0, "gold": 0, "reason": "托盘内存在不可出售的物品"}
		total += Shop.sell_price(it)
		n += 1
	if n == 0:
		return {"ok": false, "count": 0, "gold": 0, "reason": "出售托盘为空"}
	if total > GOLD_CAP - gold:
		return {"ok": false, "count": 0, "gold": 0, "reason": "金币已接近上限，请减少待售物品"}
	var gained := add_gold(total)
	EventBus.trade_done.emit("sell", "", gained)
	return {"ok": true, "count": n, "gold": gained, "reason": ""}

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
	# M10-0：等级护栏。`PLAYER_LEVEL_CAP` 同时是读档校验上界，若这里不拦，
	# 一旦越过（改档 / 极端经验注入）就会写出「自己读不回来」的存档（P-14）。
	# 到顶后经验照常累积、不再升级：不丢玩家的 xp，只是不再成长。
	while int(player.level) < PLAYER_LEVEL_CAP and int(player.xp) >= xp_to_next(int(player.level)):
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
	# M10-0：L ≤ 60 走逐级成长（与 4.4 逐位等价，见工程 40 §4.4 的证明）；
	# L > 60 抬到 `Balance` 曲线基线，与怪物同乘 S ⇒ 击杀次数恒定（产品 13 §2.3）。
	# 用 maxi 而非直接赋值，避免覆盖将来可能出现的其他基线来源。
	player.attack = maxi(int(player.attack) + 2, Balance.base_attack(int(player.level)))
	player.defense = maxi(int(player.defense) + 1, Balance.base_defense(int(player.level)))
	player.hp = int(round(float(max_hp()) * hp_ratio))
	player.mp = int(round(float(max_mp()) * mp_ratio))
	EventBus.player_leveled.emit(int(player.level))
	EventBus.player_hp_changed.emit(int(player.hp), max_hp())
	EventBus.player_mp_changed.emit(int(player.mp), max_mp())
	EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p053") % int(player.level), "levelup")

## M10-0：把基础攻防幂等抬到 `Balance` 曲线基线。用于读档后对齐「旧档（线性成长）」与「新档（曲线）」。
##
## 不写任何标记位 —— 曲线值只由等级决定，`maxi` 只升不降，可无限次重复执行；
## 也不能写 `unlocks` 标记（save_manager 会校验键必须在 `_known_unlock_ids` 内，自造键整档拒收）。
## 新游戏（`reset_to_defaults`）不走这里：L1 的曲线值就是初始值，无需对齐。
## ⚠ 调用前必须已恢复 `equipment` —— `max_hp()` 依赖装备加成，否则 HP 结转比例会算错。
func align_baseline_stats() -> void:
	var ratio := float(player.hp) / float(maxi(1, max_hp()))
	player.attack = maxi(int(player.attack), Balance.base_attack(int(player.level)))
	player.defense = maxi(int(player.defense), Balance.base_defense(int(player.level)))
	# HP 按比例结转而不是补满：读档时玩家可能正在残血，补满等于白送一次治疗。
	player.hp = clampi(int(round(float(max_hp()) * ratio)), 0, max_hp())

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
