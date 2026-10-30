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
	var bad_rules: Dictionary = ItemFactory.rules().duplicate(true)
	bad_rules.qualities.legendary.affixCount = 3
	check(not ReforgeAffixes.validate_config(bad_rules, DataLoader.get_table("equipments")).is_empty(), "配置拒绝非四条基础紫装")
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
	await _test_ui()
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
	var upgrade_rng := RandomNumberGenerator.new()
	for seed_value in range(10000):
		upgrade_rng.seed = seed_value
		if upgrade_rng.randf() * 100.0 < Upgrade.success_rate(11):
			upgrade_rng.seed = seed_value
			break
	var upgraded := GameState.upgrade_equipment("bag", 0, item.instanceId, upgrade_rng)
	check(upgraded.ok and item.star == 12 and count(item) == 4 and not ReforgeAffixes.unlocked(item), "真实升12星不自动解锁")
	GameState.gold = 0
	var before := item.duplicate(true)
	check(not GameState.reforge_equipment("bag", 0, item.instanceId, rng).ok and item == before, "金币不足不解锁")
	GameState.gold = 10000000
	var gold_before := GameState.gold
	GameState.inventory[1] = ItemFactory.make_any("rune_diamond", 3)
	var missing_runes := GameState.reforge_equipment("bag", 0, item.instanceId, rng, [], [], 1.0,
		["rune_diamond", "rune_diamond", "rune_diamond", "rune_diamond"])
	check(not missing_runes.ok and item == before and GameState.gold == gold_before and GameState.inventory[1].count == 3, "首次解锁如意不足不扣资源")
	check(not GameState.reforge_equipment("bag", 0, item.instanceId, rng, [], ["missing_material"]).ok and item == before and GameState.gold == gold_before, "精炼材料失效不解锁")
	var all_stats: Array = []
	for entry in item.affixes + item.pctAttrs:
		all_stats.append(entry.stat)
	check(not GameState.reforge_equipment("bag", 0, item.instanceId, rng, all_stats).ok and item == before, "首次不能锁全部四条")
	var first_locks := all_stats.slice(0, 3)
	var preserved_before: Array = (item.affixes + item.pctAttrs).duplicate(true)
	var first := GameState.reforge_equipment("bag", 0, item.instanceId, rng, first_locks)
	for entry in preserved_before:
		if first_locks.has(entry.stat):
			check((item.affixes + item.pctAttrs).has(entry), "首次解锁保留三锁原值")
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
	var malformed := item.duplicate(true)
	malformed.affixes.append(malformed.affixes[0].duplicate())
	check(not SaveManager._valid_item(malformed), "拒绝六条")
	malformed = item.duplicate(true)
	malformed.affixes[1].stat = malformed.affixes[0].stat
	check(not SaveManager._valid_item(malformed), "拒绝重复stat")
	malformed = item.duplicate(true)
	malformed.pctAttrs.append(malformed.pctAttrs[0].duplicate())
	malformed.affixes.pop_back()
	check(not SaveManager._valid_item(malformed), "拒绝两个百分比")
	malformed = item.duplicate(true)
	malformed.affixes.pop_back()
	check(not SaveManager._valid_item(malformed), "拒绝标记五条却只有四条")
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
	GameState.gold = 10000000
	var worn := make_item("weapon_iron", 914)
	worn.star = 12
	GameState.equipment.weapon = worn
	var worn_result := GameState.reforge_equipment("worn", "weapon", worn.instanceId, rng)
	check(worn_result.ok and count(GameState.equipment.weapon) == 5 and ItemUtil.affix_lines(worn).size() == 5, "穿戴装备同步解锁五条")
	GameState.reset_to_defaults()

func _test_ui() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 10000000
	var item := make_item("c6_equip_weapon", 944, 100)
	item.star = 12
	GameState.inventory[0] = item
	var ui := CanvasLayer.new()
	add_child(ui)
	var panel := preload("res://scenes/ui/ReforgePanel.tscn").instantiate()
	ui.add_child(panel)
	panel.set_open(true)
	check(panel._lock_hint.text.contains("解锁第5条") and panel._affix_title.text.contains("4 条"), "首次解锁预告")
	panel._button.pressed.emit()
	check(count(item) == 5 and panel._affix_rows.get_child_count() == 5, "真实按钮解锁并显示五行")
	check(panel._feedback.text.contains("已解锁第五词条") and panel._affix_title.text.contains("最多锁定 4"), "解锁反馈与锁数同步")
	check(ItemUtil.affix_lines(item).size() == 5 and ItemUtil.attr_lines(item).has(Localization.tr_key("ui.item.fifth_unlocked")), "通用词条与tooltip显示五条资格")
	for entry in item.affixes:
		panel._on_lock_toggled(entry.stat)
	check(panel._locked.size() == 4 and not panel._button.disabled, "界面允许锁四条")
	var last_row: Node = panel._affix_rows.get_child(4)
	check(last_row.get_child(1).disabled, "第五条不能同时锁定")
	if DisplayServer.get_name() != "headless":
		for spec in [[Vector2i(1280, 800), 1.0], [Vector2i(960, 720), 1.0], [Vector2i(1280, 800), 1.5]]:
			DisplayServer.window_set_size(spec[0])
			GameState.settings.uiScale = spec[1]
			GameState.settings.textScale = spec[1]
			SettingsRuntime.apply_ui_scale_to(ui)
			SettingsRuntime.apply_text_scale_to(ui)
			panel._resize()
			panel._scroll.scroll_vertical = 0
			for _i in range(16):
				await get_tree().process_frame
			var box: Control = panel._box
			var rect := Rect2(box.get_global_transform_with_canvas().origin, box.size * float(spec[1]))
			check(get_viewport().get_visible_rect().grow(1).encloses(rect), "五词条面板不越界 " + str(spec))
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/tmp/fifth_reforge_%d_%d.png" % [spec[0].x, int(float(spec[1]) * 100)])
			panel._scroll.scroll_vertical = int(panel._scroll.get_v_scroll_bar().max_value)
			for _i in range(8):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/tmp/fifth_reforge_bottom_%d_%d.png" % [spec[0].x, int(float(spec[1]) * 100)])
	panel.queue_free()
	ui.queue_free()
	GameState.reset_to_defaults()
