extends Control

const PANEL_ID := "super_portable"
var _first: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 360)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = Localization.tr_key("ui.panel.super_portable")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	for row in [["boss_token", "随身 Boss"], ["shop", "随身商店"], ["blacksmith", "随身铁匠"], ["carter", "随身车夫"], ["warehouse", "随身仓库"]]:
		var button := Button.new()
		button.text = row[1]
		button.custom_minimum_size.y = 42
		box.add_child(button)
		if _first == null:
			_first = button
		button.pressed.connect(func() -> void:
			set_open(false)
			PanelRouter.open(row[0])
		)
	var close := Button.new()
	close.text = "关闭（Esc）"
	box.add_child(close)
	close.pressed.connect(func() -> void: set_open(false))
	visible = false
	EventBus.super_portable_requested.connect(func() -> void: set_open(true))
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
	EventBus.panel_opened.connect(func(id: String) -> void:
		if id != PANEL_ID and visible:
			set_open(false)
	)

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open(PANEL_ID, open)
	if open:
		EventBus.panel_opened.emit(PANEL_ID)
		_first.grab_focus()
	else:
		var focus := get_viewport().gui_get_focus_owner()
		if focus != null and is_ancestor_of(focus):
			focus.release_focus()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		set_open(false)
		get_viewport().set_input_as_handled()
