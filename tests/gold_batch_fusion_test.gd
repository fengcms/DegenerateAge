extends Node
var failures: Array[String] = []
var events := 0
var rng := RandomNumberGenerator.new()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
func gear(tier: int, star: int = 0) -> Dictionary:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", tier, "epic", rng)
	item.star = star
	return item
func seed_bag(tiers: Array) -> void:
	GameState.reset_to_defaults()
	for i in range(tiers.size()):
		GameState.inventory[i] = gear(tiers[i])
func _ready() -> void:
	rng.seed = 3124
	for n in [0, 3, 4, 5, 7, 8]:
		var inputs: Array = []
		for i in range(n):
			inputs.append(gear(61))
		var plan := GoldBatchFusion.plan(inputs)
		check(plan.ok and plan.groups.size() == n / 4 and plan.remaining == n % 4, "件数边界 " + str(n))
	seed_bag([61, 71, 71, 71, 71, 71, 71, 71])
	var session := GameState.begin_gold_batch()
	var plan := GameState.preview_gold_batch(session.token)
	check(plan.ok and plan.outputs == {71: 1, 61: 1} and plan.mixed == 1 and plan.downgraded == 3, "同档先组再跨档余数")
	var first_id: String = plan.groups[0][0].instanceId
	var excluded := GameState.preview_gold_batch(session.token, false, [first_id])
	check(excluded.ok and excluded.groups.size() == 1 and excluded.remaining == 3, "排除后重新分组")
	GameState.pickup_loot(gear(81))
	GameState.organize_inventory()
	check(GameState.preview_gold_batch(session.token).groups == plan.groups, "拾取不扩大计划，整理不改变分组")
	EventBus.inventory_changed.connect(func() -> void: events += 1)
	events = 0
	var result := GameState.forge_gold_batch(session.token)
	check(result.ok and result.count == 2 and result.consumed == 8 and GameState.inventory_used() == 3 and events == 1, "一次提交只消耗冻结8件，保留新拾取")
	check(not GameState.forge_gold_batch(session.token).ok and events == 1, "成功会话不能重放")
	seed_bag([61, 61, 61, 61])
	GameState.inventory[0].star = 1
	session = GameState.begin_gold_batch()
	check(GameState.preview_gold_batch(session.token).groups.is_empty() and GameState.preview_gold_batch(session.token, true).groups.size() == 1, "默认保护带星，明确开启可合成")
	GameState.inventory[0].favorite = true
	var before := GameState.inventory.duplicate(true)
	check(not GameState.forge_gold_batch(session.token, true).ok and GameState.inventory == before, "收藏变更拒绝整批")
	GameState.inventory[0].favorite = false
	GameState.equipment.weapon = GameState.inventory[0]
	GameState.inventory[0] = null
	check(not GameState.forge_gold_batch(session.token, true).ok, "材料穿到身上后拒绝")
	seed_bag([61, 61, 61, 61])
	session = GameState.begin_gold_batch()
	var tpl: Dictionary = DataLoader.get_entry("equipments", "c6_equip_weapon")
	var bases: Dictionary = tpl.tierBases.duplicate(true)
	tpl.tierBases = {}
	before = GameState.inventory.duplicate(true)
	check(not GameState.forge_gold_batch(session.token).ok and GameState.inventory == before, "模板失效整批不消耗")
	tpl.tierBases = bases
	GameState.reset_to_defaults()
	GameState.inventory_expansions = Warehouse.max_expansions()
	GameState.inventory.resize(Warehouse.capacity(GameState.inventory_expansions))
	for i in range(400):
		GameState.inventory[i] = gear(61 + (i % 4) * 10)
	session = GameState.begin_gold_batch()
	var start := Time.get_ticks_usec()
	result = GameState.forge_gold_batch(session.token)
	print("[PERF] GoldBatch400 CPU us=" , Time.get_ticks_usec() - start)
	check(result.ok and result.count == 100 and GameState.inventory_used() == 100, "满400件产生100件")
	var ids := {}
	for item in result.get("items", []):
		ids[item.instanceId] = true
		check(SaveManager._valid_item(item) and item.quality == "legendary" and item.star == 0 and item.affixes.size() + item.pctAttrs.size() == 4 and not ReforgeAffixes.unlocked(item), "产物合法0星四条")
	check(ids.size() == 100, "产物ID唯一")
	var doc := SaveManager._collect()
	doc.slotId = 1
	check(SaveManager._is_valid_save(JSON.parse_string(JSON.stringify(doc))), "批量产物可保存")
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[GoldBatchFusionTest] 全部通过 ✅")
	get_tree().quit(0 if failures.is_empty() else 1)
