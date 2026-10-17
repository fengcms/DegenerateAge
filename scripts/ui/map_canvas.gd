class_name MapCanvas
extends Control
## 小/大地图复用世界投影；营地白盒显示矩形边界，其余地图保留等距轮廓。
## 静态底图按探索变化更新，玩家标记移动不重建背景。
signal destination_selected(world_position: Vector2)
@export var minimap: bool = false
@export var ornamental_frame: bool = false
var _map_id := ""
var _player_position := Vector2.ZERO
var _markers: Array[Dictionary] = []
## 自动寻路的行进路线折线（世界坐标）；由 refresh() 从玩家侧读取，无寻路时为空。
var _route: Array[Vector2] = []
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
var _terrain_mesh: ArrayMesh
var _background_revision := -1
var _background_cave: CaveLayout
## Diagnostic counter: moving markers must not rebuild static terrain.
var background_draw_count := 0
## 地图内容节点（地形与轮廓）；小地图跟随只改它的 position，底图渲染命令不失效。
var _terrain: Node2D
## 小地图局部视野：视野中心（世界坐标）、可见半径、锚点（人物世界坐标）与跟随位移。
var _view_center := Vector2.ZERO
var _view_half := Vector2.ZERO
var _view_anchor := Vector2.ZERO
var _follow_offset := Vector2.ZERO
var _clip_radius := 0.0
var _clip_material: ShaderMaterial

## 等宽字体（M4-10）：小地图上的标记字母（N/B）不经主题，显式引用与 default_theme
## 相同的字体资源，保证数字 / 字母等宽对齐。
const MONO_FONT := preload("res://assets/themes/mono_font.tres")

## 自动寻路虚线路线：大地图与小地图共用同一套绘制（本文件是小/大地图唯一绘制源）。
## 线色与玩家标记同系（"这是你的路线"），终点空心金环与任务目标标记同色。
const ROUTE_COLOR := Color("6eebe6")
const ROUTE_TARGET_COLOR := Color("f2cb5b")
const ROUTE_WIDTH_MINIMAP := 2.0
const ROUTE_WIDTH_BIG := 3.0
const ROUTE_DASH_MINIMAP := 5.0
const ROUTE_DASH_BIG := 8.0
const ROUTE_TARGET_RADIUS_MINIMAP := 4.0
const ROUTE_TARGET_RADIUS_BIG := 6.0
const ROUTE_TARGET_WIDTH := 2.0

## 小地图局部视野：圆内只显示以人物为中心的固定格数（瓦片宽度折算），
## 看全景必须打开大地图。固定格数而非固定倍数，可让不同尺寸地图的观感一致。
const MINIMAP_VIEW_GRIDS := 18.0
## 圆形裁剪材质：小地图内容放大后会越出圆边糊在 HUD 框外，用 fragment discard 裁掉。
const MINIMAP_CLIP_SHADER := preload("res://assets/ui/minimap_clip.gdshader")

## 注册迷雾事件与内容层，首次显示时构建静态背景。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	EventBus.fog_changed.connect(_on_fog_changed)
	# 地形与轮廓挂在子节点上：小地图跟随只改它的 position，不触发 _draw()。
	_terrain = Node2D.new()
	_terrain.name = "Terrain"
	_terrain.draw.connect(_draw_terrain)
	add_child(_terrain)
	_overlay = Node2D.new()
	_overlay.name = "Markers"
	_overlay.draw.connect(_draw_markers)
	add_child(_overlay)
	resized.connect(_invalidate_background)
	refresh()

## 可见时每 0.2 秒同步动态标记；不因玩家移动重建底图。
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_refresh_t += delta
	if _refresh_t >= 0.2:
		_refresh_t = 0.0
		refresh()

## 当前地图探索发生变化时失效静态背景缓存。
func _on_fog_changed(map_id: String) -> void:
	if map_id == GameState.current_map:
		_exploration = GameState.explored_maps.get(map_id, _empty_exploration)
		_exploration_count = _exploration.size()
		_invalidate_background()

## 排队重绘底盘、地形与标记；只在尺寸、地图或探索变化时调用。
func _invalidate_background() -> void:
	_refresh_follow()
	queue_redraw()
	if is_instance_valid(_terrain):
		_terrain.queue_redraw()
	if is_instance_valid(_overlay):
		_overlay.queue_redraw()

## 读取玩家、导航版本与地图标记，按实际变化更新两层绘制缓存。
func refresh() -> void:
	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	var position_now := player.global_position if player != null else MapService.entry_point(GameState.current_map)
	var route: Array[Vector2] = []
	if player != null:
		route = player.map_move_route()
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
	_update_view(position_now)
	# 换图时该分支同样执行，路线缓存随之归零，不会残留上一张图的虚线。
	if GameState.current_map != _map_id or position_now != _player_position or markers != _markers or route != _route:
		_map_id = GameState.current_map
		_player_position = position_now
		_markers = markers
		_route = route
		_overlay.queue_redraw()

## 从地图配置重建世界到控件的投影；营地用屏幕矩形，其他图用等距外框。
## 小地图不再整图适配，改为圆内固定格数的局部视野（见 MINIMAP_VIEW_GRIDS）。
func _ensure_projection() -> void:
	if _projection_map == GameState.current_map and _projection_size == size and _projection_minimap == minimap:
		return
	_projection_map = GameState.current_map
	_projection_size = size
	_projection_minimap = minimap
	_dims = MapService.grid_size(_projection_map)
	var map_data := MapService.data_for(_projection_map)
	var screen_rect: Variant = map_data.get("worldRect", [])
	if screen_rect is Array and screen_rect.size() == 4:
		_world_rect = Rect2(float(screen_rect[0]), float(screen_rect[1]),
			float(screen_rect[2]), float(screen_rect[3]))
	else:
		var corners := [Iso.grid_pt(-0.5, -0.5), Iso.grid_pt(_dims.x - 0.5, -0.5), Iso.grid_pt(_dims.x - 0.5, _dims.y - 0.5), Iso.grid_pt(-0.5, _dims.y - 0.5)]
		_world_rect = Rect2(corners[0], Vector2.ZERO)
		for corner: Vector2 in corners:
			_world_rect = _world_rect.expand(corner)
	if minimap:
		# 圆内直径恰好容纳 MINIMAP_VIEW_GRIDS 格；可见半径比圆盘小 1px，
		# 让圆盘自身画出的边缘（内接多边形）成为可见边界，不留透明缝。
		_clip_radius = maxf(1.0, minf(size.x, size.y) * 0.5 - 3.0)
		_scale = maxf(0.001, _clip_radius * 2.0 / (MINIMAP_VIEW_GRIDS * Iso.TILE_W))
		_view_half = Vector2.ONE * (_clip_radius / _scale)
	else:
		var available := size - Vector2(40, 40)
		_scale = maxf(0.001, minf(available.x / maxf(1, _world_rect.size.x), available.y / maxf(1, _world_rect.size.y)))
		_view_half = Vector2.ZERO
	_apply_clip_material()

## 小地图挂圆形裁剪材质（大地图不挂）；材质在内容层上，底盘圆盘不受影响。
func _apply_clip_material() -> void:
	if minimap and _clip_material == null:
		_clip_material = ShaderMaterial.new()
		_clip_material.shader = MINIMAP_CLIP_SHADER
	if is_instance_valid(_terrain):
		_terrain.material = _clip_material if minimap else null
	if is_instance_valid(_overlay):
		_overlay.material = _clip_material if minimap else null

## 记录视野锚点（人物世界坐标）并重算跟随位移。
func _update_view(anchor: Vector2) -> void:
	_view_anchor = anchor
	_refresh_follow()

## 小地图：视野恒锁人物（夹紧在地图范围内），位移交给内容层节点，
## 底图绘制命令与既有「移动只重绘 overlay」缓存语义都不受影响；大地图位移恒 0。
func _refresh_follow() -> void:
	_ensure_projection()
	if minimap:
		var center := _view_anchor
		center.x = _clamp_view_axis(center.x, _world_rect.position.x, _world_rect.end.x, _view_half.x)
		center.y = _clamp_view_axis(center.y, _world_rect.position.y, _world_rect.end.y, _view_half.y)
		_view_center = center
	else:
		_view_center = _world_rect.get_center()
	_follow_offset = (_world_rect.get_center() - _view_center) * _scale
	if is_instance_valid(_terrain):
		_terrain.position = _follow_offset
	if is_instance_valid(_overlay):
		_overlay.position = _follow_offset
	if _clip_material != null:
		_clip_material.set_shader_parameter("clip_center", size * 0.5 - _follow_offset)
		_clip_material.set_shader_parameter("clip_radius", _clip_radius)

## 视野中心沿一个轴夹紧：地图比视野还小时居中，否则保证视野不越出地图外框。
func _clamp_view_axis(value: float, lo: float, hi: float, half: float) -> float:
	if hi - lo <= half * 2.0:
		return (lo + hi) * 0.5
	return clampf(value, lo + half, hi - half)

## 返回当前地图在世界像素中的显示外框，供地图面板与测试查询。
func world_rect() -> Rect2:
	_ensure_projection()
	return _world_rect

## 返回世界像素到控件像素的比例，仅在投影失效时重算。
func map_scale() -> float:
	_ensure_projection()
	return _scale

## 当前绘制的自动寻路路线折线（世界坐标）；无寻路时为空数组。供测试与外部查询。
func route_points() -> Array[Vector2]:
	return _route

## 小地图局部视野的可见半径（世界像素）；大地图返回 0，表示不裁剪、不跟随。
func view_radius_world() -> float:
	_ensure_projection()
	return _view_half.x

## 小地图局部视野的中心（世界坐标）；大地图恒为整图中心。
func view_center_world() -> Vector2:
	_ensure_projection()
	return _view_center

## 内容层当前挂载的圆形裁剪材质；大地图未挂载时返回 null。
func clip_material() -> ShaderMaterial:
	if not is_instance_valid(_terrain):
		return null
	return _terrain.material as ShaderMaterial

## 世界坐标点是否落在小地图圆内可见区（大地图恒为 true）。
func in_minimap_view(world: Vector2) -> bool:
	_ensure_projection()
	if not minimap:
		return true
	return world.distance_to(_view_center) <= _view_half.x

## 小地图实际参与绘制的路线折线（按视野矩形裁剪后的结果）；大地图为原折线。
func visible_route_points() -> Array[Vector2]:
	return _visible_route()

## 路线终点是否会在图上画出终点金环；小地图要求终点仍在视野圆内。
func route_target_visible() -> bool:
	if _route.size() < 2:
		return false
	return in_minimap_view(_route[_route.size() - 1])

## 将世界像素映射到控件坐标（含小地图跟随位移）；大地图位移恒 0，与整图适配逐值一致。
func world_to_canvas(world: Vector2) -> Vector2:
	_ensure_projection()
	return _project(world) + _follow_offset

## 使用已缓存的世界外框和比例投影一个世界像素点（地图锚定坐标，不含跟随位移）。
func _project(world: Vector2) -> Vector2:
	return size * 0.5 + (world - _world_rect.get_center()) * _scale

## 将控件坐标转换为等距格浮点坐标，供大地图点击寻路；与 world_to_canvas 互为逆映射。
func canvas_to_grid(point: Vector2) -> Vector2:
	_ensure_projection()
	return Iso.world_to_grid(_world_rect.get_center() + (point - size * 0.5 - _follow_offset) / _scale)

## 小地图点击打开大图；大地图只把矩形营地或其他地图内部点击派发为目标。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		if minimap:
			if event.position.distance_to(size * 0.5) <= minf(size.x, size.y) * 0.5:
				EventBus.map_panel_requested.emit()
			return
		var grid := canvas_to_grid(event.position)
		if GameState.current_map == "camp" and not _world_rect.has_point(_world_rect.get_center() +
				(event.position - size * 0.5) / _scale):
			EventBus.toast_requested.emit(Localization.tr_key("ui.map_canvas.p001"), "danger")
			return
		var dims := MapService.grid_size(GameState.current_map)
		if grid.x < -0.5 or grid.y < -0.5 or grid.x >= dims.x - 0.5 or grid.y >= dims.y - 0.5:
			EventBus.toast_requested.emit(Localization.tr_key("ui.map_canvas.p001"), "danger")
			return
		destination_selected.emit(Iso.grid_pt(grid.x, grid.y))

## 查询鼠标附近可见地图标记的说明文字。
func _get_tooltip(at_position: Vector2) -> String:
	if minimap:
		return Localization.tr_key("ui.map_canvas.p002")
	for marker in _markers:
		if _marker_visible(marker) and world_to_canvas(marker.position).distance_to(at_position) <= 14:
			return String(marker.name)
	return Localization.tr_key("ui.map_canvas.p003")

## 按迷雾、小地图局部视野与大地图规则判断一个动态标记是否可见。
func _marker_visible(marker: Dictionary) -> bool:
	var kind := String(marker.get("kind", ""))
	if minimap:
		# 局部视野：圆外的标记一律不画，想看全局必须打开大地图。
		if not in_minimap_view(marker.position):
			return false
		if kind == "exit" or kind == "carter":
			return true
	elif bool(marker.get("always_big", false)):
		return true
	var cell := Vector2i(Iso.world_to_grid(marker.position).round())
	return bool(marker.get("revealed", false)) or Fog.is_explored(GameState.current_map, cell)

## 把等距格范围投影成控件四边形，供探索区块合批。
func _polygon(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([_project(Iso.grid_pt(x0, y0)), _project(Iso.grid_pt(x1, y0)), _project(Iso.grid_pt(x1, y1)), _project(Iso.grid_pt(x0, y1))])

## 绘制视口底盘（小地图圆盘 / 大地图矩形底）；地图内容交给 _terrain 子节点，
## 使小地图跟随位移只改节点 transform，不触发本回调，也不重建底图。
func _draw() -> void:
	_ensure_projection()
	if not MapService.exists(GameState.current_map):
		return
	if minimap:
		draw_circle(size * 0.5, minf(size.x, size.y) * 0.5 - 2, Color("162321") if ornamental_frame else Color("131a1e"))
		if not ornamental_frame:
			draw_arc(size * 0.5, minf(size.x, size.y) * 0.5 - 2, 0, TAU, 64, Color("778e91"), 2, true)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color("101619"))

## 绘制静态边界与已探索地形；渲染命令由引擎缓存（background_draw_count 在此计数）。
func _draw_terrain() -> void:
	background_draw_count += 1
	_ensure_projection()
	if not MapService.exists(GameState.current_map):
		return
	var dims := _dims
	var outline := _polygon(-0.5, -0.5, dims.x - 0.5, dims.y - 0.5)
	if GameState.current_map == "camp":
		outline = PackedVector2Array([_project(_world_rect.position),
			_project(Vector2(_world_rect.end.x, _world_rect.position.y)), _project(_world_rect.end),
			_project(Vector2(_world_rect.position.x, _world_rect.end.y))])
	_terrain.draw_colored_polygon(outline, Color("100e0b") if GameState.current_map == "corruption_source" else Color("334633") if minimap and ornamental_frame else Color("1f282d"))
	var world := get_tree().get_first_node_in_group("map_world")
	var ground := world.get_node_or_null("Ground") as IsoGround if world != null else null
	var explored: Dictionary = GameState.explored_maps.get(GameState.current_map, _empty_exploration)
	var block_width := ceili(float(dims.x) / Fog.BLOCK_SIZE)
	var builder := FlatTileMesh.new(mini(explored.size() * Fog.BLOCK_SIZE * Fog.BLOCK_SIZE, dims.x * dims.y))
	# Iterate revealed blocks once, then preserve the exact walkable-cell mask.
	for raw_id in explored:
		var id := int(raw_id)
		var cell := Vector2i((id % block_width) * Fog.BLOCK_SIZE, (id / block_width) * Fog.BLOCK_SIZE)
		var end := (cell + Vector2i.ONE * Fog.BLOCK_SIZE).min(dims)
		if ground != null and ground.cave != null:
			for y in range(cell.y, end.y):
				for x in range(cell.x, end.x):
					if ground.cave.is_walkable(Vector2i(x, y)):
						builder.add_quad(_polygon(x - 0.5, y - 0.5, x + 0.5, y + 0.5))
		else:
			builder.add_quad(_polygon(cell.x - 0.5, cell.y - 0.5, end.x - 0.5, end.y - 0.5))
	_terrain_mesh = builder.build()
	if _terrain_mesh != null:
		var terrain_color := Color("b4a382") if ground != null and ground.cave != null else Color("66705a") if minimap and ornamental_frame else Color("536959")
		_terrain.draw_mesh(_terrain_mesh, null, Transform2D.IDENTITY, terrain_color)
	var border := outline.duplicate()
	border.append(outline[0])
	if ground == null or ground.cave == null:
		_terrain.draw_polyline(border, Color("859a8b"), 1, true)

## 绘制 NPC、出口、玩家等动态标记，与底图缓存分开。
func _draw_markers() -> void:
	_ensure_projection()
	if not MapService.exists(GameState.current_map):
		return
	# 路线先画（压在标记之下），避免虚线遮挡 NPC / Boss / 出口的文字与图标。
	_draw_route()
	for marker in _markers:
		if not _marker_visible(marker):
			continue
		var p := _project(marker.position)
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
	_overlay.draw_circle(_project(_player_position), 4 if minimap else 6, Color("6eebe6"))
	_overlay.draw_arc(_project(_player_position), 6 if minimap else 9, 0, TAU, 24, Color.WHITE, 1, true)

## 绘制自动寻路的行进路线：从人物当前坐标到目标的虚线，终点补一个空心金环。
## 折线由 Player.map_move_route() 提供（洞穴地图为绕障路点，非洞穴为两点直线）；
## 无寻路时为空数组，此时不画任何内容。小地图侧按视野矩形截断（见 _visible_route）。
func _draw_route() -> void:
	if _route.size() < 2:
		return
	var width := ROUTE_WIDTH_MINIMAP if minimap else ROUTE_WIDTH_BIG
	var dash := ROUTE_DASH_MINIMAP if minimap else ROUTE_DASH_BIG
	var points := _visible_route()
	for index in range(points.size() - 1):
		_overlay.draw_dashed_line(_project(points[index]), _project(points[index + 1]),
			ROUTE_COLOR, width, dash, true, true)
	# 终点在圆外时不画金环：避免误导玩家「目标就在圆边」，看全局请开大地图。
	if not route_target_visible():
		return
	var target := _project(_route[_route.size() - 1])
	var radius := ROUTE_TARGET_RADIUS_MINIMAP if minimap else ROUTE_TARGET_RADIUS_BIG
	_overlay.draw_arc(target, radius, 0, TAU, 20, ROUTE_TARGET_COLOR, ROUTE_TARGET_WIDTH, true)

## 小地图：把路线按视野矩形裁剪，超出的段丢掉；大地图返回原折线。
func _visible_route() -> Array[Vector2]:
	if not minimap or _route.size() < 2:
		return _route
	var rect := Rect2(_view_center - _view_half, _view_half * 2.0)
	var clipped: Array[Vector2] = []
	for index in range(_route.size() - 1):
		for point in _clip_segment(_route[index], _route[index + 1], rect):
			if clipped.is_empty() or not clipped[clipped.size() - 1].is_equal_approx(point):
				clipped.append(point)
	return clipped

## Liang–Barsky 线段裁剪：返回线段落在矩形内的部分（完全在外时为空数组）。
func _clip_segment(from: Vector2, to: Vector2, rect: Rect2) -> Array[Vector2]:
	var delta := to - from
	var enter := 0.0
	var exit := 1.0
	var bounds := [-delta.x, delta.x, -delta.y, delta.y]
	var limits := [from.x - rect.position.x, rect.end.x - from.x, from.y - rect.position.y, rect.end.y - from.y]
	for index in range(4):
		var p: float = bounds[index]
		var q: float = limits[index]
		if is_zero_approx(p):
			if q < 0.0:
				return []
			continue
		var t := q / p
		if p < 0.0:
			enter = maxf(enter, t)
		else:
			exit = minf(exit, t)
		if enter > exit:
			return []
	return [from + delta * enter, from + delta * exit]
