extends Node
## 如意如意按钮的预选、置灰、手动改动和概率预览回归。

var failures: Array[String] = []

func _ready() -> void:
	GameState.reset_to_defaults()
	var panel := preload("res://scenes/ui/UpgradePanel.tscn").instantiate()
	add_child(panel)
	panel.set_open(true)
	_check(panel._auto_rune_button.disabled, "没有装备与如意时按钮置灰")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7031
	var weapon := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "legendary", rng)
	weapon.star = 1
	GameState.inventory[0] = weapon
	GameState.inventory[1] = {"kind": "rune", "itemId": "rune_iron", "count": 2}
	GameState.inventory[2] = {"kind": "rune", "itemId": "rune_iron", "count": 2}
	GameState.inventory[3] = {"kind": "rune", "itemId": "rune_diamond", "count": 4}
	EventBus.inventory_changed.emit()
	_check(not panel._auto_rune_button.disabled, "装备可升且有如意时按钮可用")
	var before := GameState.inventory.duplicate(true)
	panel._on_auto_runes()
	_check(panel._rune_choices == ["rune_iron", "rune_iron", "", ""]
		and panel._price.text.contains("100%") and panel._feedback.text.contains("100%")
		and GameState.inventory == before,
		"90% 自动放两铁并更新预览，但不消耗材料")
	_check(String(panel._rune_pickers[0].get_item_metadata(panel._rune_pickers[0].selected)) == "rune_iron",
		"自动预选同步四格下拉框")
	panel._rune_pickers[0].select(4)
	panel._rune_pickers[0].item_selected.emit(4)
	_check(panel._rune_choices[0] == "rune_diamond", "自动放入后仍可逐格手动修改")
	weapon.star = 8
	EventBus.inventory_changed.emit()
	panel._on_auto_runes()
	_check(panel._rune_choices == ["rune_diamond", "rune_diamond", "rune_diamond", "rune_diamond"]
		and panel._price.text.contains("100%"), "切换星级后再次点击按新成功率重选")
	GameState.gold = Upgrade.cost(8)
	GameState.inventory[3].count = 1
	EventBus.inventory_changed.emit()
	_check(panel._rune_choices == ["rune_diamond", "", "", ""]
		and not panel._upgrade_button.disabled and panel._price.text.contains("40%"),
		"库存只剩一枚时保留最早一格，自动清空超额预选并允许继续升星")
	weapon.star = 0
	EventBus.inventory_changed.emit()
	panel._on_auto_runes()
	_check(panel._rune_choices == ["", "", "", ""]
		and panel._feedback.text.contains("无需如意"), "基础已达 100% 时清空误选如意")
	GameState.inventory[1] = null
	GameState.inventory[2] = null
	GameState.inventory[3] = null
	EventBus.inventory_changed.emit()
	_check(panel._auto_rune_button.disabled, "没有如意时按钮置灰")
	GameState.inventory[1] = {"kind": "rune", "itemId": "rune_iron", "count": 1}
	weapon.star = Upgrade.max_star()
	EventBus.inventory_changed.emit()
	_check(panel._auto_rune_button.disabled, "满星装备即使有如意也不允许自动填充")
	# 实际结算吃完最后四枚后，下一次升星应直接使用空如意槽，不必关面板重开。
	GameState.reset_to_defaults()
	var last_weapon := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "legendary", rng)
	last_weapon.star = 8
	GameState.inventory[0] = last_weapon
	GameState.inventory[1] = {"kind": "rune", "itemId": "rune_diamond", "count": 4}
	GameState.gold = Upgrade.cost(8) + Upgrade.cost(9)
	EventBus.inventory_changed.emit()
	panel._on_auto_runes()
	panel._on_upgrade()
	_check(GameState.inventory[1] == null and panel._rune_choices == ["", "", "", ""]
		and panel._rune_pickers.all(func(picker: OptionButton) -> bool: return picker.selected == 0)
		and panel._auto_rune_button.disabled and not panel._upgrade_button.disabled,
		"消耗最后四枚如意后选项自动变空，升星仍可不放如意继续")
	var gold_before_second := GameState.gold
	panel._on_upgrade()
	_check(GameState.gold == gold_before_second - Upgrade.cost(9),
		"如意耗尽后可直接继续下一次升星")
	await get_tree().process_frame
	_check(panel._auto_rune_button.get_parent().get_combined_minimum_size().x <= 560.0,
		"双按钮操作行未超出升星面板的设计宽度")
	if failures.is_empty():
		print("[UpgradeAutoRuneUiTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
