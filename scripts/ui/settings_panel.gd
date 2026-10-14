extends Control
## M4-6 设置：即时预览，写入当前存档；冲突键位经确认后交换。

const ACTION_NAMES := {
	"move_up": "ui.action.move_up", "move_down": "ui.action.move_down", "move_left": "ui.action.move_left", "move_right": "ui.action.move_right",
	"attack": "ui.action.attack", "target_next": "ui.action.target_next", "sit_toggle": "ui.action.sit_toggle", "auto_battle": "ui.action.auto_battle", "auto_pickup": "ui.action.auto_pickup",
	"interact": "ui.action.interact", "pause": "ui.action.pause", "panel_inventory": "ui.action.panel_inventory", "panel_character": "ui.action.panel_character",
	"panel_map": "ui.action.panel_map", "panel_skill": "ui.action.panel_skill", "panel_mount": "ui.action.panel_mount",
}

var _key_list: VBoxContainer
var _capture_action := ""
var _capture_label: Label
var _conflict: ConfirmationDialog
var _pending_action := ""
var _pending_code := 0
var _layout_root: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	get_viewport().size_changed.connect(_update_layout)
	_update_layout.call_deferred()
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
		_capture_label.text = Localization.tr_key("ui.settings_panel.p001")
		return
	if key.physical_keycode <= 0 or key.ctrl_pressed or key.alt_pressed or key.meta_pressed or key.shift_pressed:
		_capture_label.text = Localization.tr_key("ui.settings_panel.p002")
		return
	var action := _capture_action
	_capture_action = ""
	var conflict := SettingsRuntime.action_for_key(key.physical_keycode, action)
	if not conflict.is_empty():
		_pending_action = action
		_pending_code = key.physical_keycode
		_conflict.dialog_text = Localization.tr_key("ui.settings_panel.p003") % [OS.get_keycode_string(key.physical_keycode), _action_name(conflict)]
		_conflict.popup_centered()
		_capture_label.text = Localization.tr_key("ui.settings_panel.p004")
	else:
		SettingsRuntime.set_binding(action, key.physical_keycode)
		_capture_label.text = Localization.tr_key("ui.settings_panel.p005") % _action_name(action)
		_refresh_keys()

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open("settings", open)
	if open:
		_update_layout()
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
	var panel := PanelChrome.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	_layout_root = root
	root.custom_minimum_size = Vector2(650, 430)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = Localization.tr_key("ui.settings_panel.p006")
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	PanelChrome.style_title(title)
	var close := Button.new()
	close.text = Localization.tr_key("ui.settings_panel.p007")
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)
	var divider := HSeparator.new()
	PanelChrome.style_separator(divider)
	root.add_child(divider)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	PanelChrome.style_tabs(tabs)
	_build_audio(tabs)
	_build_visual(tabs)
	_build_game(tabs)
	_build_controls(tabs)
	_build_data(tabs)
	_conflict = ConfirmationDialog.new()
	_conflict.title = Localization.tr_key("ui.settings_panel.p008")
	_conflict.confirmed.connect(_confirm_swap)
	add_child(_conflict)

func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.name = title + "Content"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	return box

func _update_layout() -> void:
	if _layout_root == null:
		return
	var logical := get_viewport().get_visible_rect().size / SettingsRuntime.ui_scale_value()
	_layout_root.custom_minimum_size = Vector2(minf(860.0, maxf(320.0, logical.x - 64.0)),
		minf(600.0, maxf(260.0, logical.y - 64.0)))

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
	var box := _tab(tabs, Localization.tr_key("ui.settings_panel.p009"))
	_slider(box, Localization.tr_key("ui.settings_panel.p010"), "musicVolume", 0.0, 1.0, 0.05)
	_slider(box, Localization.tr_key("ui.settings_panel.p011"), "sfxVolume", 0.0, 1.0, 0.05)
	var hint := Label.new()
	hint.text = Localization.tr_key("ui.settings_panel.p012")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

func _build_visual(tabs: TabContainer) -> void:
	var box := _tab(tabs, Localization.tr_key("ui.settings_panel.p013"))
	# M5-9d（09-A）：三轴各自档位化 + 显示适配（自动/手动）。
	_option_row(box, Localization.tr_key("ui.settings_panel.p014"), "uiScale", [80, 100, 125, 150, 175, 200])
	_option_row(box, Localization.tr_key("ui.settings_panel.p015"), "mapScale", [80, 100, 125, 150, 175, 200])
	_option_row(box, Localization.tr_key("ui.settings_panel.p016"), "textScale", [100, 110, 125, 150, 175, 200])
	var color_row := HBoxContainer.new()
	box.add_child(color_row)
	var color_label := Label.new()
	color_label.text = Localization.tr_key("ui.settings_panel.p017")
	color_label.custom_minimum_size.x = 160
	color_row.add_child(color_label)
	var color_options := OptionButton.new()
	color_options.add_item(Localization.tr_key("ui.settings_panel.p018"))
	color_options.add_item(Localization.tr_key("ui.settings_panel.p019"))
	color_options.select(1 if String(GameState.settings.get("colorblindMode", "off")) == "friendly" else 0)
	color_options.item_selected.connect(func(index: int) -> void:
		GameState.settings["colorblindMode"] = "friendly" if index == 1 else "off"
		_changed())
	color_row.add_child(color_options)
	_build_display_adapt(box)
	_checkbox(box, Localization.tr_key("ui.settings_panel.p020"), "fullscreen")
	var resolution := OptionButton.new()
	for entry in [{"id": "auto", "label": Localization.tr_key("ui.settings_panel.p021")}, {"id": "1280x800", "label": "1280×800"},
		{"id": "1440x900", "label": "1440×900"}, {"id": "1600x900", "label": "1600×900"},
		{"id": "1920x1200", "label": "1920×1200"}]:
		resolution.add_item(String(entry.label))
		resolution.set_item_metadata(resolution.item_count - 1, String(entry.id))
		if String(GameState.settings.get("resolution", "auto")) == String(entry.id):
			resolution.select(resolution.item_count - 1)
	resolution.item_selected.connect(func(index: int) -> void:
		GameState.settings["resolution"] = resolution.get_item_metadata(index)
		_changed())
	box.add_child(resolution)
	# 屏震 / 强闪尚无实际效果；旧档字段保留兼容，界面暂不暴露空开关。
	var hint := Label.new()
	hint.text = Localization.tr_key("ui.settings_panel.p024")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

## M5-9d：百分比档位下拉（界面大小 / 地图显示大小 / 文字大小共用，写入 float 设置键）。
## 旧档值不在档位表内时（如 9d 前的 uiScale=1.2）：选中最接近档位**但不改写设置** ——
## 玩家不动它就保持原值生效，一动即落到新档位（与 textScale clamp 兼容旧档同一思路）。
func _option_row(box: VBoxContainer, label: String, field: String, percents: Array) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var caption := Label.new()
	caption.text = label
	caption.custom_minimum_size.x = 160
	row.add_child(caption)
	var options := OptionButton.new()
	var current := float(GameState.settings.get(field, 1.0))
	var exact := -1
	var nearest := 0
	var nearest_gap := INF
	for pct in percents:
		var value := float(int(pct)) / 100.0
		options.add_item("%d%%" % int(pct), int(pct))
		if is_equal_approx(value, current):
			exact = options.item_count - 1
		var gap: float = absf(value - current)
		if gap < nearest_gap:
			nearest_gap = gap
			nearest = options.item_count - 1
	options.select(exact if exact >= 0 else nearest)
	options.item_selected.connect(func(index: int) -> void:
		GameState.settings[field] = float(options.get_item_id(index)) / 100.0
		_changed())
	row.add_child(options)

## M5-9c/d：显示适配 —— 自动（默认）/ 手动（75–150% 统一系数，乘到界面、文字、地图三轴）。
func _build_display_adapt(box: VBoxContainer) -> void:
	# 手动系数行先建后加：模式行在上、系数行在下（仅手动模式可见）。
	# ⚠ 代码创建的控件入树后名字是 "@类型@N" 自动名，勿按名字引用；顺序由 add_child 决定。
	var manual_row := HBoxContainer.new()
	manual_row.visible = SettingsRuntime.display_scale_mode() == "manual"
	var row := HBoxContainer.new()
	box.add_child(row)
	var caption := Label.new()
	caption.text = Localization.tr_key("ui.settings_panel.p025")
	caption.custom_minimum_size.x = 160
	row.add_child(caption)
	var mode := OptionButton.new()
	mode.add_item(Localization.tr_key("ui.settings_panel.p026"))
	mode.add_item(Localization.tr_key("ui.settings_panel.p027"))
	mode.select(1 if SettingsRuntime.display_scale_mode() == "manual" else 0)
	mode.item_selected.connect(func(index: int) -> void:
		GameState.settings["displayScaleMode"] = "manual" if index == 1 else "auto"
		manual_row.visible = index == 1
		_changed())
	row.add_child(mode)
	box.add_child(manual_row)
	var spacer := Label.new()
	spacer.custom_minimum_size.x = 160
	manual_row.add_child(spacer)
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 300
	slider.min_value = SettingsRuntime.DISPLAY_SCALE_MIN
	slider.max_value = SettingsRuntime.DISPLAY_SCALE_MAX
	slider.step = 0.05
	slider.value = clampf(float(GameState.settings.get("displayScale", 1.0)),
		SettingsRuntime.DISPLAY_SCALE_MIN, SettingsRuntime.DISPLAY_SCALE_MAX)
	manual_row.add_child(slider)
	var value := Label.new()
	value.text = "%.0f%%" % (slider.value * 100.0)
	manual_row.add_child(value)
	slider.value_changed.connect(func(v: float) -> void:
		GameState.settings["displayScale"] = v
		value.text = "%.0f%%" % (v * 100.0)
		_changed())
	var hint := Label.new()
	hint.text = Localization.tr_key("ui.settings_panel.p028")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

func _build_game(tabs: TabContainer) -> void:
	var box := _tab(tabs, Localization.tr_key("ui.settings_panel.p029"))
	_slider(box, Localization.tr_key("ui.settings_panel.p030"), "potionThreshold", 0.1, 0.9, 0.05)
	_checkbox(box, Localization.tr_key("ui.settings_panel.p031"), "allowBoss")
	_checkbox(box, Localization.tr_key("ui.settings_panel.p032"), "dropFlyAnim")
	# 品质自动拾取过滤尚未接线，旧档字段保留兼容，避免展示不会生效的选项。

func _build_controls(tabs: TabContainer) -> void:
	var root := _tab(tabs, Localization.tr_key("ui.settings_panel.p038"))
	_capture_label = Label.new()
	_capture_label.text = Localization.tr_key("ui.settings_panel.p039")
	_capture_label.add_theme_color_override("font_color", PanelChrome.TEXT)
	root.add_child(_capture_label)
	_key_list = VBoxContainer.new()
	_key_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_list.add_theme_constant_override("separation", 4)
	root.add_child(_key_list)
	_refresh_keys()

func _build_data(tabs: TabContainer) -> void:
	var box := _tab(tabs, Localization.tr_key("ui.settings_panel.p040"))
	var button := Button.new()
	button.text = Localization.tr_key("ui.settings_panel.p041")
	button.pressed.connect(func() -> void:
		set_open(false)
		var save_panel := get_node("../SavePanel")
		save_panel.set_mode("manage")
		save_panel.set_open(true))
	box.add_child(button)
	PanelChrome.style_action(button)
	var note := Label.new()
	note.text = Localization.tr_key("ui.settings_panel.p042")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

func _refresh_keys() -> void:
	if _key_list == null:
		return
	for child in _key_list.get_children():
		child.queue_free()
	for action in SettingsRuntime.ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		_key_list.add_child(row)
		var name := Label.new()
		name.text = _action_name(action)
		name.custom_minimum_size.x = 300
		name.add_theme_color_override("font_color", PanelChrome.TEXT)
		row.add_child(name)
		var key := Button.new()
		key.custom_minimum_size.x = 140
		key.text = OS.get_keycode_string(SettingsRuntime.key_for(action))
		key.pressed.connect(_start_capture.bind(action))
		row.add_child(key)
		PanelChrome.style_action(key)

func _action_name(action: String) -> String:
	if action.begins_with("hotbar_"):
		return Localization.tr_key("ui.settings_panel.p043") % action.trim_prefix("hotbar_")
	return Localization.tr_key(String(ACTION_NAMES[action])) if ACTION_NAMES.has(action) else action

func _start_capture(action: String) -> void:
	_capture_action = action
	_capture_label.text = Localization.tr_key("ui.settings_panel.p044") % _action_name(action)

func _confirm_swap() -> void:
	SettingsRuntime.set_binding(_pending_action, _pending_code)
	_capture_label.text = Localization.tr_key("ui.settings_panel.p045")
	_pending_action = ""
	_pending_code = 0
	_refresh_keys()

func _changed() -> void:
	SettingsRuntime.apply_all()
	_update_layout.call_deferred()
	SettingsRuntime.save_display_preferences()
	EventBus.settings_changed.emit()
