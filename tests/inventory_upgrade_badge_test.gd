extends Node

var failures: Array[String] = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 10
	var candidate := ItemFactory.make_equip_roll("shoes_cloth", 1, "common", rng)
	GameState.player.level = 1
	GameState.equipment = Equipment.create()
	GameState.inventory[0] = candidate
	var panel := preload("res://scripts/ui/inventory_panel.gd").new()
	add_child(panel)
	check(panel._bag_buttons[0].upgrade_badge, "空槽可穿且评分增加时显示箭头")
	GameState.player.level = 0
	panel._refresh()
	check(not panel._bag_buttons[0].upgrade_badge, "等级不足时隐藏箭头")
	GameState.player.level = 1
	GameState.equipment.shoes = candidate.duplicate(true)
	panel._refresh()
	check(not panel._bag_buttons[0].upgrade_badge, "同分装备不显示箭头")
	GameState.inventory[0] = null
	panel._refresh()
	check(not panel._bag_buttons[0].upgrade_badge, "物品移走后清除箭头")
	if failures.is_empty():
		print("[InventoryUpgradeBadgeTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
