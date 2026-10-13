class_name IsoGround
extends Node2D
## 等距地面（M1 占位实现：程序化绘制）与边界碰撞。
##
## 依据：产品文档 7.1（64×32 等距瓦片）、7.2（禁止 corner cutting）。
## 说明：M1 用程序化绘制做占位；后续（M3）替换为 TileMapLayer + 正式素材时，
## 本节点对外接口（get_map_center_world / get_world_bounds）保持不变，上层无需改动。

@export var map_id: String = "camp"
@export var sample_camp_theme := false

const CAMP_TILES := [
	preload("res://assets/tiles/camp/tile_0.png"),
	preload("res://assets/tiles/camp/tile_1.png"),
	preload("res://assets/tiles/camp/tile_2.png"),
	preload("res://assets/tiles/camp/tile_3.png"),
]
const WILD_TILES := [
	preload("res://assets/tiles/wild/tile_0.png"),
	preload("res://assets/tiles/wild/tile_1.png"),
	preload("res://assets/tiles/wild/tile_2.png"),
	preload("res://assets/tiles/wild/tile_3.png"),
]
const ASH_TILES := [
	preload("res://assets/tiles/ash/tile_0.png"),
	preload("res://assets/tiles/ash/tile_1.png"),
	preload("res://assets/tiles/ash/tile_2.png"),
	preload("res://assets/tiles/ash/tile_3.png"),
]

const WALL_THICKNESS := 10.0
const COLOR_FILL := Color("36423a")     # 地面底色
const COLOR_GRID := Color("44564a")     # 网格线
const COLOR_BORDER := Color("5f7563")   # 外边框

var map_data: Dictionary = {}
var grid_size: Vector2i = Vector2i(40, 40)

func _ready() -> void:
	z_index = -4096
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# M3-1：地面按「当前地图」加载。Game.tscn 的 @export map_id 仅作编辑器预览默认值，
	# 运行时一律以 GameState.current_map 为准（切图 = 重载场景，见 MapService 头注）。
	var cur := String(GameState.current_map)
	if not cur.is_empty():
		map_id = cur
	_load_map()
	if map_id == "camp" or sample_camp_theme:
		add_child(preload("res://scripts/world/sample_camp_props.gd").new())
	elif map_id == "wild_trial" or map_id == "ash_land":
		var props := preload("res://scripts/world/environment_props.gd").new()
		props.map_id = map_id
		add_child(props)
	_build_boundary()
	queue_redraw()

func _load_map() -> void:
	var m = DataLoader.get_entry("maps", map_id)
	if m == null:
		push_warning("[IsoGround] 未找到地图数据 '%s'，回退默认尺寸 %s" % [map_id, grid_size])
		return
	map_data = m
	var s = m.get("size", null)
	if s is Dictionary:
		grid_size = Vector2i(int(s.get("w", grid_size.x)), int(s.get("h", grid_size.y)))

## 地图中心的世界坐标（用作玩家出生点）
func get_map_center_world() -> Vector2:
	return Iso.grid_to_world(Vector2i(grid_size.x / 2, grid_size.y / 2))

## 把世界坐标夹回地图可用范围（M1-10 读档坐标容错）：
## 坏档 / 版本变更导致坐标越界时，玩家仍会落在边界内而不是墙外。
func clamp_to_map(world: Vector2) -> Vector2:
	var g := Iso.world_to_grid(world)
	var margin := 2.0
	var hi_x := maxf(margin, float(grid_size.x - 1) - margin)
	var hi_y := maxf(margin, float(grid_size.y - 1) - margin)
	return Iso.grid_pt(clampf(g.x, margin, hi_x), clampf(g.y, margin, hi_y))

## 地图（菱形区域）的世界包围盒，用于相机限制
func get_world_bounds() -> Rect2:
	var pts := _outer_corners()
	var min_x: float = pts[0].x
	var max_x: float = pts[0].x
	var min_y: float = pts[0].y
	var max_y: float = pts[0].y
	for p in pts:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_y = min(min_y, p.y)
		max_y = max(max_y, p.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

## 菱形区域的四个外角（按 E→N→W→S 顺序，即顺时针外边界）
func _outer_corners() -> PackedVector2Array:
	var w := grid_size.x
	var h := grid_size.y
	return PackedVector2Array([
		Iso.tile_corner(Vector2i(w - 1, 0), Iso.DIR_E),
		Iso.tile_corner(Vector2i(w - 1, h - 1), Iso.DIR_N),
		Iso.tile_corner(Vector2i(0, h - 1), Iso.DIR_W),
		Iso.tile_corner(Vector2i(0, 0), Iso.DIR_S),
	])

func _build_boundary() -> void:
	var pts := _outer_corners()
	var body := StaticBody2D.new()
	body.name = "Boundary"
	add_child(body)
	for i in range(pts.size()):
		_add_wall(body, pts[i], pts[(i + 1) % pts.size()])

func _add_wall(body: StaticBody2D, a: Vector2, b: Vector2) -> void:
	var seg := b - a
	var shape := RectangleShape2D.new()
	shape.size = Vector2(seg.length() + WALL_THICKNESS, WALL_THICKNESS)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = (a + b) * 0.5
	cs.rotation = seg.angle()
	body.add_child(cs)

func _draw() -> void:
	var w := grid_size.x
	var h := grid_size.y
	var corners := _outer_corners()

	# 地面填充（整块菱形，一次绘制）
	var camp_style := map_id == "camp" or sample_camp_theme
	var themed := camp_style or map_id == "wild_trial" or map_id == "ash_land"
	var fill := Color("806346") if camp_style else (Color("515a42") if map_id == "wild_trial" else Color("4b4443"))
	draw_colored_polygon(corners, fill if themed else COLOR_FILL)
	if themed:
		var tiles: Array = CAMP_TILES if camp_style else (WILD_TILES if map_id == "wild_trial" else ASH_TILES)
		for col in range(w):
			for row in range(h):
				var tile := 0
				var variation := posmod(col * 73 + row * 37 + col * row * 11, 19)
				if variation < 4:
					tile = 1
				elif variation == 5:
					tile = 2
				var road_center := 20 if sample_camp_theme else h / 2
				if camp_style and (absi(row - road_center) <= 1 or absi(col - road_center) <= 1):
					tile = 3
				if not camp_style and absi(row - h / 2) <= 1:
					tile = 3
				draw_texture(tiles[tile], Iso.grid_to_world(Vector2i(col, row)) - Vector2(32, 16))
		var camp_outline := PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]])
		draw_polyline(camp_outline, Color("a89978") if camp_style else Color("747565"), 2.0)
		return

	# 网格线：两组共 w+h+2 条（性能友好，避免逐格绘制）
	var lines := PackedVector2Array()
	for i in range(-1, w):
		lines.append(Iso.grid_pt(float(i) + 0.5, -0.5))
		lines.append(Iso.grid_pt(float(i) + 0.5, float(h) - 0.5))
	for j in range(-1, h):
		lines.append(Iso.grid_pt(-0.5, float(j) + 0.5))
		lines.append(Iso.grid_pt(float(w) - 0.5, float(j) + 0.5))
	draw_multiline(lines, COLOR_GRID, 1.0)

	# 外边框
	var outline := PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]])
	draw_polyline(outline, COLOR_BORDER, 2.0)
