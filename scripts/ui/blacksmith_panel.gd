extends Control
## 铁匠对话与功能菜单。NPC 的自我介绍来自 maps.json，继续后进入升星面板。

const PANEL_ID := "blacksmith"
const COL_PANEL := Color(0.06, 0.07, 0.09, 0.97)
const COL_BORDER := Color(0.36, 0.31, 0.26)

var _title: Label
var _greeting: Label
var _continue: Button
var _upgrade: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.blacksmith_panel_requested.connect(_on_requested)
	EventBus.panel_opened.connect(_on_panel_opened)

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("pause")):
		set_open(false)
		get_viewport().set_input_as_handled()

func _on_requested(npc_name: String, greeting: String) -> void:
	_title.text = PanelChrome.title_text(Localization.tr_key("ui.blacksmith_panel.p001") % npc_name)
	_greeting.text = "「%s」" % greeting
	set_open(true)

func _on_panel_opened(panel_id: String) -> void:
	if panel_id != PANEL_ID and visible:
		set_open(false)

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open(PANEL_ID, open)
	if open:
		_continue.visible = true
		_upgrade.visible = false
		EventBus.panel_opened.emit(PANEL_ID)

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.36)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelChrome.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(430, 0)
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	_title = Label.new()
	_title.text = Localization.tr_key("ui.blacksmith_panel.p002")
	_title.add_theme_font_size_override("font_size", 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	PanelChrome.style_title(_title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)
	var divider := HSeparator.new()
	PanelChrome.style_separator(divider)
	root.add_child(divider)
	_greeting = Label.new()
	_greeting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_greeting)
	_continue = Button.new()
	_continue.text = Localization.tr_key("ui.blacksmith_panel.p003")
	_continue.pressed.connect(_show_menu)
	root.add_child(_continue)
	_upgrade = Button.new()
	_upgrade.text = Localization.tr_key("ui.blacksmith_panel.p004")
	_upgrade.pressed.connect(_open_upgrade)
	root.add_child(_upgrade)

func _show_menu() -> void:
	_continue.visible = false
	_upgrade.visible = true
	_upgrade.grab_focus()

func _open_upgrade() -> void:
	set_open(false)
	EventBus.upgrade_panel_requested.emit()
