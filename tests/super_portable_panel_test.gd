extends Node

var _opened := ""

func _ready() -> void:
	EventBus.boss_token_panel_requested.connect(func(_title: String) -> void: _opened = "boss_token")
	EventBus.shop_open_requested.connect(func(_id: String) -> void: _opened = "shop")
	EventBus.blacksmith_panel_requested.connect(func(_name: String, _greeting: String, _portable: bool) -> void: _opened = "blacksmith")
	EventBus.carter_panel_requested.connect(func(_title: String, _portable: bool) -> void: _opened = "carter")
	EventBus.warehouse_panel_requested.connect(func(_title: String) -> void: _opened = "warehouse")
	var panel := Control.new()
	panel.set_script(load("res://scripts/ui/super_portable_panel.gd"))
	add_child(panel)
	await get_tree().process_frame
	for i in range(5):
		panel.set_open(true)
		_opened = ""
		var key := InputEventKey.new()
		key.physical_keycode = KEY_1 + i
		key.pressed = true
		Input.parse_input_event(key)
		await get_tree().process_frame
		if _opened != panel.SERVICES[i] or panel.visible:
			push_error("超级令牌快捷键 %d 未打开预期服务" % (i + 1))
			get_tree().quit(1)
			return
	_opened = ""
	var hidden_key := InputEventKey.new()
	hidden_key.physical_keycode = KEY_1
	hidden_key.pressed = true
	Input.parse_input_event(hidden_key)
	await get_tree().process_frame
	if not _opened.is_empty():
		get_tree().quit(1)
		return
	print("[SuperPortablePanelTest] 五项数字键及隐藏状态隔离通过")
	get_tree().quit()
