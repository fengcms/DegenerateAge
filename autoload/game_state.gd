extends Node
## GameState — 全局运行时状态（单例 / Autoload）。
##
## 持有角色、经济、进度、设置的运行时数据；启动时赋予初始参数
## （数值来源：docs/产品文档/04 角色成长系统 4.4 初始值）。
## 不持久化运行时节点对象——存档由 SaveManager 负责序列化这里的数据。

const SCHEMA_VERSION := 1

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
var inventory: Array = []           # 背包物品实例（40 格，见 Inventory / 5.8）
var quest_states: Dictionary = {}   # quest_id -> state 字符串
var first_clear: Dictionary = {}    # boss_id -> bool（首通标记）
var settings: Dictionary = {}

func _ready() -> void:
	reset_to_defaults()

## 重置为初始状态（新建角色 / 初始化时调用）。
func reset_to_defaults() -> void:
	player = {
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
	gold = 0
	current_map = "camp"
	inventory = Inventory.create(INVENTORY_SIZE)
	quest_states = {}
	first_clear = {}
	settings = {
		"autoBattleDefault": false,   # 10.3：重启后自动战斗默认关闭
		"autoPickupDefault": false,
		"potionThreshold": 0.35,      # 3.14 喝药血量阈值
		"searchRadius": 12,           # 3.14 搜索半径（格）
		"allowBoss": false,           # 3.14 自动战斗是否允许 Boss
		"masterVolume": 1.0,
		"sfxVolume": 1.0,
		"uiScale": 1.0,
	}

## 经验升级所需（4.4 公式：round(100 × L^1.6)）。
func xp_to_next(level: int) -> int:
	return int(round(100.0 * pow(float(level), 1.6)))

## 派生的最大生命（4.3 公式）。装备百分比 / 固定加成暂为 0（M4 接入）。
func max_hp() -> int:
	var base := BASE_HP + float(player.level) * HP_PER_LV \
		+ float(player.attack) * HP_PER_ATK + float(player.defense) * HP_PER_DEF
	var pct := float(player.get("hpPercent", 0.0))
	var flat := float(player.get("hpFlat", 0.0))
	return int(round(base * (1.0 + pct) + flat))

## 派生的最大法力（4.3 公式）。
func max_mp() -> int:
	var base := BASE_MP + float(player.level) * MP_PER_LV
	var pct := float(player.get("mpPercent", 0.0))
	var flat := float(player.get("mpFlat", 0.0))
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
	EventBus.toast_requested.emit("升级！Lv%d" % int(player.level), "levelup")

## 广播全部数值（HUD 初始化 / 读档后同步）。
func emit_all() -> void:
	EventBus.gold_changed.emit(gold)
	EventBus.player_leveled.emit(int(player.level))
	EventBus.player_hp_changed.emit(int(player.hp), max_hp())
	EventBus.player_mp_changed.emit(int(player.mp), max_mp())
	EventBus.player_xp_changed.emit(int(player.xp), xp_to_next(int(player.level)))
