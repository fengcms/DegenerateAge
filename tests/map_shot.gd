extends Node
## M3-3 开窗检查：加载真实 Main，通过 Viewport 鼠标事件及 M/Esc 路由验证地图。
## 自动存沿用 tests 场景闸门，输出 PNG 仅用于布局检查；不是游戏功能的替代。
var _failures: Array[String] = []

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "wild_trial"
	GameState.quest_states = {"Q002": {"state": "active", "progress": 0}}
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.4).timeout
	_freeze_enemies()
	var mini: MapCanvas = main.get_node("UI/Hud/MapPanel/Minimap")
	var panel: Control = main.get_node("UI/MapBigPanel")
	var player: PlayerCharacter = main.get_node("Game/Entities/Player")
	await _capture("minimap")
	_click(mini.get_global_rect().get_center())
	await get_tree().create_timer(0.2).timeout
	_check(panel.visible and GameState.panel_open, "小地图点击打开大图")
	await _capture("quest")
	var canvas: MapCanvas = panel.get("_map")
	_click(canvas.get_global_rect().position + Vector2(10, 10))
	await get_tree().create_timer(0.1).timeout
	_check(panel.visible and not player.map_move_active, "图外点击拒绝")
	var start := player.global_position
	var point := Iso.grid_pt(40, 34)
	_click(canvas.get_global_rect().position + canvas.world_to_canvas(point))
	await get_tree().create_timer(0.5).timeout
	_check(not panel.visible and player.map_move_active and player.global_position.distance_to(point) < start.distance_to(point), "地图点击实际移动")
	_key(KEY_M)
	await get_tree().create_timer(0.2).timeout
	_check(panel.visible, "M打开大图")
	await _capture("moving")
	_key(KEY_ESCAPE)
	await get_tree().create_timer(0.1).timeout
	_check(not panel.visible and not GameState.panel_open, "Esc只关闭地图")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.reset_to_defaults()
	GameState.current_map = "corruption_source"
	GameState.quest_states = {"Q005": {"state": "active", "progress": 0}}
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.3).timeout
	_freeze_enemies()
	panel = main.get_node("UI/MapBigPanel")
	_key(KEY_M)
	await get_tree().create_timer(0.2).timeout
	var markers := MapMarkers.for_world(main.get_node("Game"))
	_check(markers.any(func(m: Dictionary) -> bool: return m.kind == "quest" and m.name == "腐化源头" and m.revealed), "Boss任务标记")
	await _capture("boss")
	if _failures.is_empty():
		print("[MapShot] 全部交互检查通过 ✅")
	else:
		for message in _failures:
			print("[MapShot] 失败：", message)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)

func _freeze_enemies() -> void:
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)

func _click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event)

func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		get_viewport().push_input(event)

func _capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "/tmp/degenerateage_map_%s.png" % tag
	get_viewport().get_texture().get_image().save_png(path)
	print("[MapShot] ", path)
