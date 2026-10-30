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
	if failures.is_empty():
		print("[FullStarReforgeTest] 全部通过 ✅")
	get_tree().quit(0 if failures.is_empty() else 1)

func rolled_item(item: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	return ItemFactory.reroll_affixes(item, rng)
