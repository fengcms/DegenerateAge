extends Node
## M4-8 拖放契约；不写玩家存档。

var _errors: Array[String] = []

func _ready() -> void:
	GameState.reset_to_defaults()
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	var inventory: Control = main.get_node("UI/InventoryPanel")
	var hud: Control = main.get_node("UI/Hud")
	GameState.inventory[0] = {"kind": "potion", "itemId": "potion_hp_small", "count": 4}
	GameState.inventory[1] = {"kind": "misc", "itemId": "misc_town_scroll", "count": 2}
	EventBus.inventory_changed.emit()
	inventory.set_open(true)
	_check(hud._hotbar.z_index == 100, "背包打开时快捷栏可接收拖放")
	for _i in range(3):
		await get_tree().process_frame
	var from: Vector2 = inventory._bag_buttons[0].get_global_rect().get_center()
	var to: Vector2 = hud._hotbar_buttons[7].get_global_rect().get_center()
	_send_move(from, Vector2.ZERO)
	await get_tree().process_frame
	_send_mouse(from, true)
	await get_tree().process_frame
	var previous := from
	for step in range(1, 9):
		var point: Vector2 = from.lerp(to, float(step) / 8.0)
		_send_move(point, point - previous)
		previous = point
		await get_tree().process_frame
	_send_mouse(to, false)
	await get_tree().process_frame
	_check(GameState.hotbar[7] is Dictionary and GameState.hotbar[7].id == "potion_hp_small",
		"真实鼠标拖拽从背包落到快捷格")
	inventory.set_open(false)
	var skills: Control = main.get_node("UI/SkillPanel")
	skills.set_open(true)
	for _i in range(2):
		await get_tree().process_frame
	var skill_button: Control = skills._list.get_child(0).get_child(0)
	from = skill_button.get_global_rect().get_center()
	to = hud._hotbar_buttons[8].get_global_rect().get_center()
	_send_move(from, Vector2.ZERO)
	await get_tree().process_frame
	_send_mouse(from, true)
	await get_tree().process_frame
	previous = from
	for step in range(1, 9):
		var point: Vector2 = from.lerp(to, float(step) / 8.0)
		_send_move(point, point - previous)
		previous = point
		await get_tree().process_frame
	_send_mouse(to, false)
	await get_tree().process_frame
	_check(GameState.hotbar[8] is Dictionary and GameState.hotbar[8].id == "basic_slash",
		"真实鼠标拖拽从技能面板落到快捷格")
	skills.set_open(false)
	inventory.set_open(true)
	var bag_slot: ItemSlot = inventory._bag_buttons[0]
	_check(bag_slot.draggable, "药品背包格可拖动")
	var payload: Variant = bag_slot._get_drag_data(Vector2.ZERO)
	var target: HotbarSlot = hud._hotbar_buttons[4]
	_check(target._can_drop_data(Vector2.ZERO, payload), "快捷格接受背包药品")
	target._drop_data(Vector2.ZERO, payload)
	_check(GameState.hotbar[4].id == "potion_hp_small" and GameState.inventory[0].count == 4,
		"拖入绑定模板而不取走背包物品")
	var town: ItemSlot = inventory._bag_buttons[1]
	_check(town.draggable, "回城卷可拖动")
	hud._hotbar_buttons[5]._drop_data(Vector2.ZERO, town._get_drag_data(Vector2.ZERO))
	_check(GameState.hotbar[5].id == "misc_town_scroll", "回城卷绑定成功")
	var source: HotbarSlot = hud._hotbar_buttons[4]
	target = hud._hotbar_buttons[5]
	target._drop_data(Vector2.ZERO, source._get_drag_data(Vector2.ZERO))
	_check(GameState.hotbar[4].id == "misc_town_scroll" and GameState.hotbar[5].id == "potion_hp_small", "两格拖放交换")
	hud._hotbar_buttons[6]._drop_data(Vector2.ZERO, {"kind": "hotbar_skill", "id": "basic_slash"})
	_check(GameState.hotbar[6].id == "basic_slash", "已接通技能可拖入")
	_check(hud._hotbar_buttons[6]._can_drop_data(Vector2.ZERO, {"kind": "hotbar_skill", "id": "earth_cleave"}),
		"裂地斩接通后可拖入")
	_check(hud._hotbar_buttons[6]._can_drop_data(Vector2.ZERO, {"kind": "hotbar_skill", "id": "whirlwind"}),
		"旋风斩接通后可拖入")
	_check(not hud._hotbar_buttons[6]._can_drop_data(Vector2.ZERO, {"kind": "hotbar_skill", "id": "battle_focus"}),
		"尚未接通技能不可拖入")
	var right := InputEventMouseButton.new()
	right.position = hud._hotbar_buttons[6].get_global_rect().get_center()
	right.global_position = right.position
	right.button_index = MOUSE_BUTTON_RIGHT
	right.button_mask = MOUSE_BUTTON_MASK_RIGHT
	right.pressed = true
	get_viewport().push_input(right, true)
	await get_tree().process_frame
	_check(GameState.hotbar[6] == null, "右键清空绑定")
	GameState.inventory[0] = null
	EventBus.inventory_changed.emit()
	_check(GameState.hotbar[5].id == "potion_hp_small" and is_equal_approx(hud._hotbar_buttons[5].modulate.a, 0.45),
		"药品耗尽绑定保留且置灰")
	GameState.inventory[8] = {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	EventBus.inventory_changed.emit()
	_check(hud._hotbar_buttons[5]._count.text == "3" and is_equal_approx(hud._hotbar_buttons[5].modulate.a, 1.0),
		"补货后显示数量并恢复可用")
	GameState.organize_inventory()
	_check(GameState.hotbar[5].id == "potion_hp_small" and hud._hotbar_buttons[5]._count.text == "3",
		"背包整理不破坏模板绑定")
	inventory.set_open(false)
	GameState.player.hp = GameState.max_hp() - 50
	hud._activate_hotbar(5)
	await get_tree().process_frame
	_check(GameState.player.hp == GameState.max_hp() and hud._hotbar_buttons[5]._count.text == "2",
		"拖入的具体药品可使用且库存同步减少")
	_check(not hud._hotbar_buttons[5]._cooldown.text.is_empty(), "药品格显示冷却")
	print("[HotbarUiTest] ", "全部通过 ✅" if _errors.is_empty() else str(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_errors.append(message)
		push_error("[HotbarUiTest] " + message)

func _send_mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	get_viewport().push_input(event, true)

func _send_move(point: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event, true)
