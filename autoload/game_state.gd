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
var equipment: Dictionary = {}      # 已穿戴装备（槽 id → 实例，14 槽，见 Equipment / 5.1）
var panel_open: bool = false        # 是否有关闭式面板打开中（面板开启时屏蔽角色操控）
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
	equipment = Equipment.create()
	panel_open = false
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

# ---- 装备穿脱（5.1；槽位规则与属性汇总见 scripts/systems/equipment.gd）----

## 从背包穿上一件装备（slot_id 为空时自动选槽：优先同类空槽，否则替换）。
## 返回 {ok, reason, replaced}；失败广播原因（背包满 / 等级不足 / 槽位不匹配），不静默。
func equip_from_inventory(inv_index: int, slot_id: String = "") -> Dictionary:
	if inv_index < 0 or inv_index >= inventory.size() or inventory[inv_index] == null:
		return {"ok": false, "reason": "该格没有物品", "replaced": {}}
	var item: Dictionary = inventory[inv_index]
	var target := slot_id
	if target.is_empty():
		target = Equipment.auto_slot_for(equipment, item)
	var res := Equipment.equip_from_inventory(
		equipment, inventory, target, inv_index, int(player.level))
	if bool(res.get("ok", false)):
		_after_equip_change()
		EventBus.toast_requested.emit("穿戴：" + ItemUtil.display_name(item), "pickup")
	else:
		EventBus.toast_requested.emit(String(res.get("reason", "无法穿戴")), "danger")
	return res

## 卸下槽位装备（需背包空位，5.1）。返回 {ok, reason, item}。
func unequip_slot(slot_id: String) -> Dictionary:
	var res := Equipment.unequip(equipment, inventory, slot_id)
	if bool(res.get("ok", false)):
		var item: Dictionary = res.get("item", {})
		_after_equip_change()
		EventBus.toast_requested.emit("卸下：" + ItemUtil.display_name(item), "info")
	else:
		EventBus.toast_requested.emit(String(res.get("reason", "无法卸下")), "danger")
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
	EventBus.equipment_changed.emit()
	EventBus.inventory_changed.emit()
	EventBus.player_leveled.emit(int(player.level))
	EventBus.player_hp_changed.emit(int(player.hp), max_hp())
	EventBus.player_mp_changed.emit(int(player.mp), max_mp())
	EventBus.player_xp_changed.emit(int(player.xp), xp_to_next(int(player.level)))
