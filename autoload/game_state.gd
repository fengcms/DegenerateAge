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
var _open_panels: Dictionary = {}   # 已打开面板 id 集合（多面板互斥，见 set_panel_open）
var quest_states: Dictionary = {}   # quest_id -> state 字符串
var first_clear: Dictionary = {}    # boss_id -> bool（首通标记）
var settings: Dictionary = {}
## 自动战斗 / 自动拾取开关（M1-9，3.14）。**运行态开关，不写存档**
## （10.3：重启后自动战斗默认关闭）。决策机见 scripts/systems/auto_battle.gd。
var auto_battle_on: bool = false
var auto_pickup_on: bool = false

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
	_open_panels = {}
	quest_states = {}
	first_clear = {}
	auto_battle_on = false          # 10.3：重启后自动战斗默认关闭
	auto_pickup_on = false
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

# ---- 自动战斗 / 自动拾取开关（M1-9，3.14 / 4.6）----

## 设置自动战斗开关（F 键）。返回新状态。决策机订阅本信号以重置锚点。
func set_auto_battle(on: bool) -> bool:
	if auto_battle_on == on:
		return auto_battle_on
	auto_battle_on = on
	EventBus.auto_state_changed.emit(auto_battle_on, auto_pickup_on)
	var msg := "自动战斗：开" if on else "自动战斗：关"
	if on and auto_pickup_on:
		msg += "（自动拾取已开）"
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
		"自动拾取：开（自动战斗时顺路拾取）" if on else "自动拾取：关", "info")
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

# ---- 货郎交易（6.4；算价与物品构造见 scripts/systems/shop.gd）----

## 向货郎购买一件商品。返回 {ok, reason, item, price}。
## 失败原因明确广播提示（金币不足 / 背包满 / 不售此物），不静默。
func shop_buy(shop_id: String, item_id: String) -> Dictionary:
	var price := Shop.buy_price(shop_id, item_id)
	if price < 0:
		return _trade_fail("该货郎不出售此物")
	var item := Shop.make_item(item_id)
	if item.is_empty():
		return _trade_fail("物品不存在：%s" % item_id)
	if not Inventory.has_space_for(inventory, item):
		return _trade_fail("背包已满，无法购买")
	if gold < price:
		return _trade_fail("金币不足（需 %d，现有 %d）" % [price, gold])
	add_gold(-price)
	add_item(item)
	EventBus.toast_requested.emit("购买：%s（-%d 金币）" % [ItemUtil.display_name(item), price], "pickup")
	EventBus.trade_done.emit("buy", item_id, price)
	return {"ok": true, "reason": "", "item": item, "price": price}

## 出售背包中指定格的装备（6.4：货郎只收购装备）。返回 {ok, reason, item, price}。
## silent = true 时不广播单件 toast（供面板批量出售后自行汇总，避免刷屏）。
func shop_sell(inv_index: int, silent: bool = false) -> Dictionary:
	if inv_index < 0 or inv_index >= inventory.size() or inventory[inv_index] == null:
		return _trade_fail("该格没有物品")
	var item: Dictionary = inventory[inv_index]
	if not Shop.can_sell(item):
		return _trade_fail("货郎只收购装备")
	var price := Shop.sell_price(item)
	var label := ItemUtil.display_name(item)
	remove_item_at(inv_index)
	add_gold(price)
	if not silent:
		EventBus.toast_requested.emit("出售：%s（+%d 金币）" % [label, price], "pickup")
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
