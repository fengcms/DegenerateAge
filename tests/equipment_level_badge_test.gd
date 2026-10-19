extends Node
## 装备穿戴等级角标回归：核对实例等级、空格复用、装备槽继承、拖拽副本与缩放布局。
## 仅在隔离测试项目中创建 UI，不读取或写入玩家正式存档。

var _failures: Array[String] = []

## 使用真实动态装备检查可见数字，并确保非装备与错误等级清除旧角标。
func _ready() -> void:
	GameState.reset_to_defaults()
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var weapon_61 := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "rare", rng)
	var weapon_71 := ItemFactory.make_equip_dynamic("c6_equip_weapon", 71, "rare", rng)
	var helmet_64 := ItemFactory.make_equip_dynamic("c6_equip_helmet", 64, "rare", rng)
	_check(not weapon_61.is_empty() and not weapon_71.is_empty() and not helmet_64.is_empty(), "真实动态装备实例可生成")
	var bag := ItemSlot.new()
	bag.role = ItemSlot.ROLE_BAG
	bag.apply_grid_base(Vector2(52, 52))
	add_child(bag)
	bag.size = Vector2(52, 52)
	bag.item = weapon_61
	_check(bag._level_badge.visible and bag._level_badge_text == "61", "背包角标读取实例 61 级")
	bag.item = weapon_71
	_check(bag._level_badge_text == "71", "复用同一装备素材时显示新实例等级")
	bag.item = helmet_64
	_check(bag._level_badge_text == "64", "同档其他部位显示其穿戴等级 64")
	var worn := EquipmentSlot.new()
	worn.role = ItemSlot.ROLE_EQUIP
	worn.slot_id = "helmet"
	worn.custom_minimum_size = Vector2(52, 52)
	add_child(worn)
	worn.size = Vector2(52, 52)
	worn.item = helmet_64
	_check(worn._level_badge.visible and worn._level_badge_text == "64", "人物装备槽继承相同角标")
	var ghost := DragGhost.slot_copy(bag)
	add_child(ghost)
	ghost.size = Vector2(52, 52)
	_check(ghost._level_badge.visible and ghost._level_badge_text == "64", "拖拽副本保留等级角标")
	_check(bag._level_badge.mouse_filter == Control.MOUSE_FILTER_IGNORE, "角标不抢鼠标和拖放事件")
	var high := helmet_64.duplicate(true)
	high.requiredLevel = 9999
	bag.item = high
	for scales in [[1.0, 1.0], [1.5, 1.5], [2.0, 2.0], [1.0, 2.0]]:
		GameState.settings.uiScale = scales[0]
		GameState.settings.textScale = scales[1]
		EventBus.settings_changed.emit()
		var layout := bag._level_badge_layout()
		var rect: Rect2 = layout.get("rect", Rect2())
		_check(bag._level_badge_text == "9999" and rect.position.x >= 0.0 and rect.position.y >= 0.0
			and rect.end.x <= bag.size.x and rect.end.y <= bag.size.y,
			"四位数在界面/文字倍率 %s 内完整留在格子里" % str(scales))
	bag.item = {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	_check(not bag._level_badge.visible and bag._level_badge_text.is_empty() and bag._count.text == "3",
		"药品保留数量角标且无等级数字")
	bag.item = {"kind": "equip", "requiredLevel": "无效"}
	_check(not bag._level_badge.visible, "非法等级不显示虚假的 1 级")
	bag.item = {}
	_check(not bag._level_badge.visible and bag._level_badge_text.is_empty(), "清空格子后不残留旧数字")
	GameState.reset_to_defaults()
	if _failures.is_empty():
		print("[EquipmentLevelBadgeTest] 全部通过 ✅")
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)

## 汇总失败项，确保单个错误不会掩盖后续的格子状态问题。
func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
