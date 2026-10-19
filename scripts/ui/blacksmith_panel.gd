extends Control
## 铁匠对话与功能菜单。NPC 的自我介绍来自 maps.json，继续后进入升星面板。

const PANEL_ID := "blacksmith"
const COL_PANEL := Color(0.06, 0.07, 0.09, 0.97)
const COL_BORDER := Color(0.36, 0.31, 0.26)

var _title: Label
var _greeting: Label
var _continue: Button
var _upgrade: Button
var _reforge: Button
var _greeting_card: Control
var _service_card: Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.blacksmith_panel_requested.connect(_on_requested)
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("pause")):
		set_open(false)
		get_viewport().set_input_as_handled()

func _on_requested(npc_name: String, greeting: String) -> void:
	_title.text = PanelChrome.title_text(npc_name if not npc_name.is_empty() else Localization.tr_key("ui.blacksmith_panel.p002"))
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
		_reforge.visible = false
		_greeting_card.visible = true
		_service_card.visible = false
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
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(500, 350)
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
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
	root.add_child(PanelChrome.make_title_gap())
	_greeting_card = PanelContainer.new()
	PanelChrome.style_card(_greeting_card as PanelContainer)
	_greeting_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_greeting_card)
	var greeting_row := HBoxContainer.new()
	greeting_row.add_theme_constant_override("separation", 18)
	_greeting_card.add_child(greeting_row)
	var portrait := TextureRect.new()
	var portrait_atlas := AtlasTexture.new()
	portrait_atlas.atlas = preload("res://assets/sprites/npcs/blacksmith/idle_atlas.png")
	portrait_atlas.region = Rect2(0, 0, 64, 80)
	portrait.texture = portrait_atlas
	portrait.custom_minimum_size = Vector2(118, 150)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	greeting_row.add_child(portrait)
	var speech := VBoxContainer.new()
	speech.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	greeting_row.add_child(speech)
	var speaker := Label.new()
	speaker.text = "铁匠"
	PanelChrome.style_section(speaker)
	speech.add_child(speaker)
	_greeting = Label.new()
	_greeting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_greeting.add_theme_color_override("font_color", PanelChrome.TEXT)
	speech.add_child(_greeting)
	_service_card = PanelContainer.new()
	PanelChrome.style_card(_service_card as PanelContainer)
	_service_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_service_card.visible = false
	root.add_child(_service_card)
	var service_content := VBoxContainer.new()
	service_content.add_theme_constant_override("separation", 12)
	_service_card.add_child(service_content)
	var service_title := Label.new()
	service_title.text = "可用服务"
	PanelChrome.style_section(service_title)
	service_content.add_child(service_title)
	var service_description := Label.new()
	service_description.text = "%s\n\n%s" % [Localization.tr_key("ui.blacksmith_panel.p005"),
		Localization.tr_key("ui.blacksmith_panel.p006")]
	service_description.add_theme_color_override("font_color", PanelChrome.TEXT)
	service_content.add_child(service_description)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)
	var leave := Button.new()
	leave.text = "离开"
	leave.pressed.connect(func() -> void: set_open(false))
	actions.add_child(leave)
	PanelChrome.style_action(leave)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_continue = Button.new()
	_continue.text = Localization.tr_key("ui.blacksmith_panel.p003")
	_continue.pressed.connect(_show_menu)
	actions.add_child(_continue)
	PanelChrome.style_action(_continue, true)
	_upgrade = Button.new()
	_upgrade.text = Localization.tr_key("ui.blacksmith_panel.p004")
	_upgrade.pressed.connect(_open_upgrade)
	actions.add_child(_upgrade)
	PanelChrome.style_action(_upgrade, true)
	_reforge = Button.new()
	_reforge.text = Localization.tr_key("ui.reforge_panel.p002")
	_reforge.pressed.connect(_open_reforge)
	actions.add_child(_reforge)
	PanelChrome.style_action(_reforge, true)

func _show_menu() -> void:
	_continue.visible = false
	_upgrade.visible = true
	_reforge.visible = true
	_greeting_card.visible = false
	_service_card.visible = true
	_upgrade.grab_focus()

func _open_upgrade() -> void:
	set_open(false)
	EventBus.upgrade_panel_requested.emit()

## M10-8：铁匠服务菜单第二项。与升星同构 —— 先关铁匠再开重铸面板。
func _open_reforge() -> void:
	set_open(false)
	EventBus.reforge_panel_requested.emit()
