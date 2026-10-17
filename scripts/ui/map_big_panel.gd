extends Control
## M3-3：沿用关闭式面板互斥/屏蔽指令规则，世界继续模拟。

## 标题行、当前位置、图例、路线提示与目标说明所需的逻辑高度；缩放时优先收紧地图画布，
## 避免外框越界（图例含路线/终点两项后需要多留一行，取 260）。
const MAP_VERTICAL_CHROME_BUDGET := 260.0
var _title: Label
var _info: Label
var _map: MapCanvas
var _hint: Label
var _root: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	get_viewport().size_changed.connect(_update_layout)
	EventBus.settings_changed.connect(_update_layout)
	_update_layout.call_deferred()
	visible = false
	EventBus.map_panel_requested.connect(func() -> void: set_open(true))
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("panel_map") and not event.is_echo():
		set_open(not visible)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		set_open(false)
		get_viewport().set_input_as_handled()

func _on_panel_opened(panel_id: String) -> void:
	if panel_id != "map" and visible:
		set_open(false)

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open("map", open)
	if open:
		_update_layout()
		_title.text = PanelChrome.title_text(Localization.tr_key("ui.map_big_panel.p001") % MapService.display_name(GameState.current_map))
		var cell := Iso.world_to_grid(MapService.entry_point(GameState.current_map))
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null:
			cell = Iso.world_to_grid(player.global_position)
		_info.text = Localization.tr_key("ui.map_big_panel.p002") % [roundi(cell.x), roundi(cell.y), MapService.recommended_level(GameState.current_map)]
		_hint.text = Localization.tr_key("ui.map_big_panel.p003")
		_map.refresh()
		_map.queue_redraw()
		EventBus.panel_opened.emit("map")

func _on_destination(point: Vector2) -> void:
	var world := get_tree().get_first_node_in_group("map_world")
	if world == null or not world.request_map_move(point):
		_hint.text = Localization.tr_key("ui.map_big_panel.p004")
		EventBus.toast_requested.emit(_hint.text, "danger")
		return
	# 面板**不关闭**：让玩家当场看到刚下发的行进路线（青色虚线 + 金色终点环）。
	# 角色此时已开始自动行走，路线随人物实时推进；此后仍可继续点选别处改目标。
	_hint.text = Localization.tr_key("ui.map_big_panel.p008")

func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.4)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := PanelChrome.new()
	center.add_child(box)
	var margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	box.add_child(margin)
	var root := VBoxContainer.new()
	_root = root
	root.custom_minimum_size = Vector2(800, 0)
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	PanelChrome.style_title(_title)
	var close := Button.new()
	close.text = Localization.tr_key("ui.map_big_panel.p005")
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)
	root.add_child(PanelChrome.make_title_gap())
	_info = Label.new()
	root.add_child(_info)
	PanelChrome.style_section(_info)
	_map = MapCanvas.new()
	_map.name = "MapCanvas"
	_map.custom_minimum_size = Vector2(800, 400)
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.destination_selected.connect(_on_destination)
	root.add_child(_map)
	var legend := Label.new()
	legend.text = Localization.tr_key("ui.map_big_panel.p006")
	legend.add_theme_font_size_override("font_size", 13)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(legend)
	legend.add_theme_color_override("font_color", PanelChrome.MUTED)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_hint)
	_hint.add_theme_color_override("font_color", PanelChrome.TEXT)
	var targets := Label.new()
	targets.text = Localization.tr_key("ui.map_big_panel.p007")
	targets.add_theme_font_size_override("font_size", 12)
	targets.modulate = Color("a0afb7")
	targets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(targets)

func _update_layout() -> void:
	if _root == null or _map == null:
		return
	var logical := get_viewport().get_visible_rect().size / SettingsRuntime.ui_scale_value()
	var width := minf(800.0, maxf(280.0, logical.x - 48.0))
	_root.custom_minimum_size.x = width
	_map.custom_minimum_size = Vector2(0, minf(400.0, maxf(96.0, logical.y - MAP_VERTICAL_CHROME_BUDGET)))
