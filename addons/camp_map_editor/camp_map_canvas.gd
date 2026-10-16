@tool
extends Control
## 营地编辑器画布：以屏幕矩形坐标绘制当前地面、道路、整体分层和碰撞。
## 仅响应编辑器鼠标，不参与运行场景，也不修改正式地图文件。

signal selection_changed(object_id: String)
signal document_changed()

const SIZE := Vector2(1672, 941)
const GROUND := "res://assets/maps/camp_style_full_b_v2/ground_tile.png"
const ROAD := "res://assets/maps/camp_style_full_b_v2/roads_and_shadows.png"

var document: RefCounted
var mode := "object"
var selected_id := ""
var selected_branch := -1
var selected_point := -1
var show_collision := true
var show_targets := true
var zoom_factor := 1.0
var pan := Vector2.ZERO
var _ground: Texture2D
var _road: Texture2D
var _textures: Dictionary = {}
var _npc_cells: Array = []
var _dragging := false
var _panning := false
var _drag_start := Vector2.ZERO
var _last_delta := Vector2i.ZERO

## 进入编辑器时加载已导入的运行贴图，所有对象复用相同纹理实例。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ground = load(GROUND) as Texture2D
	_road = load(ROAD) as Texture2D
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
	if _road != null:
		draw_texture_rect(_road, Rect2(Vector2.ZERO, SIZE), false)
	var objects: Array = document.manifest.get("objects", []).duplicate()
	objects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["foot_y"]) < int(b["foot_y"]))
	for item: Dictionary in objects:
		_draw_layer(item, "back")
	for item: Dictionary in objects:
		_draw_layer(item, "front")
	if show_collision:
		for item: Dictionary in objects:
			var polygon: PackedVector2Array = document.footprint(String(item["id"]))
			if polygon.size() > 2:
				var tint := Color(1.0, 0.35, 0.2, 0.8) if String(item["id"]) == selected_id else Color(1.0, 0.28, 0.2, 0.38)
				_draw_closed_polyline(polygon, tint, 2.0)
	if show_targets:
		_draw_targets()
	if mode == "road":
		_draw_road_guides()
	if not selected_id.is_empty():
		var rect: Rect2 = document.art_rect(selected_id)
		draw_rect(rect, Color("66e6ff"), false, 2.0)
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color("d8c8a5"), false, 2.0)
	draw_set_transform(Vector2.ZERO)

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

## 处理选择、拖拽、缩放和平移；一次按下到松开只产生一个撤销记录。
func _gui_input(event: InputEvent) -> void:
	if document == null or document.layout.is_empty():
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = button.pressed
			accept_event()
			return
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before := screen_to_canvas(button.position)
			zoom_factor = clampf(zoom_factor * (1.15 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.5, 4.0)
			pan += button.position - (_origin() + before * _scale_value())
			queue_redraw()
			accept_event()
			return
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_drag_start = screen_to_canvas(button.position)
			_last_delta = Vector2i.ZERO
			if mode == "object":
				selected_id = _pick_object(_drag_start)
				selection_changed.emit(selected_id)
				_dragging = not selected_id.is_empty()
			else:
				var picked := _pick_road_point(_drag_start)
				selected_branch = picked.x
				selected_point = picked.y
				_dragging = picked.x >= -1 and picked.y >= 0
				selection_changed.emit("道路控制点" if _dragging else "")
			if _dragging:
				document.begin_change()
		else:
			if _dragging:
				document.finish_change()
				document_changed.emit()
			_dragging = false
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _panning:
			pan += motion.relative
			queue_redraw()
		elif _dragging:
			var location := screen_to_canvas(motion.position)
			if mode == "object":
				var total := Vector2i((location - _drag_start).round())
				document.move_object(selected_id, total - _last_delta)
				_last_delta = total
			else:
				document.move_road_point(selected_branch, selected_point, Vector2i(location.round()))
			queue_redraw()
		accept_event()
