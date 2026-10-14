class_name MapCanvas
extends Control
## 小/大地图复用等距投影；圆形小地图点击打开大图，大图点击只派发当前图世界坐标。
signal destination_selected(world_position: Vector2)
@export var minimap: bool = false
@export var ornamental_frame: bool = false
var _map_id := ""
var _player_position := Vector2.ZERO
var _markers: Array[Dictionary] = []
var _refresh_t := 0.0
var _overlay: Node2D
var _projection_map := ""
var _projection_size := Vector2(-1, -1)
var _projection_minimap := false
var _dims := Vector2i.ZERO
var _world_rect := Rect2()
var _scale := 1.0
var _empty_exploration: Dictionary = {}
var _background_map := ""
var _background_style := false
var _exploration: Dictionary = {}
var _exploration_count := -1
var _background_revision := -1
var _background_cave: CaveLayout
## Diagnostic counter: moving markers must not rebuild static terrain.
var background_draw_count := 0

## 等宽字体（M4-10）：小地图上的标记字母（N/B）不经主题，显式引用与 default_theme
## 相同的字体资源，保证数字 / 字母等宽对齐。
const MONO_FONT := preload("res://assets/themes/mono_font.tres")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	EventBus.fog_changed.connect(_on_fog_changed)
	_overlay = Node2D.new()
	_overlay.name = "Markers"
	_overlay.draw.connect(_draw_markers)
	add_child(_overlay)
	resized.connect(_invalidate_background)
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
		_exploration = GameState.explored_maps.get(map_id, _empty_exploration)
		_exploration_count = _exploration.size()
		_invalidate_background()

func _invalidate_background() -> void:
	queue_redraw()
	if is_instance_valid(_overlay):
		_overlay.queue_redraw()

func refresh() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var position_now := player.global_position if player != null else MapService.entry_point(GameState.current_map)
	var world := get_tree().get_first_node_in_group("map_world")
	var markers := MapMarkers.for_world(world)
	var ground := world.get_node_or_null("Ground") as IsoGround if world != null else null
	var cave := ground.cave if ground != null else null
	var revision := cave.navigation_revision if cave != null else -1
	var exploration: Dictionary = GameState.explored_maps.get(GameState.current_map, _empty_exploration)
	# Fog only adds blocks in place; loading/resetting can replace the dictionary.
	if _background_map != GameState.current_map or _background_style != ornamental_frame \
			or _projection_map != GameState.current_map or _projection_size != size \
			or _projection_minimap != minimap or cave != _background_cave or revision != _background_revision \
			or not is_same(exploration, _exploration) or exploration.size() != _exploration_count:
		_background_map = GameState.current_map
		_background_style = ornamental_frame
		_exploration = exploration
		_exploration_count = exploration.size()
		_background_cave = cave
		_background_revision = revision
		_ensure_projection()
		_invalidate_background()
	if GameState.current_map != _map_id or position_now != _player_position or markers != _markers:
		_map_id = GameState.current_map
		_player_position = position_now
		_markers = markers
		_overlay.queue_redraw()

## 与 IsoGround 的格中心/边界一致，支持非正方形地图与局部四格区块。
func _ensure_projection() -> void:
	if _projection_map == GameState.current_map and _projection_size == size and _projection_minimap == minimap:
		return
	_projection_map = GameState.current_map
	_projection_size = size
	_projection_minimap = minimap
	_dims = MapService.grid_size(_projection_map)
	var corners := [Iso.grid_pt(-0.5, -0.5), Iso.grid_pt(_dims.x - 0.5, -0.5), Iso.grid_pt(_dims.x - 0.5, _dims.y - 0.5), Iso.grid_pt(-0.5, _dims.y - 0.5)]
	_world_rect = Rect2(corners[0], Vector2.ZERO)
	for corner: Vector2 in corners:
		_world_rect = _world_rect.expand(corner)
	var available := Vector2.ONE * (minf(size.x, size.y) - 24) if minimap else size - Vector2(40, 40)
	_scale = maxf(0.001, minf(available.x / maxf(1, _world_rect.size.x), available.y / maxf(1, _world_rect.size.y)))

func world_rect() -> Rect2:
	_ensure_projection()
	return _world_rect

func map_scale() -> float:
	_ensure_projection()
	return _scale

func world_to_canvas(world: Vector2) -> Vector2:
	_ensure_projection()
	return _project(world)

func _project(world: Vector2) -> Vector2:
	return size * 0.5 + (world - _world_rect.get_center()) * _scale

func canvas_to_grid(point: Vector2) -> Vector2:
	_ensure_projection()
	return Iso.world_to_grid(_world_rect.get_center() + (point - size * 0.5) / _scale)

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
			EventBus.toast_requested.emit(Localization.tr_key("ui.map_canvas.p001"), "danger")
			return
		destination_selected.emit(Iso.grid_pt(grid.x, grid.y))

func _get_tooltip(at_position: Vector2) -> String:
	if minimap:
		return Localization.tr_key("ui.map_canvas.p002")
	for marker in _markers:
		if _marker_visible(marker) and world_to_canvas(marker.position).distance_to(at_position) <= 14:
			return String(marker.name)
	return Localization.tr_key("ui.map_canvas.p003")

func _marker_visible(marker: Dictionary) -> bool:
	var kind := String(marker.get("kind", ""))
	if minimap and (kind == "exit" or kind == "carter"):
		return get_viewport().get_visible_rect().has_point(get_viewport().get_canvas_transform() * Vector2(marker.position))
	if not minimap and bool(marker.get("always_big", false)):
		return true
	var cell := Vector2i(Iso.world_to_grid(marker.position).round())
	return bool(marker.get("revealed", false)) or Fog.is_explored(GameState.current_map, cell)

func _polygon(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([_project(Iso.grid_pt(x0, y0)), _project(Iso.grid_pt(x1, y0)), _project(Iso.grid_pt(x1, y1)), _project(Iso.grid_pt(x0, y1))])

func _draw() -> void:
	background_draw_count += 1
	_ensure_projection()
	if not MapService.exists(GameState.current_map):
		return
	if minimap:
		draw_circle(size * 0.5, minf(size.x, size.y) * 0.5 - 2, Color("162321") if ornamental_frame else Color("131a1e"))
		if not ornamental_frame:
			draw_arc(size * 0.5, minf(size.x, size.y) * 0.5 - 2, 0, TAU, 64, Color("778e91"), 2, true)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color("101619"))
	var dims := _dims
	var outline := _polygon(-0.5, -0.5, dims.x - 0.5, dims.y - 0.5)
	draw_colored_polygon(outline, Color("100e0b") if GameState.current_map == "corruption_source" else Color("334633") if minimap and ornamental_frame else Color("1f282d"))
	var world := get_tree().get_first_node_in_group("map_world")
	var ground := world.get_node_or_null("Ground") as IsoGround if world != null else null
	var explored: Dictionary = GameState.explored_maps.get(GameState.current_map, _empty_exploration)
	var block_width := ceili(float(dims.x) / Fog.BLOCK_SIZE)
	# Iterate revealed blocks once, then preserve the exact walkable-cell mask.
	for raw_id in explored:
		var id := int(raw_id)
		var cell := Vector2i((id % block_width) * Fog.BLOCK_SIZE, (id / block_width) * Fog.BLOCK_SIZE)
		var end := (cell + Vector2i.ONE * Fog.BLOCK_SIZE).min(dims)
		if ground != null and ground.cave != null:
			for y in range(cell.y, end.y):
				for x in range(cell.x, end.x):
					if ground.cave.is_walkable(Vector2i(x, y)):
						draw_colored_polygon(_polygon(x - 0.5, y - 0.5, x + 0.5, y + 0.5), Color("b4a382"))
		else:
			draw_colored_polygon(_polygon(cell.x - 0.5, cell.y - 0.5, end.x - 0.5, end.y - 0.5), Color("66705a") if minimap and ornamental_frame else Color("536959"))
	var border := outline.duplicate()
	border.append(outline[0])
	if ground == null or ground.cave == null:
		draw_polyline(border, Color("859a8b"), 1, true)

func _draw_markers() -> void:
	_ensure_projection()
	if not MapService.exists(GameState.current_map):
		return
	for marker in _markers:
		if not _marker_visible(marker):
			continue
		var p := world_to_canvas(marker.position)
		var kind := String(marker.kind)
		var color := Color("f2cb5b") if kind == "quest" else (Color("da85ec") if kind == "boss" else (Color("7ee1cf") if kind == "exit" else (Color("d6b47b") if kind == "carter" else Color("89b8ee"))))
		if kind == "exit":
			_overlay.draw_line(p + Vector2(-5, 0), p + Vector2(5, 0), color, 2, true)
			_overlay.draw_line(p + Vector2(-5, 0), p + Vector2(-2, -3), color, 2, true)
			_overlay.draw_line(p + Vector2(5, 0), p + Vector2(2, 3), color, 2, true)
		elif kind == "carter":
			_overlay.draw_arc(p, 4 if minimap else 6, 0, TAU, 16, color, 2, true)
			_overlay.draw_circle(p, 1.5, color)
		else:
			_overlay.draw_circle(p, 3 if minimap else 5, color)
		if not minimap:
			var glyph := ("!B" if bool(marker.get("boss", false)) else "!") if kind == "quest" else ("B" if kind == "boss" else ("↔" if kind == "exit" else ("◎" if kind == "carter" else "N")))
			if kind == "exit":
				glyph = "%s%s %s" % [Localization.tr_key("ui.map.locked_short") if not bool(marker.get("unlocked", true)) else "", glyph, MapService.display_name(String(marker.get("to_map", "")))]
			_overlay.draw_string(MONO_FONT, p + Vector2(7, 4), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
	_overlay.draw_circle(world_to_canvas(_player_position), 4 if minimap else 6, Color("6eebe6"))
	_overlay.draw_arc(world_to_canvas(_player_position), 6 if minimap else 9, 0, TAU, 24, Color.WHITE, 1, true)
