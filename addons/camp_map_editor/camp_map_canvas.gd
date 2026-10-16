@tool
extends Control
## 营地编辑器画布：以屏幕矩形坐标绘制当前地面、道路、整体分层和碰撞，
## 支持地面格笔刷和单体碰撞顶点交互；只响应编辑器鼠标，不直接改正式地图。

signal selection_changed(object_id: String)
signal document_changed()

const SIZE := Vector2(1672, 941)
const GROUND := "res://assets/maps/camp_style_full_b_v2/ground_tile.png"
const ROAD := "res://assets/maps/camp_style_full_b_v2/roads_and_shadows.png"
const GROUND_CELL_SIZE := 128

var document: RefCounted
var mode := "object"
var selected_id := ""
var selected_branch := -1
var selected_point := -1
var selected_vertex := -1
var brush_id := "grass"
var hovered_ground_cell := Vector2i(-1, -1)
var show_collision := true
var show_targets := true
var zoom_factor := 1.0
var pan := Vector2.ZERO
var _ground: Texture2D
var _road: Texture2D
var _textures: Dictionary = {}
var _ground_stamps: Dictionary = {}
var _npc_cells: Array = []
var _dragging := false
var _panning := false
var _pan_button := MOUSE_BUTTON_NONE
var _space_held := false
var _drag_start := Vector2.ZERO
var _last_delta := Vector2i.ZERO
var _last_ground_cell := Vector2i(-1, -1)

## 进入编辑器时加载已导入的运行贴图，所有对象复用相同纹理实例。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ground = load(GROUND) as Texture2D
	_road = load(ROAD) as Texture2D
	for tile: Dictionary in document.palette.get("tiles", []):
		_ground_stamps[String(tile["id"])] = load(String(tile["path"])) as Texture2D
	var maps: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps.json"))
	if maps is Array:
		for map_entry: Dictionary in maps:
			if map_entry.get("id") == "camp":
				_npc_cells = map_entry.get("npcs", [])
				break
	resized.connect(queue_redraw)

## 应用新道路贴图后清除图像缓存，让编辑画布立即显示重建结果。
func reload_textures() -> void:
	_road = load(ROAD) as Texture2D
	_textures.clear()
	queue_redraw()

## 根据画布缩放和用户平移，将屏幕鼠标换成 1672×941 参考像素坐标。
func screen_to_canvas(screen: Vector2) -> Vector2:
	return (screen - _origin()) / _scale_value()

## 计算当前编辑窗口的适配缩放；缩放按钮只修改额外倍率。
func _scale_value() -> float:
	return minf((size.x - 24.0) / SIZE.x, (size.y - 24.0) / SIZE.y) * zoom_factor

## 返回参考画布左上角在控件中的坐标，保证默认居中。
func _origin() -> Vector2:
	return (size - SIZE * _scale_value()) * 0.5 + pan

## 绘制与游戏共用的贴图层，并叠加当前草稿的路点、脚底碰撞与固定服务点。
func _draw() -> void:
	if document == null or document.layout.is_empty():
		return
	draw_set_transform(_origin(), 0.0, Vector2.ONE * _scale_value())
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color("aa8455"))
	if _ground != null:
		draw_texture_rect(_ground, Rect2(Vector2.ZERO, SIZE), true)
	_draw_ground_patches()
	if _road != null:
		draw_texture_rect(_road, Rect2(Vector2.ZERO, SIZE), false)
	var objects: Array = document.manifest.get("objects", []).duplicate()
	objects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["foot_y"]) < int(b["foot_y"]))
	for item: Dictionary in objects:
		_draw_layer(item, "back")
	for item: Dictionary in objects:
		_draw_layer(item, "front")
	if show_collision or mode == "collision":
		for item: Dictionary in objects:
			var polygon: PackedVector2Array = document.footprint(String(item["id"]))
			if polygon.size() > 2:
				var tint := Color(1.0, 0.35, 0.2, 0.8) if String(item["id"]) == selected_id else Color(1.0, 0.28, 0.2, 0.38)
				_draw_closed_polyline(polygon, tint, (3.0 if String(item["id"]) == selected_id else 1.5) / _scale_value())
	if mode == "collision" and not selected_id.is_empty():
		_draw_collision_handles()
	if show_targets:
		_draw_targets()
	if mode == "road":
		_draw_road_guides()
	if mode == "ground":
		_draw_ground_grid()
	if mode == "object" and not selected_id.is_empty():
		var rect: Rect2 = document.art_rect(selected_id)
		draw_rect(rect, Color("66e6ff"), false, 2.0)
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color("d8c8a5"), false, 2.0)
	draw_set_transform(Vector2.ZERO)

## 在原地纹上绘制当前草稿的地面笔刷；空格仍直接显示原纹理。
func _draw_ground_patches() -> void:
	for patch: Dictionary in document.layout.get("ground_patches", []):
		var texture: Texture2D = _ground_stamps.get(String(patch.get("tile", "")))
		if texture == null:
			continue
		var cell: Array = patch["cell"]
		var origin := Vector2(int(cell[0]) * GROUND_CELL_SIZE, int(cell[1]) * GROUND_CELL_SIZE)
		var visible_size := Vector2(mini(GROUND_CELL_SIZE, int(SIZE.x - origin.x)),
			mini(GROUND_CELL_SIZE, int(SIZE.y - origin.y)))
		draw_texture_rect_region(texture, Rect2(origin, visible_size), Rect2(Vector2.ZERO, visible_size))

## 仅在地面模式显示稀疏格线和鼠标所在格，不覆盖实际运行贴图。
func _draw_ground_grid() -> void:
	var line_color := Color(0.9, 0.96, 0.93, 0.19)
	for col in range(1, 14):
		draw_line(Vector2(col * GROUND_CELL_SIZE, 0), Vector2(col * GROUND_CELL_SIZE, SIZE.y), line_color, 1.0)
	for row in range(1, 8):
		draw_line(Vector2(0, row * GROUND_CELL_SIZE), Vector2(SIZE.x, row * GROUND_CELL_SIZE), line_color, 1.0)
	if hovered_ground_cell.x >= 0:
		var rect := Rect2(Vector2(hovered_ground_cell * GROUND_CELL_SIZE), Vector2.ONE * GROUND_CELL_SIZE)
		rect = rect.intersection(Rect2(Vector2.ZERO, SIZE))
		draw_rect(rect, Color("6aebd0"), false, 2.0 / _scale_value())

## 高亮所选整体碰撞的顶点；白色大点是当前正在拖动的顶点。
func _draw_collision_handles() -> void:
	var points: PackedVector2Array = document.footprint(selected_id)
	if points.size() < 3:
		return
	var handle_radius := 6.0 / _scale_value()
	for index in range(points.size()):
		draw_circle(points[index], handle_radius,
			Color("fff3c2") if index == selected_vertex else Color("ff714a"))
		draw_circle(points[index], handle_radius * 0.47, Color("421e18"))

## 绘制一张整体实体背层或前沿；保留图像透明像素和固定画面矩形。
func _draw_layer(item: Dictionary, layer: String) -> void:
	if not item.has(layer):
		return
	var path := String(item[layer])
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D
	var texture: Texture2D = _textures[path]
	if texture != null:
		var rect: Array = item["rect"]
		draw_texture_rect(texture, Rect2(rect[0], rect[1], rect[2], rect[3]), false)

## 绘制一个整体碰撞多边形轮廓，不把围栏或房屋拆成格子碰撞。
func _draw_closed_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	for index in range(points.size()):
		draw_line(points[index], points[(index + 1) % points.size()], color, width)

## 绘制当前布局中的道路控制线；道路原贴图在正式应用后重建。
func _draw_road_guides() -> void:
	var paths: Array = [document.layout["main_road"]] + document.layout["branches"]
	for path_index in range(paths.size()):
		var points: Array = paths[path_index]
		for index in range(points.size()):
			var point := Vector2(points[index][0], points[index][1])
			if index > 0:
				var previous := Vector2(points[index - 1][0], points[index - 1][1])
				draw_line(previous, point, Color(0.2, 0.8, 0.95, 0.7), 2.0)
			var active := path_index - 1 == selected_branch and index == selected_point
			draw_circle(point, 6.0 if active else 3.2, Color("62e9fa") if active else Color(0.15, 0.6, 0.78, 0.75))

## 由正式 NPC 网格坐标绘制固定落点，避免预览只显示近似的原画目标。
func _draw_targets() -> void:
	var world_rect: Array = document.layout["world_rect"]
	for npc: Dictionary in _npc_cells:
		var cell: Array = npc["cell"]
		var world := Vector2((cell[0] - cell[1]) * 32.0, -(cell[0] + cell[1]) * 16.0)
		var pixel := Vector2((world.x - world_rect[0]) / world_rect[2] * SIZE.x,
			(world.y - world_rect[1]) / world_rect[3] * SIZE.y)
		draw_circle(pixel, 5.0, Color("5bf0a3"))
		draw_string(ThemeDB.fallback_font, pixel + Vector2(8, -8), String(npc["role"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("eaffef"))

## 命中最上层整体精灵，避免点击建筑时误选背后的道路控制点。
func _pick_object(point: Vector2) -> String:
	var objects: Array = document.manifest.get("objects", []).duplicate()
	objects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["foot_y"]) > int(b["foot_y"]))
	for item: Dictionary in objects:
		if document.art_rect(String(item["id"])).has_point(point):
			return String(item["id"])
	return ""

## 命中最近道路节点，返回 [支路索引、节点索引]；主路索引为 -1。
func _pick_road_point(point: Vector2) -> Vector2i:
	var paths: Array = [document.layout["main_road"]] + document.layout["branches"]
	var best := Vector2i(-2, -1)
	var distance := 12.0 / _scale_value()
	for path_index in range(paths.size()):
		for index in range(paths[path_index].size()):
			var raw: Array = paths[path_index][index]
			var current := Vector2(raw[0], raw[1]).distance_to(point)
			if current < distance:
				distance = current
				best = Vector2i(path_index - 1, index)
	return best

## 将画布位置转换为 128 像素地面格；画布外返回无效格。
func _ground_cell_at(point: Vector2) -> Vector2i:
	if point.x < 0 or point.y < 0 or point.x >= SIZE.x or point.y >= SIZE.y:
		return Vector2i(-1, -1)
	return Vector2i(int(point.x / GROUND_CELL_SIZE), int(point.y / GROUND_CELL_SIZE))

## 命中所选对象最近的顶点；拾取半径按屏幕像素固定，缩放后仍可操作。
func _pick_collision_vertex(point: Vector2) -> int:
	var points: PackedVector2Array = document.footprint(selected_id)
	var limit := 12.0 / _scale_value()
	var best := -1
	for index in range(points.size()):
		var distance := points[index].distance_to(point)
		if distance < limit:
			limit = distance
			best = index
	return best

## 在全部整体碰撞中寻找最近的线段，碰撞线优先于美术矩形命中。
## 距离按屏幕像素计算，避免缩放后细线难以选中。
func _pick_collision_edge(point: Vector2) -> Dictionary:
	var limit := 16.0 / _scale_value()
	var best := {"id": "", "edge": -1, "point": Vector2.ZERO}
	for item: Dictionary in document.manifest.get("objects", []):
		var object_id := String(item["id"])
		var points: PackedVector2Array = document.footprint(object_id)
		for index in range(points.size()):
			var closest := Geometry2D.get_closest_point_to_segment(point, points[index],
				points[(index + 1) % points.size()])
			var distance := closest.distance_to(point)
			if distance < limit:
				limit = distance
				best = {"id": object_id, "edge": index, "point": closest}
	return best

## 空格作为画布平移修饰键，不抢占编辑器其他键盘输入。
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.keycode == KEY_SPACE or key.physical_keycode == KEY_SPACE:
			_space_held = key.pressed

## 将笔刷放入鼠标路径经过的所有格；快速拖动也不留空洞。
## 撤销记录由鼠标按放管理，而不是每个格子各记一次。
func _paint_ground(point: Vector2) -> void:
	var cell := _ground_cell_at(point)
	if cell.x < 0:
		return
	var from_cell := _last_ground_cell if _last_ground_cell.x >= 0 else cell
	var steps := maxi(absi(cell.x - from_cell.x), absi(cell.y - from_cell.y))
	for step in range(steps + 1):
		var current := Vector2i(Vector2(from_cell).lerp(Vector2(cell),
			float(step) / float(maxi(steps, 1))).round())
		if document.ground_patch_at(current) != brush_id:
			document.set_ground_patch(current, brush_id)
	_last_ground_cell = cell
	selection_changed.emit("地面格 (%d,%d)" % [cell.x, cell.y])
	queue_redraw()

## 处理四种编辑模式、缩放和平移；一次按下到松开只产生一个撤销记录。
func _gui_input(event: InputEvent) -> void:
	if document == null or document.layout.is_empty():
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = button.pressed
			_pan_button = MOUSE_BUTTON_MIDDLE if button.pressed else MOUSE_BUTTON_NONE
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed \
				and (_space_held or Input.is_key_pressed(KEY_SPACE)):
			_panning = true
			_pan_button = MOUSE_BUTTON_LEFT
			_dragging = false
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed \
				and _pan_button == MOUSE_BUTTON_LEFT:
			_panning = false
			_pan_button = MOUSE_BUTTON_NONE
			accept_event()
			return
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before := screen_to_canvas(button.position)
			zoom_factor = clampf(zoom_factor * (1.15 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.5, 4.0)
			pan += button.position - (_origin() + before * _scale_value())
			queue_redraw()
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed and mode == "collision" \
				and not selected_id.is_empty():
			var remove_index := _pick_collision_vertex(screen_to_canvas(button.position))
			if remove_index >= 0:
				document.begin_change()
				if document.remove_collision_vertex(selected_id, remove_index):
					document.finish_change()
					document_changed.emit()
				else:
					document.finish_change()
				selected_vertex = -1
				queue_redraw()
				accept_event()
			return
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_drag_start = screen_to_canvas(button.position)
			_last_delta = Vector2i.ZERO
			_last_ground_cell = Vector2i(-1, -1)
			match mode:
				"object":
					selected_id = _pick_object(_drag_start)
					selection_changed.emit(selected_id)
					_dragging = not selected_id.is_empty()
				"road":
					var picked := _pick_road_point(_drag_start)
					selected_branch = picked.x
					selected_point = picked.y
					_dragging = picked.x >= -1 and picked.y >= 0
					selection_changed.emit("道路控制点" if _dragging else "")
				"ground":
					_dragging = _ground_cell_at(_drag_start).x >= 0
				"collision":
					var hit := _pick_collision_edge(_drag_start)
					if button.shift_pressed and int(hit["edge"]) >= 0:
						selected_id = String(hit["id"])
						selection_changed.emit(selected_id)
						var points: PackedVector2Array = document.footprint(selected_id)
						var edge := int(hit["edge"])
						var insert_at: Vector2 = hit["point"]
						var next := points[(edge + 1) % points.size()]
						if insert_at.distance_to(points[edge]) < 4.0 / _scale_value() \
								or insert_at.distance_to(next) < 4.0 / _scale_value():
							insert_at = (points[edge] + next) * 0.5
						if points[edge].distance_to(next) > 8.0 / _scale_value():
							document.begin_change()
							selected_vertex = document.insert_collision_vertex(selected_id, edge,
								Vector2i(insert_at.round()))
							_dragging = selected_vertex >= 0
							if not _dragging:
								document.finish_change()
							queue_redraw()
							accept_event()
							return
					selected_vertex = _pick_collision_vertex(_drag_start) if not selected_id.is_empty() else -1
					if selected_vertex < 0:
						selected_id = String(hit["id"]) if int(hit["edge"]) >= 0 else _pick_object(_drag_start)
						selection_changed.emit(selected_id)
						_dragging = false
					else:
						_dragging = true
			if _dragging:
				document.begin_change()
				if mode == "ground":
					_paint_ground(_drag_start)
		else:
			if _dragging:
				document.finish_change()
				document_changed.emit()
			_dragging = false
			_last_ground_cell = Vector2i(-1, -1)
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if mode == "ground":
			hovered_ground_cell = _ground_cell_at(screen_to_canvas(motion.position))
			queue_redraw()
		if _panning:
			pan += motion.relative
			queue_redraw()
		elif _dragging:
			var location := screen_to_canvas(motion.position)
			match mode:
				"object":
					var total := Vector2i((location - _drag_start).round())
					document.move_object(selected_id, total - _last_delta)
					_last_delta = total
				"road":
					document.move_road_point(selected_branch, selected_point, Vector2i(location.round()))
				"ground":
					_paint_ground(location)
				"collision":
					document.move_collision_vertex(selected_id, selected_vertex, Vector2i(location.round()))
			queue_redraw()
		accept_event()
