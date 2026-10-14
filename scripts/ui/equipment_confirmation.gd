extends Control
## 降品质确认是短时模态；普通背包/人物面板仍保持既有战斗行为。

var _request_id := -1
var _pause_before := false
var _panel: PanelContainer
var _scroll: ScrollContainer
var _current: Label
var _incoming: Label
var _comparison: Label
var _skip: CheckBox
var _cancel: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 4095
	_build()
	visible = false
	EventBus.equipment_confirmation_requested.connect(_show_request)
	EventBus.equipment_confirmation_closed.connect(_close)
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.player_died.connect(GameState.cancel_equipment_change)
	get_viewport().size_changed.connect(_resize_dialog)
	EventBus.settings_changed.connect(_resize_dialog)

func _build() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.05, 0.82)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("121c24")
	style.border_color = Color("b69a65")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := Label.new()
	title.text = Localization.tr_key("ui.equip_confirm.title")
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = Localization.tr_key("ui.common.cancel")
	close.pressed.connect(GameState.cancel_equipment_change)
	heading.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	_scroll.add_child(body)
	var warning := _label(body)
	warning.text = Localization.tr_key("ui.equip_confirm.warning")
	_current = _label(body)
	_incoming = _label(body)
	_comparison = _label(body)
	_skip = CheckBox.new()
	_skip.text = Localization.tr_key("ui.equip_confirm.skip")
	_skip.tooltip_text = Localization.tr_key("ui.equip_confirm.session")
	column.add_child(_skip)
	var session := _label(column)
	session.text = Localization.tr_key("ui.equip_confirm.session")
	session.add_theme_color_override("font_color", Color("a6b3be"))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_cancel = Button.new()
	_cancel.text = Localization.tr_key("ui.common.cancel")
	_cancel.custom_minimum_size = Vector2(100, 38)
	_cancel.pressed.connect(GameState.cancel_equipment_change)
	buttons.add_child(_cancel)
	var confirm := Button.new()
	confirm.text = Localization.tr_key("ui.equip_confirm.confirm")
	confirm.custom_minimum_size = Vector2(130, 38)
	confirm.pressed.connect(_confirm)
	buttons.add_child(confirm)

func _label(parent: Node) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _resize_dialog() -> void:
	if _panel == null:
		return
	var available := get_viewport_rect().size / SettingsRuntime.ui_scale_value()
	_panel.custom_minimum_size.x = minf(600.0, maxf(280.0, available.x - 40.0))
	_scroll.custom_minimum_size.y = minf(270.0, maxf(100.0, available.y * 0.40))

func _show_request(preview: Dictionary) -> void:
	if GameState.pending_equipment_change.is_empty():
		return
	_request_id = int(preview.request_id)
	_pause_before = get_tree().paused
	var worn: Dictionary = preview.worn
	var candidate: Dictionary = preview.candidate
	_current.text = Localization.tr_key("ui.equip_confirm.current", [String(preview.slot_label),
		ItemUtil.display_name(worn), float(preview.worn_score)])
	_current.add_theme_color_override("font_color", ItemUtil.quality_color(String(worn.quality)))
	_incoming.text = Localization.tr_key("ui.equip_confirm.incoming", [ItemUtil.display_name(candidate),
		float(preview.candidate_score)])
	_incoming.add_theme_color_override("font_color", ItemUtil.quality_color(String(candidate.quality)))
	_comparison.text = Localization.tr_key("ui.equip_confirm.comparison", [
		ItemUtil.quality_name(String(worn.quality)), ItemUtil.quality_name(String(candidate.quality)),
		float(preview.worn_score), float(preview.candidate_score)])
	_skip.button_pressed = false
	_scroll.scroll_vertical = 0
	visible = true
	_resize_dialog()
	GameState.set_panel_open("equipment_confirm", true)
	get_tree().paused = true
	_cancel.grab_focus()

func _confirm() -> void:
	GameState.confirm_equipment_change(_request_id, _skip.button_pressed)

func _close() -> void:
	if not visible:
		return
	visible = false
	_request_id = -1
	GameState.set_panel_open("equipment_confirm", false)
	# 不抢占主菜单、死亡或加载流程的暂停状态。
	get_tree().paused = _pause_before or GameState.menu_mode != "world" \
		or int(GameState.player.get("hp", 0)) <= 0 \
		or GameState._open_panels.has("death") or GameState._open_panels.has("menu") \
		or MapService.loading_active

func _on_panel_opened(panel_id: String) -> void:
	if visible and panel_id not in ["inventory", "character"]:
		GameState.cancel_equipment_change()

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		GameState.cancel_equipment_change()
		get_viewport().set_input_as_handled()

func _unhandled_input(_event: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if EventBus.player_died.is_connected(GameState.cancel_equipment_change):
		EventBus.player_died.disconnect(GameState.cancel_equipment_change)
	if visible:
		GameState.cancel_equipment_change()
