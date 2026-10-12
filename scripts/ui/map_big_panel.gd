extends Control
## M3-3：沿用关闭式面板互斥/屏蔽指令规则，世界继续模拟。
var _title: Label
var _info: Label
var _map: MapCanvas
var _hint: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.map_panel_requested.connect(func() -> void: set_open(true))
	EventBus.panel_opened.connect(_on_panel_opened)

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
		_title.text = "%s　·　大地图" % MapService.display_name(GameState.current_map)
		var cell := Iso.world_to_grid(MapService.entry_point(GameState.current_map))
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null:
			cell = Iso.world_to_grid(player.global_position)
		_info.text = "当前位置 (%d, %d)　·　推荐 Lv%d" % [roundi(cell.x), roundi(cell.y), MapService.recommended_level(GameState.current_map)]
		_hint.text = "点击本图位置步行前往 · WASD / 攻击可接管 · M / Esc 关闭"
		_map.refresh()
		_map.queue_redraw()
		EventBus.panel_opened.emit("map")

func _on_destination(point: Vector2) -> void:
	var world := get_tree().get_first_node_in_group("map_world")
	if world == null or not world.request_map_move(point):
		_hint.text = "当前无法移动，请等待角色恢复"
		EventBus.toast_requested.emit(_hint.text, "danger")
		return
	set_open(false)

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
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171e24")
	style.border_color = Color("73878c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	box.add_child(margin)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(800, 0)
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "关闭 · Esc"
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	_info = Label.new()
	root.add_child(_info)
	_map = MapCanvas.new()
	_map.name = "MapCanvas"
	_map.custom_minimum_size = Vector2(800, 400)
	_map.destination_selected.connect(_on_destination)
	root.add_child(_map)
	var legend := Label.new()
	legend.text = "青色圈：你　·　N：NPC　·　!：已接任务目标　·　B：Boss　·　暗色：未探索"
	legend.add_theme_font_size_override("font_size", 13)
	root.add_child(legend)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 13)
	root.add_child(_hint)
	var targets := Label.new()
	targets.text = "任务标记显示当前图的刷新区域；其他地图目标随车夫切图查看。"
	targets.add_theme_font_size_override("font_size", 12)
	targets.modulate = Color("a0afb7")
	root.add_child(targets)
