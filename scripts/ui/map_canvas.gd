class_name MapCanvas
extends Control
## 小/大地图复用等距投影；圆形小地图点击打开大图，大图点击只派发当前图世界坐标。
signal destination_selected(world_position: Vector2)
@export var minimap: bool = false
var _map_id := ""
var _player_position := Vector2.ZERO
var _markers: Array[Dictionary] = []
var _refresh_t := 0.0

## 等宽字体（M4-10）：小地图上的标记字母（N/B）不经主题，显式引用与 default_theme
## 相同的字体资源，保证数字 / 字母等宽对齐。
const MONO_FONT := preload("res://assets/themes/mono_font.tres")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	EventBus.fog_changed.connect(_on_fog_changed)
	resized.connect(queue_redraw)
	refresh()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_refresh_t += delta
	if _refresh_t >= 0.2:
		_refresh_t = 0.0
		refresh()

func _on_fog_changed(map_id: String) -> void:
	if map_id == GameState.current_map:
		queue_redraw()

func refresh() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var position_now := player.global_position if player != null else MapService.entry_point(GameState.current_map)
	var world := get_tree().get_first_node_in_group("map_world")
	var markers := MapMarkers.for_world(world)
	if GameState.current_map != _map_id or position_now != _player_position or markers != _markers:
		_map_id = GameState.current_map
		_player_position = position_now
		_markers = markers
		queue_redraw()

## 与 IsoGround 的格中心/边界一致，支持非正方形地图与局部四格区块。
func world_rect() -> Rect2:
	var dims := MapService.grid_size(GameState.current_map)
	var corners := [Iso.grid_pt(-0.5, -0.5), Iso.grid_pt(dims.x - 0.5, -0.5), Iso.grid_pt(dims.x - 0.5, dims.y - 0.5), Iso.grid_pt(-0.5, dims.y - 0.5)]
	var rect := Rect2(corners[0], Vector2.ZERO)
	for corner: Vector2 in corners:
		rect = rect.expand(corner)
	return rect

func map_scale() -> float:
	var rect := world_rect()
	var available := Vector2.ONE * (minf(size.x, size.y) - 24) if minimap else size - Vector2(40, 40)
	return maxf(0.001, minf(available.x / maxf(1, rect.size.x), available.y / maxf(1, rect.size.y)))

func world_to_canvas(world: Vector2) -> Vector2:
	return size * 0.5 + (world - world_rect().get_center()) * map_scale()

func canvas_to_grid(point: Vector2) -> Vector2:
	return Iso.world_to_grid(world_rect().get_center() + (point - size * 0.5) / map_scale())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		if minimap:
			if event.position.distance_to(size * 0.5) <= minf(size.x, size.y) * 0.5:
				EventBus.map_panel_requested.emit()
			return
		var grid := canvas_to_grid(event.position)
		var dims := MapService.grid_size(GameState.current_map)
		if grid.x < -0.5 or grid.y < -0.5 or grid.x >= dims.x - 0.5 or grid.y >= dims.y - 0.5:
			EventBus.toast_requested.emit("请点击地图范围内的位置", "danger")
			return
		destination_selected.emit(Iso.grid_pt(grid.x, grid.y))

func _get_tooltip(at_position: Vector2) -> String:
	if minimap:
		return "点击打开大地图 · M"
	for marker in _markers:
		var cell := Vector2i(Iso.world_to_grid(marker.position).round())
		if (marker.revealed or Fog.is_explored(GameState.current_map, cell)) and world_to_canvas(marker.position).distance_to(at_position) <= 14:
			return String(marker.name)
	return "点击本图位置步行前往"

func _polygon(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([world_to_canvas(Iso.grid_pt(x0, y0)), world_to_canvas(Iso.grid_pt(x1, y0)), world_to_canvas(Iso.grid_pt(x1, y1)), world_to_canvas(Iso.grid_pt(x0, y1))])

func _draw() -> void:
	if not MapService.exists(GameState.current_map):
		return
	if minimap:
		draw_circle(size * 0.5, minf(size.x, size.y) * 0.5 - 2, Color("131a1e"))
		draw_arc(size * 0.5, minf(size.x, size.y) * 0.5 - 2, 0, TAU, 64, Color("778e91"), 2, true)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color("101619"))
	var dims := MapService.grid_size(GameState.current_map)
	var outline := _polygon(-0.5, -0.5, dims.x - 0.5, dims.y - 0.5)
	draw_colored_polygon(outline, Color("1f282d"))
	var blocks := Fog.block_grid(GameState.current_map)
	for y in range(blocks.y):
		for x in range(blocks.x):
			var cell := Vector2i(x * Fog.BLOCK_SIZE, y * Fog.BLOCK_SIZE)
			if Fog.is_explored(GameState.current_map, cell):
				draw_colored_polygon(_polygon(cell.x - 0.5, cell.y - 0.5, mini(cell.x + Fog.BLOCK_SIZE, dims.x) - 0.5, mini(cell.y + Fog.BLOCK_SIZE, dims.y) - 0.5), Color("536959"))
	var border := outline.duplicate()
	border.append(outline[0])
	draw_polyline(border, Color("859a8b"), 1, true)
	for marker in _markers:
		var cell := Vector2i(Iso.world_to_grid(marker.position).round())
		if not marker.revealed and not Fog.is_explored(GameState.current_map, cell):
			continue
		var p := world_to_canvas(marker.position)
		var kind := String(marker.kind)
		var color := Color("f2cb5b") if kind == "quest" else (Color("da85ec") if kind == "boss" else Color("89b8ee"))
		draw_circle(p, 3 if minimap else 5, color)
		if not minimap:
			var glyph := ("!B" if bool(marker.get("boss", false)) else "!") if kind == "quest" else ("B" if kind == "boss" else "N")
			draw_string(MONO_FONT, p + Vector2(7, 4), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
	draw_circle(world_to_canvas(_player_position), 4 if minimap else 6, Color("6eebe6"))
	draw_arc(world_to_canvas(_player_position), 6 if minimap else 9, 0, TAU, 24, Color.WHITE, 1, true)
