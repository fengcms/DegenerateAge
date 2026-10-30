extends Control

const PANEL_ID := "super_portable"
const SERVICES := ["boss_token", "shop", "blacksmith", "carter", "warehouse"]

var _first: Button
var _window: FloatingWindow
var _root: VBoxContainer
var _scroll: ScrollContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	get_viewport().size_changed.connect(_resize)
	EventBus.settings_changed.connect(_resize)
	_resize.call_deferred()
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
		_window.show_window()
		_first.grab_focus()
	else:
		var focus := get_viewport().gui_get_focus_owner()
		if focus != null and is_ancestor_of(focus):
			focus.release_focus()

# 先于 GUI 与世界的 unhandled 输入接管数字键；仅最上层令牌菜单生效。
func _input(event: InputEvent) -> void:
	if not visible or not _window.is_top_window():
		return
	if event is InputEventKey and (event.alt_pressed or event.ctrl_pressed or event.meta_pressed or event.shift_pressed):
		return
	for i in range(SERVICES.size()):
		if event.is_action_pressed("super_service_%d" % (i + 1)):
			get_viewport().set_input_as_handled()
			if not event.is_echo():
				_open_service(SERVICES[i])
			return
	if event.is_action_pressed("pause"):
		set_open(false)
		get_viewport().set_input_as_handled()

func _resize() -> void:
	var logical := get_viewport_rect().size / SettingsRuntime.ui_scale_value()
	_root.custom_minimum_size.x = minf(440.0, logical.x * 0.84)
	_window.set_content_scroll(_scroll)

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.36)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_window = FloatingWindow.new()
	add_child(_window)
	var panel := PanelChrome.new()
	_window.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 12)
	margin.add_child(_root)
	var head := HBoxContainer.new()
	_root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	var heading := Label.new()
	heading.text = Localization.tr_key("ui.panel.super_portable")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PanelChrome.style_title(heading)
	head.add_child(heading)
	var close := Button.new()
	PanelChrome.style_close(close)
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	_window.setup(self, panel, head, Vector2(0.5, 0.5))
	_root.add_child(PanelChrome.make_title_gap())
	var card := PanelContainer.new()
	PanelChrome.style_card(card)
	_root.add_child(card)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(_scroll)
	var services := VBoxContainer.new()
	services.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	services.add_theme_constant_override("separation", 10)
	_scroll.add_child(services)
	for row in [["boss_token", "ui.super.boss"], ["shop", "ui.super.shop"], ["blacksmith", "ui.super.smith"], ["carter", "ui.super.carter"], ["warehouse", "ui.super.warehouse"]]:
		var button := Button.new()
		button.text = "%d  ·  %s" % [SERVICES.find(row[0]) + 1, Localization.tr_key(row[1])]
		button.custom_minimum_size.y = 42
		PanelChrome.style_action(button)
		services.add_child(button)
		if _first == null:
			_first = button
		button.pressed.connect(_open_service.bind(String(row[0])))
	var hint := Label.new()
	hint.text = Localization.tr_key("ui.super.shortcuts")
	hint.add_theme_color_override("font_color", PanelChrome.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(hint)
	_window.set_content_scroll(_scroll)

func _open_service(panel_id: String) -> void:
	set_open(false)
	var result := PanelRouter.open(panel_id)
	if not bool(result.get("ok", false)):
		EventBus.toast_requested.emit(String(result.get("reason", "")), "danger")
