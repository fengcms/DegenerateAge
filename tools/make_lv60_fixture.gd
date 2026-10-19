extends Node
## 生成「Lv60 全身史诗 +6」测试存档（写入槽 3），供 D-21「十级一套」与升星手感实机复验。
##
## 边界：只产出测试夹具 —— 不参与生产逻辑、不改任何数据表、不动槽 1 / 槽 2。
## 写入走 `SaveManager.save_slot`（同一套 `_is_valid_save` + 原子写 + 自动留 .bak），
## 所以产物与正常游玩存档在 schema / 字段上完全同源；若夹具本身非法，写盘会直接失败。
##
## 运行：
##   Godot --headless --path . --scene res://tools/make_lv60_fixture.tscn --quit-after 900

## 目标槽：3（当前是 Lv1 空档；主档在槽 2，旧档在槽 1，均不改动）。
const SLOT := 3
const LEVEL := 60
const STAR := 6
const SEED := 20261019
const GOLD := 1000000
## 装备取第 51 套（Lv51—60 十件对十槽位）—— 正好是 60 级能穿满的最高一套。
const TIER := 51

var problems: Array[String] = []
var expected_levels: Dictionary = {}

func _ready() -> void:
	SaveManager.autosave_enabled = false
	GameState.reset_to_defaults()
	_seed_player()
	GameState.equipment = _build_equipment()
	_finish_player()
	_fill_inventory()
	GameState.gold = GOLD
	GameState.current_map = "camp"
	GameState.visited_maps.clear()
	# 只开到「60 级能去的地方」：营地 + 第六章枢纽 + 无尽回廊（61+ 循环图）。
	for map_id in ["camp", "c6_map00", "c7_arena"]:
		GameState.visited_maps.append(map_id)
	# c7_arena 的 requiresUnlock = campaign_complete；该键由主线终章 reward.unlocks 产出，在合法白名单内。
	GameState.unlocks = {"campaign_complete": true}
	_place_at_camp_center()
	_report()
	if not problems.is_empty():
		_fail("生成阶段发现问题，已放弃写盘")
		return
	if not SaveManager.save_slot(SLOT, true, false):
		_fail("SaveManager.save_slot 拒绝写入（字段级原因见上方日志）")
		return
	_verify_roundtrip()

# ---- 角色 ----

## Lv60 基线：攻 130 / 防 64（Balance 曲线锚点，与 1—60 逐级 +2 / +1 一致）。
func _seed_player() -> void:
	GameState.player.level = LEVEL
	GameState.player.xp = 0
	GameState.player.attack = Balance.base_attack(LEVEL)
	GameState.player.defense = Balance.base_defense(LEVEL)
	GameState.player.name = "测试·Lv60"

## 装备就位后再派生 HP / MP，保证落档数值与读档后 `max_hp()` / `max_mp()` 一致。
func _finish_player() -> void:
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()

# ---- 装备 ----

## 按部位找第 51 套型号（tierBases 只有 "51" 一个键）。
## 不硬编码 id：型号表若改名，这里会直接报缺件而不是造出半身装备。
func _template_for_kind(kind: String) -> Dictionary:
	var rows: Variant = DataLoader.get_table("equipments")
	if not rows is Array:
		return {}
	for row in (rows as Array):
		if not row is Dictionary:
			continue
		var entry: Dictionary = row
		if String(entry.get("slot", "")) != kind:
			continue
		var bases: Variant = entry.get("tierBases", {})
		if bases is Dictionary and (bases as Dictionary).size() == 1 and (bases as Dictionary).has(str(TIER)):
			return entry
	return {}

func _build_equipment() -> Dictionary:
	var slots := Equipment.create()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for definition in Equipment.SLOT_DEFS:
		var kind := String((definition as Dictionary).get("kind", ""))
		var slot_id := String((definition as Dictionary).get("id", ""))
		var template := _template_for_kind(kind)
		if template.is_empty():
			problems.append("缺少部位 %s 的第 %d 套型号" % [kind, TIER])
			continue
		var item_id := String(template.get("id", ""))
		var item := ItemFactory.make_equip_roll(item_id, TIER, "epic", rng, "fixture")
		if item.is_empty():
			problems.append("生成失败：%s" % item_id)
			continue
		item["star"] = STAR
		slots[slot_id] = item
		expected_levels[slot_id] = int(template.get("requiredLevel", 0))
	return slots

func _fill_inventory() -> void:
	var inv: Array = Inventory.create(GameState.INVENTORY_SIZE)
	var supplies := [
		{"kind": "potion", "itemId": "potion_hp_large", "count": 99},
		{"kind": "potion", "itemId": "potion_mp_large", "count": 99},
		{"kind": "misc", "itemId": "misc_revive_scroll", "count": 20},
		{"kind": "misc", "itemId": "misc_town_scroll", "count": 20},
		{"kind": "misc", "itemId": "misc_random_ticket", "count": 10},
	]
	for index in range(supplies.size()):
		inv[index] = supplies[index]
	GameState.inventory = inv

func _place_at_camp_center() -> void:
	var camp: Variant = DataLoader.get_entry("maps", "camp")
	var size: Dictionary = {}
	if camp is Dictionary:
		var raw: Variant = (camp as Dictionary).get("size", {})
		if raw is Dictionary:
			size = raw
	var center := Iso.grid_to_world(Vector2i(int(size.get("w", 40)) / 2, int(size.get("h", 40)) / 2))
	GameState.save_pos = center
	GameState.has_save_pos = true

# ---- 自检与报告 ----

func _report() -> void:
	print("[Fixture] 角色：Lv%d，基础攻 %d / 防 %d，金币 %d" % [LEVEL, GameState.player.attack, GameState.player.defense, GOLD])
	for definition in Equipment.SLOT_DEFS:
		var slot_id := String((definition as Dictionary).get("id", ""))
		var label := Equipment.slot_label(slot_id)
		var item: Variant = GameState.equipment.get(slot_id)
		if not item is Dictionary:
			problems.append("槽 %s 为空" % slot_id)
			continue
		var worn: Dictionary = item
		var expected := int(expected_levels.get(slot_id, 0))
		if String(worn.get("quality", "")) != "epic":
			problems.append("槽 %s 品质不是 epic" % slot_id)
		if int(worn.get("star", 0)) != STAR:
			problems.append("槽 %s 星级不是 +%d" % [slot_id, STAR])
		if int(worn.get("requiredLevel", 0)) != expected or expected > LEVEL:
			problems.append("槽 %s 等级 %d 不符（期望 %d，角色 %d）" % [slot_id, int(worn.get("requiredLevel", 0)), expected, LEVEL])
		print("[Fixture] %-6s %-18s Lv%-3d %s +%d  词条 %d 条  评分 %.1f" % [
			label, String(worn.get("itemId", "")), int(worn.get("requiredLevel", 0)),
			String(worn.get("quality", "")), int(worn.get("star", 0)),
			(worn.get("affixes", []) as Array).size() + (worn.get("pctAttrs", []) as Array).size(),
			Equipment.score(worn)])
	print("[Fixture] 总计：攻 %d / 防 %d / HP %d / MP %d / 暴击 %.0f%% / CDR %.0f%%" % [
		GameState.total_attack(), GameState.total_defense(), GameState.max_hp(), GameState.max_mp(),
		float(GameState.player.criticalChance) * 100.0, GameState.total_cdr() * 100.0])

## 写完立刻按真实读档路径读回：槽号、等级、14 槽、品质、星级、等级逐项对齐。
func _verify_roundtrip() -> void:
	var res := SaveManager.read_slot(SLOT)
	if not bool(res.get("ok", false)):
		_fail("读回失败：%s" % String(res.get("message", "")))
		return
	var data: Dictionary = res.get("data", {})
	var player: Dictionary = data.get("player", {})
	if int(player.get("level", 0)) != LEVEL:
		problems.append("读回等级 %d ≠ %d" % [int(player.get("level", 0)), LEVEL])
	if int(player.get("hp", 0)) <= 0 or int(player.get("mp", 0)) <= 0:
		problems.append("读回 HP/MP 非正数")
	var worn: Dictionary = data.get("equipment", {})
	var epic_count := 0
	var star_count := 0
	var levels: Array = []
	for slot_id in worn.keys():
		var item: Variant = worn[slot_id]
		if not item is Dictionary:
			continue
		var entry: Dictionary = item
		if String(entry.get("quality", "")) == "epic":
			epic_count += 1
		if int(entry.get("star", 0)) == STAR:
			star_count += 1
		levels.append(int(entry.get("requiredLevel", 0)))
	levels.sort()
	if epic_count != Equipment.SLOT_DEFS.size():
		problems.append("读回史诗件数 %d ≠ %d" % [epic_count, Equipment.SLOT_DEFS.size()])
	if star_count != Equipment.SLOT_DEFS.size():
		problems.append("读回 +%d 件数 %d ≠ %d" % [STAR, star_count, Equipment.SLOT_DEFS.size()])
	print("[Fixture] 读回校验：Lv%d，史诗 %d 件，+%d %d 件，等级表 %s" % [
		int(player.get("level", 0)), epic_count, STAR, star_count, str(levels)])
	if not problems.is_empty():
		_fail("读回校验未通过")
		return
	print("[Fixture] 已写入槽 %d（source=%s），可以进游戏复验 ✅" % [SLOT, String(res.get("source", ""))])
	get_tree().quit(0)

func _fail(message: String) -> void:
	for problem in problems:
		push_error("[Fixture] " + problem)
	print("[Fixture] 失败：%s" % message)
	get_tree().quit(1)
