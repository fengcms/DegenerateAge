extends Control
## M4-6 设置：即时预览，写入当前存档；冲突键位经确认后交换。

const ACTION_NAMES := {
	"move_up": "向上移动", "move_down": "向下移动", "move_left": "向左移动", "move_right": "向右移动",
	"attack": "普通攻击", "target_next": "切换目标", "sit_toggle": "打坐 / 起身", "auto_battle": "自动战斗", "auto_pickup": "自动拾取",
	"interact": "交互", "pause": "关闭 / 暂停", "panel_inventory": "背包", "panel_character": "人物",
	"panel_map": "地图", "panel_skill": "技能", "panel_mount": "坐骑",
}

var _key_list: VBoxContainer
var _capture_action := ""
var _capture_label: Label
var _conflict: ConfirmationDialog
var _pending_action := ""
var _pending_code := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false
	EventBus.panel_opened.connect(_on_panel_opened)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		set_open(false)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if _capture_action.is_empty() or not event is InputEventKey or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	if key.physical_keycode == KEY_ESCAPE:
		_capture_action = ""
		_capture_label.text = "已取消改键"
		return
	if key.physical_keycode <= 0 or key.ctrl_pressed or key.alt_pressed or key.meta_pressed or key.shift_pressed:
		_capture_label.text = "请按单个普通按键；Esc 取消"
		return
	var action := _capture_action
	_capture_action = ""
	var conflict := SettingsRuntime.action_for_key(key.physical_keycode, action)
	if not conflict.is_empty():
		_pending_action = action
		_pending_code = key.physical_keycode
		_conflict.dialog_text = "%s 已用于「%s」。是否交换两个功能的按键？" % [OS.get_keycode_string(key.physical_keycode), _action_name(conflict)]
		_conflict.popup_centered()
		_capture_label.text = "等待确认键位交换"
	else:
		SettingsRuntime.set_binding(action, key.physical_keycode)
		_capture_label.text = "已设置「%s」" % _action_name(action)
		_refresh_keys()

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open("settings", open)
	if open:
		_refresh_keys()
		EventBus.panel_opened.emit("settings")
	else:
		_capture_action = ""

func _on_panel_opened(panel_id: String) -> void:
	if panel_id != "settings" and visible:
		set_open(false)

func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("11171d")
	style.border_color = Color("74818a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(650, 430)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "关闭 · Esc"
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	_build_audio(tabs)
	_build_visual(tabs)
	_build_game(tabs)
	_build_controls(tabs)
	_build_data(tabs)
	_conflict = ConfirmationDialog.new()
	_conflict.title = "按键冲突"
	_conflict.confirmed.connect(_confirm_swap)
	add_child(_conflict)

func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = title
	box.add_theme_constant_override("separation", 12)
	tabs.add_child(box)
	return box

func _slider(box: VBoxContainer, label: String, field: String, minimum: float, maximum: float, step: float) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var caption := Label.new()
	caption.text = label
	caption.custom_minimum_size.x = 160
	row.add_child(caption)
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 300
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = float(GameState.settings.get(field, minimum))
	row.add_child(slider)
	var value := Label.new()
	value.text = "%.0f%%" % (slider.value * 100.0) if maximum <= 1.0 else str(slider.value)
	row.add_child(value)
	slider.value_changed.connect(func(v: float) -> void:
		GameState.settings[field] = v
		value.text = "%.0f%%" % (v * 100.0) if maximum <= 1.0 else str(v)
		_changed())

func _checkbox(box: VBoxContainer, label: String, field: String) -> void:
	var check := CheckBox.new()
	check.text = label
	check.button_pressed = bool(GameState.settings.get(field, false))
	check.toggled.connect(func(v: bool) -> void:
		GameState.settings[field] = v
		_changed())
	box.add_child(check)

func _build_audio(tabs: TabContainer) -> void:
	var box := _tab(tabs, "音频")
	_slider(box, "音乐音量", "musicVolume", 0.0, 1.0, 0.05)
	_slider(box, "音效音量", "sfxVolume", 0.0, 1.0, 0.05)
	var hint := Label.new()
	hint.text = "音量应用于 Music / SFX 声道；当前版本尚无游戏内音乐资源。"
	box.add_child(hint)

func _build_visual(tabs: TabContainer) -> void:
	var box := _tab(tabs, "画面")
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := Label.new()
	label.text = "UI 缩放"
	label.custom_minimum_size.x = 160
	row.add_child(label)
	var scale := OptionButton.new()
	for pct in [80, 100, 120, 150]:
		scale.add_item("%d%%" % pct, pct)
		if is_equal_approx(float(GameState.settings.get("uiScale", 1.0)), float(pct) / 100.0):
			scale.select(scale.item_count - 1)
	scale.item_selected.connect(func(index: int) -> void:
		GameState.settings["uiScale"] = float(scale.get_item_id(index)) / 100.0
		_changed())
	row.add_child(scale)
	_slider(box, "文字缩放", "textScale", 0.8, 1.5, 0.1)
	_checkbox(box, "全屏显示", "fullscreen")
	var resolution := OptionButton.new()
	for entry in [{"id": "auto", "label": "自由窗口大小"}, {"id": "1280x800", "label": "1280×800"},
		{"id": "1440x900", "label": "1440×900"}, {"id": "1600x900", "label": "1600×900"}]:
		resolution.add_item(String(entry.label))
		resolution.set_item_metadata(resolution.item_count - 1, String(entry.id))
		if String(GameState.settings.get("resolution", "auto")) == String(entry.id):
			resolution.select(resolution.item_count - 1)
	resolution.item_selected.connect(func(index: int) -> void:
		GameState.settings["resolution"] = resolution.get_item_metadata(index)
		_changed())
	box.add_child(resolution)
	_checkbox(box, "屏幕震动", "screenShake")
	_checkbox(box, "强光闪烁", "strongFlash")
	var hint := Label.new()
	hint.text = "震动和闪烁开关已保存；对应战斗特效会在视觉阶段接入。"
	box.add_child(hint)

func _build_game(tabs: TabContainer) -> void:
	var box := _tab(tabs, "游戏")
	_slider(box, "自动喝药阈值", "potionThreshold", 0.1, 0.9, 0.05)
	_checkbox(box, "自动战斗允许 Boss", "allowBoss")
	_checkbox(box, "拾取飞行动画", "dropFlyAnim")
	var filter := OptionButton.new()
	for entry in [{"id": "all", "label": "拾取全部品质"}, {"id": "rare", "label": "稀有及以上"},
		{"id": "epic", "label": "史诗及以上"}, {"id": "legendary", "label": "仅传说"}]:
		filter.add_item(String(entry.label))
		filter.set_item_metadata(filter.item_count - 1, String(entry.id))
		if String(GameState.settings.get("qualityFilter", "all")) == String(entry.id):
			filter.select(filter.item_count - 1)
	filter.item_selected.connect(func(index: int) -> void:
		GameState.settings["qualityFilter"] = filter.get_item_metadata(index)
		_changed())
	box.add_child(filter)
	var hint := Label.new()
	hint.text = "品质筛选仅作后续自动拾取预设，当前掉落仍生成即入包。"
	box.add_child(hint)

func _build_controls(tabs: TabContainer) -> void:
	var root := _tab(tabs, "控制")
	_capture_label = Label.new()
	_capture_label.text = "点击右侧按键，再按新键；冲突时可交换。Esc 取消。"
	root.add_child(_capture_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_key_list = VBoxContainer.new()
	scroll.add_child(_key_list)
	_refresh_keys()

func _build_data(tabs: TabContainer) -> void:
	var box := _tab(tabs, "数据")
	var button := Button.new()
	button.text = "打开存档管理"
	button.pressed.connect(func() -> void:
		set_open(false)
		var save_panel := get_node("../SavePanel")
		save_panel.set_mode("manage")
		save_panel.set_open(true))
	box.add_child(button)
	var note := Label.new()
	note.text = "设置保存在当前活动存档槽；新游戏请先手动建立存档。"
	box.add_child(note)

func _refresh_keys() -> void:
	if _key_list == null:
		return
	for child in _key_list.get_children():
		child.queue_free()
	for action in SettingsRuntime.ACTIONS:
		var row := HBoxContainer.new()
		_key_list.add_child(row)
		var name := Label.new()
		name.text = _action_name(action)
		name.custom_minimum_size.x = 300
		row.add_child(name)
		var key := Button.new()
		key.custom_minimum_size.x = 140
		key.text = OS.get_keycode_string(SettingsRuntime.key_for(action))
		key.pressed.connect(_start_capture.bind(action))
		row.add_child(key)

func _action_name(action: String) -> String:
	if action.begins_with("hotbar_"):
		return "快捷格 %s" % action.trim_prefix("hotbar_")
	return String(ACTION_NAMES.get(action, action))

func _start_capture(action: String) -> void:
	_capture_action = action
	_capture_label.text = "正在设置「%s」：请按新键，Esc 取消" % _action_name(action)

func _confirm_swap() -> void:
	SettingsRuntime.set_binding(_pending_action, _pending_code)
	_capture_label.text = "已交换冲突按键"
	_pending_action = ""
	_pending_code = 0
	_refresh_keys()

func _changed() -> void:
	SettingsRuntime.apply_all()
	EventBus.settings_changed.emit()
