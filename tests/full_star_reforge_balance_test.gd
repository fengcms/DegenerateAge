extends Node
## 固定种子配对采样：无锁/无精炼/无如意，隔离第五词条自身影响。
const SAMPLES := 128
var failed := false

func _ready() -> void:
	var results: Array = []
	for level in [10, 60, 100, 1000]:
		for class_id in ["warrior", "mage"]:
			var changes := {"score": [], "atk": [], "def": [], "hp": [], "mp": [], "basic_ttk": []}
			var caps := [0, 0]
			var timings: Array = [0, 0]
			var timing_samples: Array = [[], []]
			for sample in range(SAMPLES):
				GameState.reset_to_defaults(class_id)
				GameState.player.level = level
				GameState.player.attack = Balance.base_attack(level)
				GameState.player.defense = Balance.base_defense(level)
				var before := Equipment.create()
				var after := Equipment.create()
				for slot in Equipment.SLOT_DEFS:
					var id := EquipmentFusion.template_for(1 if level == 10 else 51, String(slot.kind))
					var rng := RandomNumberGenerator.new()
					rng.seed = 731000 + sample * 31 + before.keys().find(slot.id)
					var item := ItemFactory.make_equip_exact(id, level, "legendary", rng) if level > 60 else ItemFactory.make_equip_roll(id, 1 if level == 10 else 51, "legendary", rng)
					item.star = 12
					var boosted := item.duplicate(true)
					boosted.reforgeAffixTier = 1
					var start := Time.get_ticks_usec()
					var rolled := ItemFactory.reroll_affixes(item, rng)
					var elapsed := Time.get_ticks_usec() - start
					timings[0] += elapsed
					timing_samples[0].append(elapsed)
					item.affixes = rolled.affixes
					item.pctAttrs = rolled.pctAttrs
					rng.seed = 941000 + sample * 31 + before.keys().find(slot.id)
					start = Time.get_ticks_usec()
					rolled = ItemFactory.reroll_affixes(boosted, rng)
					elapsed = Time.get_ticks_usec() - start
					timings[1] += elapsed
					timing_samples[1].append(elapsed)
					boosted.affixes = rolled.affixes
					boosted.pctAttrs = rolled.pctAttrs
					if not SaveManager._valid_item(boosted):
						failed = true
					before[slot.id] = item
					after[slot.id] = boosted
				var low := evaluate(before, level)
				var high := evaluate(after, level)
				for key in changes:
					changes[key].append(float(high[key]) / maxf(0.00001, float(low[key])) - 1.0)
				caps[0] += int(low.cdr >= 0.49999)
				caps[1] += int(high.cdr >= 0.49999)
			var row := {"level": level, "class": class_id, "samples": SAMPLES, "cdr_cap_before": caps[0], "cdr_cap_after": caps[1], "roll_mean_us_before": float(timings[0]) / (SAMPLES * 14), "roll_mean_us_after": float(timings[1]) / (SAMPLES * 14)}
			for key in changes:
				var values: Array = changes[key]
				values.sort()
				row[key] = {"p10": values[12], "p50": values[64], "p90": values[115]}
			for mode in range(2):
				var times: Array = timing_samples[mode]
				times.sort()
				row["roll_us_before" if mode == 0 else "roll_us_after"] = {"p50": times[times.size() / 2], "p95": times[int(times.size() * 0.95)], "p99": times[int(times.size() * 0.99)], "max": times.back()}
			results.append(row)
	var file := FileAccess.open("/tmp/full_star_reforge_balance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "  "))
	GameState.reset_to_defaults()
	if not failed:
		print("配对采样结果 /tmp/full_star_reforge_balance.json")
		print("[FullStarReforgeBalanceTest] 全部通过 ✅")
	get_tree().quit(1 if failed else 0)

func evaluate(gear: Dictionary, level: int) -> Dictionary:
	GameState.equipment = gear
	var norm := Endgame.norm("boss_corrupted_beast")
	var factor := Balance.scale(level - 60)
	var hp := 3000.0 if level == 10 else float(norm.hp) * factor
	var defense := 12.0 if level == 10 else float(norm.def) * factor
	var rng := RandomNumberGenerator.new()
	rng.seed = 2001
	var damage := 0.0
	var attack := GameState.total_attack()
	var crit_chance := GameState.total_crit_chance()
	var crit_mult := GameState.total_crit_multiplier()
	for _i in range(256):
		damage += float(Combat.resolve(attack, defense, 1.0, crit_chance, crit_mult, 0.0, rng).damage)
	var score := 0.0
	for item in gear.values():
		score += Equipment.score(item)
	return {"score": score, "atk": GameState.total_attack(), "def": GameState.total_defense(), "hp": GameState.max_hp(), "mp": GameState.max_mp(), "cdr": GameState.total_cdr(), "basic_ttk": hp / maxf(1.0, damage / 256.0) * GameState.total_attack_interval()}
