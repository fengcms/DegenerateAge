extends Node
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func make_item(id: String, seed_value: int = 901, level: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return ItemFactory.make_equip_exact(id, level, "legendary", rng) if level > 60 else ItemFactory.make_equip_roll(id, ItemFactory.tier_start_for_template(id), "legendary", rng)

func count(item: Dictionary) -> int:
	return item.affixes.size() + item.pctAttrs.size()

func _ready() -> void:
	check(DataLoader.validate_all().is_empty(), "正式配置合法")
	var rng := RandomNumberGenerator.new()
	rng.seed = 8733
	for tpl in DataLoader.get_table("equipments"):
		var item := make_item(tpl.id)
		check(count(item) == 4, "新生成仍4条")
		item.star = 12
		check(ReforgeAffixes.current_count(item) == 4 and ReforgeAffixes.target_count(item) == 5, "当前与目标数量分离")
		item.reforgeAffixTier = 1
		for i in range(32):
			var rolled := ItemFactory.reroll_affixes(item, rng)
			check(rolled.ok and rolled.affixes.size() == 4 and rolled.pctAttrs.size() == 1, "所有模板五条组成")
			var stats := {}
			for entry in rolled.affixes + rolled.pctAttrs:
				stats[entry.stat] = true
			check(stats.size() == 5, "五条stat唯一")
		item.merge(rolled_item(item, rng), true)
		var locks: Array = [item.affixes[0].stat, item.affixes[1].stat, item.affixes[2].stat, item.pctAttrs[0].stat]
		var preserved := ItemFactory.reroll_affixes(item, rng, locks, 0.6)
		for entry in item.affixes + item.pctAttrs:
			if locks.has(entry.stat):
				check((preserved.affixes + preserved.pctAttrs).has(entry), "四锁精确保留")
	_test_business(rng)
	if failures.is_empty():
		print("[FullStarReforgeTest] 全部通过 ✅")
	get_tree().quit(0 if failures.is_empty() else 1)

func rolled_item(item: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	return ItemFactory.reroll_affixes(item, rng)

func _test_business(rng: RandomNumberGenerator) -> void:
	GameState.reset_to_defaults()
	var item := make_item("c6_equip_weapon", 910, 100)
	item.star = 11
	GameState.inventory[0] = item
	GameState.gold = 10000000
	var low := GameState.reforge_equipment("bag", 0, item.instanceId, rng)
	check(low.ok and count(item) == 4 and not ReforgeAffixes.unlocked(item), "低星重铸仍四条")
	item.star = 12
	check(count(item) == 4 and not ReforgeAffixes.unlocked(item), "到12星不自动解锁")
	GameState.gold = 0
	var before := item.duplicate(true)
	check(not GameState.reforge_equipment("bag", 0, item.instanceId, rng).ok and item == before, "金币不足不解锁")
	GameState.gold = 10000000
	var first := GameState.reforge_equipment("bag", 0, item.instanceId, rng)
	check(first.ok and first.unlocked_fifth and count(item) == 5 and ReforgeAffixes.unlocked(item), "成功重铸原子解锁")
	check(Reforge.can_reforge(item).ok and Reforge.max_lock_count(item) == 4, "五条合法且可锁四条")
	var locked: Array = []
	for entry in item.affixes:
		locked.append(entry.stat)
	var fixed: Array = item.affixes.duplicate(true)
	GameState.inventory[1] = ItemFactory.make_any("rune_diamond", 4)
	var second := GameState.reforge_equipment("bag", 0, item.instanceId, rng, locked, [], 1.0,
		["rune_diamond", "rune_diamond", "rune_diamond", "rune_diamond"])
	check(second.ok and not second.unlocked_fifth and second.tries == 17 and count(item) == 5 and item.affixes == fixed, "四锁17次取优保持五条")
	check(GameState.inventory[1] == null, "如意只扣一次")
	check(SaveManager._valid_item(item), "五条实例可存档")
	for field in ["star", "quality", "reforgeAffixTier"]:
		var bad := item.duplicate(true)
		bad[field] = 11 if field == "star" else ("epic" if field == "quality" else 2)
		check(not SaveManager._valid_item(bad), "拒绝非法五条 " + field)
	var no_mark := item.duplicate(true)
	no_mark.erase("reforgeAffixTier")
	check(not SaveManager._valid_item(no_mark), "无标记五条拒绝")
	GameState.warehouse[0] = item.duplicate(true)
	var doc := SaveManager._collect()
	doc.slotId = 1
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(doc))
	check(SaveManager._is_valid_save(decoded), "五条JSON存档校验")
	SaveManager.apply_to_game_state(decoded)
	check(count(GameState.inventory[0]) == 5 and ReforgeAffixes.unlocked(GameState.warehouse[0]), "背包仓库往返保留解锁")
	var old := SaveManager._collect()
	old.slotId = 1
	old.schemaVersion = 15
	old.inventory[0] = make_item("c6_equip_weapon", 911, 100)
	old.inventory[0].star = 12
	old.warehouse[0] = null
	var old_item: Dictionary = old.inventory[0].duplicate(true)
	SaveManager.apply_to_game_state(old)
	check(GameState.inventory[0] == old_item and count(GameState.inventory[0]) == 4, "旧15档满星保持四条")
	# 保星生成新实例，不能继承旧装备的解锁资格。
	GameState.reset_to_defaults()
	GameState.gold = 10000000
	var old_gear := make_item("c6_equip_weapon", 912, 100)
	old_gear.star = 12
	old_gear.reforgeAffixTier = 1
	old_gear.merge(ItemFactory.reroll_affixes(old_gear, rng), true)
	old_gear.erase("ok")
	var new_gear := make_item("c6_equip_weapon", 913, 110)
	GameState.inventory[0] = old_gear
	GameState.inventory[1] = new_gear
	var selected: Array[Dictionary] = [old_gear.duplicate(true), new_gear.duplicate(true)]
	var transfer := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, selected, "", rng)
	check(transfer.ok and GameState.inventory[0].star == 12 and count(GameState.inventory[0]) == 4 and not ReforgeAffixes.unlocked(GameState.inventory[0]), "保星新产物12星四条")
	GameState.reset_to_defaults()
