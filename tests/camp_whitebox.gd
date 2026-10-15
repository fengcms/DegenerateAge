extends Node2D
## 幸存者营地独立可玩白盒：将整图原画坐标映射为世界矩形，复用真实玩家和等距格导航。
## 供独立设计验收；读取正式营地的同一源文件，实体轮廓同时生成阻挡掩码和物理碰撞。

const LAYOUT_PATH := "res://data/map_art/camp_whitebox_v1.json"
const PLAYER_SCENE := preload("res://scenes/entities/Player.tscn")
const PLAYER_CLEARANCE := 14.0
const TARGET_LABELS := {
	"blacksmith": "铁匠", "warehouse": "仓库", "shop": "货郎", "elder": "长老",
	"carter": "车夫", "lamp": "镇灵灯", "training": "训练区",
	"north_exit": "往沉井镇", "east_exit": "往试炼野外",
}

var layout: Dictionary = {}
var canvas_size := Vector2.ZERO
var world_rect := Rect2()
var grid_size := Vector2i.ZERO
var player: PlayerCharacter
var _camera: Camera2D
var _astar := AStarGrid2D.new()
var _solid_polygons: Array[PackedVector2Array] = []
var _route: Array[Vector2] = []
var _overview := true
var _status: Label
var walkable_count := 0
var interior_count := 0

## 读取唯一白盒布局，在加载时建立绘制、导航、静态碰撞与玩家；不写正式营地数据。
func _ready() -> void:
	z_index = -4096
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	assert(file != null, "营地白盒布局缺失")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "营地白盒布局不是 JSON 对象")
	layout = parsed
	var source_size: Array = layout["reference_canvas"]
	canvas_size = Vector2(float(source_size[0]), float(source_size[1]))
	var rect: Array = layout["world_rect"]
	world_rect = Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	var extent: Array = layout["grid_size"]
	grid_size = Vector2i(int(extent[0]), int(extent[1]))
	assert(canvas_size.x > 0.0 and canvas_size.y > 0.0 and grid_size.x > 0 and grid_size.y > 0)
	_build_obstacles()
	_build_navigation()
	_build_player()
	_build_ui()
	set_overview(true)
	queue_redraw()

## 将原画上的像素坐标线性映射到白盒世界矩形，不改变玩家或地砖比例。
func canvas_to_world(raw: Array) -> Vector2:
	return world_rect.position + Vector2(float(raw[0]) / canvas_size.x * world_rect.size.x,
		float(raw[1]) / canvas_size.y * world_rect.size.y)

## 将一个原画多边形变为世界坐标；调用者负责其碰撞或绘制用途。
func _world_polygon(raw: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Array in raw:
		result.append(canvas_to_world(point))
	return result

## 从同一份实体和围栏数据生成物理形状，并缓存多边形供导航留边筛选。
func _build_obstacles() -> void:
	var body := StaticBody2D.new()
	body.name = "WhiteboxObstacles"
	add_child(body)
	for entity: Dictionary in layout["entities"]:
		_add_obstacle(body, _world_polygon(entity["footprint"]), String(entity["id"]))
	for fence: Dictionary in layout["fences"]:
		_add_obstacle(body, _world_polygon(fence["polygon"]), String(fence["id"]))
	var border := StaticBody2D.new()
	border.name = "WhiteboxBoundary"
	add_child(border)
	var a := world_rect.position
	var b := world_rect.end
	for segment: Array in [[Vector2(a.x, a.y), Vector2(b.x, a.y)],
		[Vector2(b.x, a.y), Vector2(b.x, b.y)],
		[Vector2(b.x, b.y), Vector2(a.x, b.y)],
		[Vector2(a.x, b.y), Vector2(a.x, a.y)]]:
		var middle: Vector2 = (segment[0] + segment[1]) * 0.5
		var edge: Vector2 = segment[1] - segment[0]
		var shape := RectangleShape2D.new()
		shape.size = Vector2(edge.length(), 16.0)
		var hit := CollisionShape2D.new()
		hit.shape = shape
		hit.position = middle
		hit.rotation = edge.angle()
		border.add_child(hit)

## 为一个完整实体挂一条接地碰撞多边形，避免逐格碰撞节点。
func _add_obstacle(body: StaticBody2D, polygon: PackedVector2Array, id: String) -> void:
	assert(polygon.size() >= 3, "白盒实体足迹至少需要三个点：%s" % id)
	var hit := CollisionPolygon2D.new()
	hit.name = id
	hit.polygon = polygon
	body.add_child(hit)
	_solid_polygons.append(polygon)

## 按等距格中心一次性编译通行掩码；实体轮廓、14 像素留边和画幅边界共享同一事实源。
func _build_navigation() -> void:
	_astar.region = Rect2i(Vector2i.ZERO, grid_size)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for row in range(grid_size.y):
		for col in range(grid_size.x):
			var cell := Vector2i(col, row)
			var center := Iso.grid_to_world(cell)
			if world_rect.grow(-PLAYER_CLEARANCE).has_point(center):
				interior_count += 1
			var blocked := _is_blocked_with_clearance(center)
			_astar.set_point_solid(cell, blocked)
			if not blocked:
				walkable_count += 1
	assert(walkable_count > 0, "白盒没有可通行区域")

## 判断世界点是否落在边界或实体 14 像素安全带内；仅在构建掩码时高频调用。
func _is_blocked_with_clearance(point: Vector2) -> bool:
	if not world_rect.grow(-PLAYER_CLEARANCE).has_point(point):
		return true
	for polygon: PackedVector2Array in _solid_polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
		for index in range(polygon.size()):
			var closest := Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])
			if point.distance_squared_to(closest) <= PLAYER_CLEARANCE * PLAYER_CLEARANCE:
				return true
	return false

## 装配现有玩家场景及其真实圆形碰撞体；自动战斗在设计样板里停用。
func _build_player() -> void:
	player = PLAYER_SCENE.instantiate() as PlayerCharacter
	player.z_as_relative = false
	add_child(player)
	player.global_position = canvas_to_world(layout["spawn"])
	var pilot := player.get_node_or_null("AutoPilot")
	if pilot != null:
		pilot.process_mode = Node.PROCESS_MODE_DISABLED
	_camera = player.get_node("Camera2D") as Camera2D
	_camera.position_smoothing_enabled = false
	assert(player.get_node("CollisionShape2D").shape is CircleShape2D)

## 创建不随镜头缩放的操作提示；可用 O 在全图和玩家视角间切换。
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "WhiteboxUI"
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(18, 14)
	_status.add_theme_color_override("font_color", Color("fff4d9"))
	_status.add_theme_font_size_override("font_size", 20)
	_status.text = "营地白盒 · O 切换全图/玩家视角 · 左键寻路 · WASD 移动"
	layer.add_child(_status)

## 以真实游戏窗口显示矩形全图，或切换到玩家的原尺寸跟随镜头。
func set_overview(enabled: bool) -> void:
	_overview = enabled
	_camera.top_level = enabled
	if enabled:
		_camera.global_position = world_rect.get_center()
		var viewport_size := get_viewport_rect().size
		var scale := minf((viewport_size.x - 40.0) / world_rect.size.x,
			(viewport_size.y - 90.0) / world_rect.size.y)
		_camera.zoom = Vector2.ONE * scale
	else:
		_camera.position = Vector2.ZERO
		_camera.zoom = Vector2.ONE
	_camera.make_current()

## 将世界点换算为最近的合法等距格，供点击目标和测试路线共用。
func _nearest_open(point: Vector2) -> Vector2i:
	var base := Vector2i(Iso.world_to_grid(point).round()).clamp(Vector2i.ZERO, grid_size - Vector2i.ONE)
	if not _astar.is_point_solid(base):
		return base
	for radius in range(1, maxi(grid_size.x, grid_size.y)):
		for row in range(maxi(0, base.y - radius), mini(grid_size.y - 1, base.y + radius) + 1):
			for col in range(maxi(0, base.x - radius), mini(grid_size.x - 1, base.x + radius) + 1):
				var cell := Vector2i(col, row)
				if not _astar.is_point_solid(cell):
					return cell
	return base

## 按白盒掩码返回实际格中心路线；空数组表示目标不可达。
func route_between(from_world: Vector2, to_world: Vector2) -> Array[Vector2]:
	var start := _nearest_open(from_world)
	var end := _nearest_open(to_world)
	var cells: Array[Vector2i] = _astar.get_id_path(start, end)
	var result: Array[Vector2] = []
	for cell: Vector2i in cells:
		result.append(Iso.grid_to_world(cell))
	return result

## 为现有玩家下达点击路线，路线在加载时构建的掩码中计算。
func navigate_to(target: Vector2) -> bool:
	_route = route_between(player.global_position, target)
	return not _route.is_empty()

## 用预定义服务点发出路线，供实机体验和验收脚本复用。
func navigate_to_target(id: String) -> bool:
	if not (layout["targets"] as Dictionary).has(id):
		return false
	return navigate_to(canvas_to_world(layout["targets"][id]))

## 驱动现有玩家沿等距 A* 路线移动；键盘手动操作时立即交还控制权。
func _physics_process(_delta: float) -> void:
	if player == null or _route.is_empty():
		return
	if Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > 0.05:
		_route.clear()
		player.set_auto_move(Vector2.ZERO)
		return
	while not _route.is_empty() and player.global_position.distance_to(_route[0]) < 11.0:
		_route.pop_front()
	player.set_auto_move(Vector2.ZERO if _route.is_empty() else player.global_position.direction_to(_route[0]))

## 响应白盒专用的视角切换和点击寻路；不接管正式游戏输入。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_O:
		set_overview(not _overview)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		navigate_to(get_global_mouse_position())

## 绘制单块矩形地面、路线及大型实体示意；每格不创建节点或单独绘制命令。
func _draw() -> void:
	if layout.is_empty():
		return
	draw_rect(world_rect, Color("81694f"))
	draw_rect(world_rect.grow(-24.0), Color("987854"), false, 16.0)
	draw_polyline(_world_polygon(layout["main_road"]), Color("c7ac79"), 82.0, true)
	for branch: Array in layout["branches"]:
		draw_polyline(_world_polygon(branch), Color("b29b75"), 54.0, true)
	for entity: Dictionary in layout["entities"]:
		if entity.has("visual"):
			var visual := _world_polygon(entity["visual"])
			draw_colored_polygon(visual, Color("66706b88"))
			draw_polyline(visual + PackedVector2Array([visual[0]]), Color("aaa9a3"), 4.0, true)
		var footprint := _world_polygon(entity["footprint"])
		draw_colored_polygon(footprint, Color("9c6058"))
		var center := Vector2.ZERO
		for vertex: Vector2 in footprint:
			center += vertex
		center /= float(footprint.size())
		draw_string(ThemeDB.fallback_font, center + Vector2(-32, -14), String(entity["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("fff4de"))
	for fence: Dictionary in layout["fences"]:
		draw_colored_polygon(_world_polygon(fence["polygon"]), Color("4c5145"))
	for id: String in layout["targets"]:
		var point := canvas_to_world(layout["targets"][id])
		draw_circle(point, 17.0, Color("f3d36e"))
		var label_position := point + (Vector2(-290, 9) if id == "east_exit" else Vector2(25, 9))
		draw_string(ThemeDB.fallback_font, label_position, String(TARGET_LABELS[id]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color("fff4de"))
