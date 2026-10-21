extends Node
## 工程 81：重铸词条锁定（保留满意词条，只重掷其余）—— 12 组用例。
##
## 四条最值钱的断言：
## 1. **用例 1 钉死「空锁定逐字节同结果」** —— `_roll_affixes` 的随机数调用顺序被
##    `ReforgeTest` 用例 14 的 20 行固定种子快照锁死；锁定功能一旦挪动 rng 调用，
##    1—60 级全部掉落漂移且零报错，只有这条 + 那 20 行快照能发现。
## 2. **用例 3 钉死「锁定 stat 必须从候选池剔除」** —— 否则掷出两条同 stat，而
##    `Equipment.bonus()` 按 stat 累加 ⇒ **静默叠加、零报错**，玩家只看到「锁的那条变了」。
## 3. **用例 4 钉死「百分比锁定跳过 randf() 判定」** —— 不跳就是 50% 概率整条消失，
##    间歇性发作最难查；必须跑满 20 轮才能暴露（单轮是假绿）。
## 4. **用例 8 钉死「费用按锁定数实扣」** —— 只断 `cost()` 返回值是**假绿**：
##    真正要断的是 `gold` 少了多少（负向 N-5 专门守这条）。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[ReforgeLockTest] " + label)

func _ready() -> void:
	_test_empty_lock_is_identical()
	_test_locked_entry_preserved()
	_test_no_duplicate_stat()
	_test_percent_lock_survives()
	_test_affix_count_preserved()
	_test_all_locked_rejected()
	_test_unknown_stat_rejected()
	_test_lock_price_charged()
	_test_lock_factor_wired()
	_test_worn_bonus_delta_matches_unlocked()
	_test_no_lock_in_save()
	_test_ui_lock_rows()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[ReforgeLockTest] 全部通过 ✅")
	else:
		for failure in failures:
			print("[ReforgeLockTest] 失败：" + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

# ---- 工具 ----

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

## 与 `ReforgeTest` 同规格：level > 60 走 `make_equip_exact`，否则挂模板所属套。
func _make(item_id: String, level: int, quality: String, seed_value: int) -> Dictionary:
	if level > Balance.SOFTCAP_LEVEL:
		return ItemFactory.make_equip_exact(item_id, level, quality, _rng(seed_value))
	return ItemFactory.make_equip_roll(item_id, ItemFactory.tier_start_for_template(item_id),
		quality, _rng(seed_value))

## 找一件**含指定 stat 词条**的实例（固定种子扫一遍，找不到就是数据变了）。
func _make_with(item_id: String, level: int, quality: String, stat: String,
		from_seed: int, want_percent: bool = false) -> Dictionary:
	for i in range(40):
		var item := _make(item_id, level, quality, from_seed + i)
		if item.is_empty():
			continue
		var arr: Variant = item.get("pctAttrs" if want_percent else "affixes", [])
		if arr is Array and _has_stat(arr as Array, stat):
			return item
	return {}

func _has_stat(entries: Array, stat: String) -> bool:
	for e in entries:
		if e is Dictionary and String((e as Dictionary).get("stat", "")) == stat:
			return true
	return false

## 从结果里取某 stat 的数值；没有返回 `null`（用 Variant 区分「值为 0」与「不存在」）。
func _value_of(item: Dictionary, stat: String) -> Variant:
	for key in ["affixes", "pctAttrs"]:
		var arr: Variant = item.get(key, [])
		if not arr is Array:
			continue
		for e in arr as Array:
			if e is Dictionary and String((e as Dictionary).get("stat", "")) == stat:
				return (e as Dictionary).get("value", 0)
	return null

func _stat_list(item: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in ["affixes", "pctAttrs"]:
		var arr: Variant = item.get(key, [])
		if not arr is Array:
			continue
		for e in arr as Array:
			if e is Dictionary:
				out.append(String((e as Dictionary).get("stat", "")))
	return out

# ---- 1) 空锁定必须与「不传锁定」逐条相同（随机数红线）----

func _test_empty_lock_is_identical() -> void:
	for i in range(6):
		var seed_value := 500 + i
		var a := _make("c6_equip_necklace", 60, "legendary", seed_value)
		var b := _make("c6_equip_necklace", 60, "legendary", seed_value)
		var plain := ItemFactory.reroll_affixes(a, _rng(seed_value))
		var empty := ItemFactory.reroll_affixes(b, _rng(seed_value), [])
		check(bool(plain.get("ok", false)) and bool(empty.get("ok", false)),
			"第 %d 组两种调用都应成功" % i)
		check(str(plain.get("affixes", [])) == str(empty.get("affixes", [])),
			"空锁定与不传锁定的固定词条必须逐条相同（第 %d 组）" % i)
		check(str(plain.get("pctAttrs", [])) == str(empty.get("pctAttrs", [])),
			"空锁定与不传锁定的百分比词条必须逐条相同（第 %d 组）" % i)

# ---- 2) 锁定条目连数值一起保留 ----

func _test_locked_entry_preserved() -> void:
	var item := _make_with("c6_equip_necklace", 60, "legendary", "hp", 601)
	check(not item.is_empty(), "应能造出带 hp 词条的传说装备")
	var locked_value: Variant = _value_of(item, "hp")
	for i in range(30):
		var rolled := ItemFactory.reroll_affixes(item, _rng(700 + i), ["hp"])
		if not bool(rolled.get("ok", false)):
			check(false, "第 %d 轮带锁定重掷应成功" % i)
			continue
		var merged: Dictionary = item.duplicate(true)
		merged["affixes"] = rolled.get("affixes", [])
		merged["pctAttrs"] = rolled.get("pctAttrs", [])
		var got: Variant = _value_of(merged, "hp")
		check(got != null, "第 %d 轮锁定的 hp 必须还在（不该被重掷掉）" % i)
		if got != null:
			check(is_equal_approx(float(got), float(locked_value)),
				"第 %d 轮锁定的 hp 数值必须恒为 %s，实际 %s" % [i, locked_value, got])

# ---- 3) 结果里不得出现重复 stat（锁定的必须从候选池剔除）----

func _test_no_duplicate_stat() -> void:
	var item := _make_with("c6_equip_necklace", 60, "legendary", "hp", 801)
	check(not item.is_empty(), "应能造出带 hp 词条的传说装备")
	for i in range(30):
		var rolled := ItemFactory.reroll_affixes(item, _rng(900 + i), ["hp"])
		if not bool(rolled.get("ok", false)):
			check(false, "第 %d 轮带锁定重掷应成功" % i)
			continue
		var merged: Dictionary = item.duplicate(true)
		merged["affixes"] = rolled.get("affixes", [])
		merged["pctAttrs"] = rolled.get("pctAttrs", [])
		var seen: Array[String] = []
		var duplicated := ""
		for stat in _stat_list(merged):
			if seen.has(stat):
				duplicated = stat
			seen.append(stat)
		check(duplicated.is_empty(),
			"第 %d 轮出现重复词条 %s（锁定 stat 未从候选池剔除即红）" % [i, duplicated])

# ---- 4) 锁定百分比词条：必须跳过 randf() 判定，20 轮一条都不能丢 ----

func _test_percent_lock_survives() -> void:
	var item := _make_with("c6_equip_necklace", 60, "legendary", "hpPercent", 1001, true)
	check(not item.is_empty(), "应能造出带 hpPercent 词条的传说装备（扫 40 个种子）")
	if item.is_empty():
		return
	var locked_value: Variant = _value_of(item, "hpPercent")
	for i in range(20):
		var rolled := ItemFactory.reroll_affixes(item, _rng(1100 + i), ["hpPercent"])
		if not bool(rolled.get("ok", false)):
			check(false, "第 %d 轮带百分比锁定重掷应成功" % i)
			continue
		var merged: Dictionary = item.duplicate(true)
		merged["affixes"] = rolled.get("affixes", [])
		merged["pctAttrs"] = rolled.get("pctAttrs", [])
		var got: Variant = _value_of(merged, "hpPercent")
		check(got != null,
			"第 %d 轮锁定的 hpPercent 消失了（没跳过 randf 判定即红）" % i)
		if got != null:
			check(is_equal_approx(float(got), float(locked_value)),
				"第 %d 轮锁定的 hpPercent 数值必须恒为 %s，实际 %s" % [i, locked_value, got])
		# 🔴 只查「hpPercent 还在」抓不住「又多掷了一条百分比」：不跳过 randf 判定时，
		# `percent` 先装锁定条目、再追加一条新掷的 —— 总数依旧守恒（固定词条少掷一条），
		# 条数断言照样绿。必须断「百分比最多 1 条」+「hpPercent 恰好 1 条」。
		var pct_count := (merged.get("pctAttrs", []) as Array).size()
		check(pct_count <= 1,
			"第 %d 轮百分比词条最多 1 条，实际 %d（锁定后仍走 randf 判定即红）" % [i, pct_count])
		var occurrences := 0
		for stat in _stat_list(merged):
			if stat == "hpPercent":
				occurrences += 1
		check(occurrences == 1, "第 %d 轮 hpPercent 应恰好 1 条，实际 %d" % [i, occurrences])

# ---- 5) 条数守恒：五品质各锁到上限再掷，条数仍等于 affixCount ----

func _test_affix_count_preserved() -> void:
	var counts := {"uncommon": 1, "rare": 2, "epic": 3, "legendary": 4}
	for quality in counts:
		var expected := int(counts[quality])
		var item := _make("c6_equip_necklace", 60, String(quality), 1201)
		var limit := Reforge.max_lock_count(item)
		check(limit == expected - 1, "%s 的可锁上限应为 %d，实际 %d" % [quality, expected - 1, limit])
		if limit <= 0:
			continue
		var locked: Array[String] = []
		for stat in _stat_list(item):
			if locked.size() >= limit:
				break
			locked.append(stat)
		for i in range(8):
			var rolled := ItemFactory.reroll_affixes(item, _rng(1300 + i), locked)
			if not bool(rolled.get("ok", false)):
				check(false, "%s 第 %d 轮带锁定重掷应成功" % [quality, i])
				continue
			var total: int = (rolled.get("affixes", []) as Array).size() \
				+ (rolled.get("pctAttrs", []) as Array).size()
			check(total == expected,
				"%s 锁定 %d 条后词条总数应仍为 %d，第 %d 轮为 %d" % [quality, locked.size(), expected, i, total])

# ---- 6) 全锁必须拒绝：不扣钱、词条不变 ----

func _test_all_locked_rejected() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	var item := _make("c6_equip_necklace", 60, "legendary", 1401)
	GameState.inventory[0] = item
	var locked := _stat_list(item)
	check(locked.size() == 4, "传说装备应有 4 条词条，实际 %d" % locked.size())
	var before: Dictionary = item.duplicate(true)
	var res := GameState.reforge_equipment("bag", 0, String(item.get("instanceId", "")),
		_rng(9), locked)
	check(not bool(res.get("ok", false)), "锁满全部词条应被拒绝（否则是花钱买「没变化」）")
	check(String(res.get("reason", "")).contains("锁定"),
		"拒绝原因应指向锁定，实际「%s」" % String(res.get("reason", "")))
	check(GameState.gold == 1000000, "拒绝时不得扣费，实际 %d" % GameState.gold)
	check(str(GameState.inventory[0]) == str(before), "拒绝时词条必须逐键未变")

# ---- 7) 锁定不存在的 stat：拒绝，不静默丢弃 ----

func _test_unknown_stat_rejected() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	var item := _make("c6_equip_necklace", 60, "legendary", 1501)
	GameState.inventory[0] = item
	# 从池里挑一个**不在**这件装备上的 stat 当探针。
	var probe := ""
	for stat in ["atk", "def", "hp", "mp", "hpPercent", "mpPercent", "cdr"]:
		if not _stat_list(item).has(stat):
			probe = stat
			break
	check(not probe.is_empty(), "应能找到一个不在该装备上的属性做探针")
	var before: Dictionary = item.duplicate(true)
	var res := GameState.reforge_equipment("bag", 0, String(item.get("instanceId", "")),
		_rng(10), [probe])
	check(not bool(res.get("ok", false)),
		"锁定不在装备上的 %s 应被拒绝（静默丢弃会让玩家以为锁住了）" % probe)
	check(GameState.gold == 1000000, "拒绝时不得扣费，实际 %d" % GameState.gold)
	check(str(GameState.inventory[0]) == str(before), "拒绝时词条必须逐键未变")

# ---- 8) 费用随锁定数上涨，且**实扣**等于加价后的价 ----

func _test_lock_price_charged() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	var item := _make("c6_equip_necklace", 60, "legendary", 1601)
	GameState.inventory[0] = item
	var base := Reforge.cost(60)
	check(base == 52500, "L60 无锁定费用应为 52,500，实际 %d" % base)
	var one := Reforge.cost(60, 1)
	var two := Reforge.cost(60, 2)
	check(one == 78750, "L60 锁 1 条应为 78,750，实际 %d" % one)
	check(two == 105000, "L60 锁 2 条应为 105,000，实际 %d" % two)
	var gold_before := GameState.gold
	var res := GameState.reforge_equipment("bag", 0, String(item.get("instanceId", "")),
		_rng(11), ["hp"])
	check(bool(res.get("ok", false)), "锁 1 条应能重铸：%s" % String(res.get("reason", "")))
	# 🔴 有牙的判据：断**金币实扣**，不是断返回值（只改 cost() 不改扣费是假绿）。
	check(GameState.gold == gold_before - one,
		"锁 1 条应实扣 %d，实际扣了 %d" % [one, gold_before - GameState.gold])
	check(int(res.get("cost", 0)) == one, "返回的 cost 应为 %d，实际 %d" % [one, int(res.get("cost", 0))])
	check(int(res.get("locked", 0)) == 1, "返回的 locked 应为 1，实际 %d" % int(res.get("locked", 0)))

# ---- 9) lockFactor 必须真接线 ----

func _test_lock_factor_wired() -> void:
	var cfg: Dictionary = DataLoader.get_table("endgame")
	var reforge: Dictionary = cfg.get("reforge", {})
	var original: Variant = reforge.get("lockFactor", 0)
	reforge["lockFactor"] = 1.0
	check(Reforge.cost(60, 1) == 105000, "lockFactor=1.0 时锁 1 条应为 105,000，实际 %d" % Reforge.cost(60, 1))
	reforge["lockFactor"] = 0.0
	check(Reforge.cost(60, 2) == 52500, "lockFactor=0 时锁 2 条应仍为 52,500，实际 %d" % Reforge.cost(60, 2))
	reforge["lockFactor"] = original
	check(Reforge.cost(60, 1) == 78750, "还原后锁 1 条应回到 78,750，实际 %d" % Reforge.cost(60, 1))

# ---- 10) 已穿戴：属性变化只来自未锁定的词条 ----

func _test_worn_bonus_delta_matches_unlocked() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	var item := _make_with("c6_equip_necklace", 60, "legendary", "hp", 1701)
	check(not item.is_empty(), "应能造出带 hp 词条的传说装备")
	GameState.equipment["necklace"] = item
	var locked_hp: Variant = _value_of(item, "hp")
	var before_bonus := Equipment.bonus(GameState.equipment)
	var res := GameState.reforge_equipment("worn", "necklace", String(item.get("instanceId", "")),
		_rng(12), ["hp"])
	check(bool(res.get("ok", false)), "已穿戴装备带锁定重铸应成功：%s" % String(res.get("reason", "")))
	check(is_equal_approx(float(_value_of(item, "hp")), float(locked_hp)),
		"锁定后 hp 词条必须原样保留")
	var after_bonus := Equipment.bonus(GameState.equipment)
	# hp 锁定 ⇒它对 bonus 的贡献不变；总变化量 = 其余词条的 hp 差值（本例其余无 hp ⇒ 0）。
	var other_hp := 0.0
	for e in item.get("affixes", []):
		if e is Dictionary and String((e as Dictionary).get("stat", "")) == "hp":
			other_hp += float((e as Dictionary).get("value", 0))
	check(is_equal_approx(float(after_bonus.get("hp", 0.0)) - float(before_bonus.get("hp", 0.0)),
			other_hp - float(locked_hp)),
		"hp 的加成变化应等于未锁定部分的差值")

# ---- 11) 锁定不落档：装备实例上不出现 lock 键，存档仍有效 ----

func _test_no_lock_in_save() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	var item := _make("c6_equip_necklace", 60, "legendary", 1801)
	GameState.inventory[0] = item
	var res := GameState.reforge_equipment("bag", 0, String(item.get("instanceId", "")),
		_rng(13), ["hp"])
	check(bool(res.get("ok", false)), "带锁定重铸应成功")
	var after: Dictionary = GameState.inventory[0]
	for key in ["locked", "lockedStats", "lockedAffixes", "lockFactor"]:
		check(not after.has(key), "装备实例上不得出现 %s（锁定不落档 ⇒ schema 不动）" % key)
	check(SaveManager._is_valid_save(SaveManager._collect()), "锁定重铸后存档仍应有效")

# ---- 12) UI：锁按钮数 == 词条数；锁定后价格与按钮文案跟着变；到上限后余下的置灰 ----

func _test_ui_lock_rows() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	var item := _make("c6_equip_necklace", 60, "legendary", 1901)
	GameState.inventory[0] = item
	# 第二件只作「切换装备」用：验证锁定是**按装备**记的，换一件即清空（§2.6）。
	GameState.inventory[1] = _make("c6_equip_weapon", 60, "rare", 1902)
	var panel: Control = (load("res://scenes/ui/ReforgePanel.tscn") as PackedScene).instantiate()
	add_child(panel)
	panel.set_open(true)
	var buttons: Array[Button] = panel.lock_buttons()
	check(buttons.size() == 4, "传说装备应有 4 个锁按钮，实际 %d" % buttons.size())
	if buttons.size() != 4:
		panel.set_open(false)
		panel.queue_free()
		return
	var price_before: String = String(panel._price.text)
	panel.toggle_lock("hp")
	check(panel.locked_stats() == ["hp"], "点锁后应锁定 hp，实际 %s" % str(panel.locked_stats()))
	var price_after: String = String(panel._price.text)
	check(price_after != price_before, "锁定后价格文案应变化（「%s」→「%s」）" % [price_before, price_after])
	check(price_after.contains("1"), "价格文案应带上锁定条数：%s" % price_after)
	check(String(panel._button.text).contains("1"), "按钮文案应带上锁定条数：%s" % String(panel._button.text))
	# 锁到上限（传说 3 条）后，第 4 个按钮必须置灰，且按钮本身仍可用。
	var stats := _stat_list(item)
	for stat in stats:
		if panel.locked_stats().size() >= 3:
			break
		panel.toggle_lock(stat)
	check(panel.locked_stats().size() == 3, "传说装备最多锁 3 条，实际 %d" % panel.locked_stats().size())
	var disabled_full := 0
	for button in panel.lock_buttons():
		if not button.button_pressed and button.disabled:
			disabled_full += 1
	check(disabled_full >= 1, "锁到上限后未锁的按钮应置灰，实际置灰 %d 个" % disabled_full)
	check(not bool(panel._button.disabled), "锁 3 条（上限内）时重铸按钮应可用")
	# 再手动塞满 4 条 ⇒ 校验拒绝，按钮变灰且 tooltip 说明原因。
	panel.toggle_lock("atk")
	panel.toggle_lock("def")
	panel.toggle_lock("mp")
	if panel.locked_stats().size() >= 4:
		check(bool(panel._button.disabled), "锁满 4 条后重铸按钮应禁用")
		check(String(panel._button.tooltip_text).contains("锁定"),
			"禁用时的 tooltip 应说明锁定原因，实际「%s」" % String(panel._button.tooltip_text))
	# 换一件装备 ⇒ 锁定清空（锁定属于「这一件」，不跟着面板走到下一件上）。
	panel._picker.select(1)
	# headless 下 OptionButton.select 不保证发信号，显式走一次选中处理（等价用户点击）。
	panel._on_selected(panel._picker.selected)
	check(panel._picker.selected == 1, "应能切到第二件装备")
	check(panel.locked_stats().is_empty(),
		"切换装备后锁定应清空，实际 %s" % str(panel.locked_stats()))
	check(panel.lock_buttons().size() == 2, "稀有装备应有 2 个锁按钮，实际 %d" % panel.lock_buttons().size())
	panel.set_open(false)
	check(panel.locked_stats().is_empty(), "关面板后锁定应清空（不落档）")
	panel.queue_free()
