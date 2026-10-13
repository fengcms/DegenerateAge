extends Control
## M4-7 主菜单与暂停菜单。菜单打开时暂停世界；UI CanvasLayer 持续处理输入。

const MAIN := "main"
const PAUSE := "pause"

var _mode := ""
var _root: VBoxContainer
var _title: Label
var _continue: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false
	EventBus.panel_opened.connect(_on_panel_opened)

func initialize_if_current() -> void:
	if get_tree().current_scene != get_parent().get_parent():
		return
	if GameState.menu_mode == "world":
		get_tree().paused = false
		return
	GameState.menu_mode = "menu"
	SaveManager.active_slot = -1
	open_main()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or event.is_echo() or GameState.menu_mode != "world":
		return
	if visible and _mode == PAUSE:
		resume_game()
		get_viewport().set_input_as_handled()
	elif not GameState.panel_open:
		open_pause()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	# 从设置或存档面板返回时恢复原菜单；子面板之间仍按既有互斥规则运作。
	if not visible and not GameState.panel_open and _mode != "":
		if _mode == MAIN and GameState.menu_mode == "menu":
			_show(MAIN)
		elif _mode == PAUSE and GameState.menu_mode == "world":
			_show(PAUSE)

func open_main() -> void:
	GameState.menu_mode = "menu"
	_show(MAIN)

func open_pause() -> void:
	if GameState.menu_mode != "world":
		return
	_show(PAUSE)

func resume_game() -> void:
	visible = false
	_mode = ""
	GameState.set_panel_open("menu", false)
	get_tree().paused = false

func _show(mode: String) -> void:
	_mode = mode
	get_tree().paused = true
	visible = true
	GameState.set_panel_open("menu", true)
	for child in _root.get_children():
		child.queue_free()
	_title.text = Localization.tr_key("ui.menu_panel.p001") if mode == MAIN else Localization.tr_key("ui.menu_panel.p002")
	if mode == MAIN:
		_continue = _button(Localization.tr_key("ui.menu_panel.p003"), _continue_game)
		_continue.disabled = SaveManager.continue_slot() < 0
		_button(Localization.tr_key("ui.menu_panel.p004"), _open_new_slots)
		_button(Localization.tr_key("ui.menu_panel.p005"), _open_load_slots)
		_button(Localization.tr_key("ui.menu_panel.p006"), _open_settings)
		_button(Localization.tr_key("ui.menu_panel.p007"), _quit_game)
	else:
		_button(Localization.tr_key("ui.menu_panel.p003"), resume_game)
		_button(Localization.tr_key("ui.menu_panel.p006"), _open_settings)
		_button(Localization.tr_key("ui.menu_panel.p008"), _open_manage_slots)
		_button(Localization.tr_key("ui.menu_panel.p009"), _return_to_main)
	EventBus.panel_opened.emit("menu")

func _on_panel_opened(panel_id: String) -> void:
	if panel_id != "menu" and visible:
		visible = false
		GameState.set_panel_open("menu", false)

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 44)
	button.pressed.connect(action)
	_root.add_child(button)
	return button

func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.84)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("121a20")
	style.border_color = Color("8d7653")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	content.add_child(_title)
	content.add_child(HSeparator.new())
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 9)
	content.add_child(_root)

func _continue_game() -> void:
	if not SaveManager.resume_last():
		_continue.disabled = true
		EventBus.toast_requested.emit(Localization.tr_key("ui.menu_panel.p010"), "danger")
		return
	_start_world()

func _open_new_slots() -> void:
	_open_slots("new")

func _open_load_slots() -> void:
	_open_slots("load")

func _open_manage_slots() -> void:
	_open_slots("manage")

func _open_slots(mode: String) -> void:
	var panel := get_node("../SavePanel")
	panel.set_mode(mode)
	panel.set_open(true)

func _open_settings() -> void:
	get_node("../SettingsPanel").set_open(true)

func _start_world() -> void:
	GameState.menu_mode = "world"
	get_tree().paused = false
	MapService.reload_world()

func _return_to_main() -> void:
	SaveManager.save_on_quit()
	SaveManager.active_slot = -1  # 保留 last_slot，供主菜单「继续」使用。
	GameState.reset_to_defaults()
	GameState.menu_mode = "menu"
	get_tree().paused = false
	MapService.reload_world()

func _quit_game() -> void:
	get_tree().quit()
