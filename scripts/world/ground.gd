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
const CAVE_TILES := [
	preload("res://assets/tiles/cave/tile_0.png"),
	preload("res://assets/tiles/cave/tile_1.png"),
	preload("res://assets/tiles/cave/tile_2.png"),
	preload("res://assets/tiles/cave/tile_3.png"),
]

const WALL_THICKNESS := 10.0
const COLOR_FILL := Color("36423a")     # 地面底色
const COLOR_GRID := Color("44564a")     # 网格线
const COLOR_BORDER := Color("5f7563")   # 外边框

var map_data: Dictionary = {}
var grid_size: Vector2i = Vector2i(40, 40)
var cave: CaveLayout = null
var _blocked_mesh: ArrayMesh
var _tile_mesh: ArrayMesh
var _tile_atlas: ImageTexture
var _atlas_tiles: Array = []

func _ready() -> void:
	z_index = -4096
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# M3-1：地面按「当前地图」加载。Game.tscn 的 @export map_id 仅作编辑器预览默认值，
	# 运行时一律以 GameState.current_map 为准（切图 = 重载场景，见 MapService 头注）。
	var cur := String(GameState.current_map)
	if not cur.is_empty():
		map_id = cur
	_load_map()
	var layout_path := String(map_data.get("layoutPath", ""))
	if not layout_path.is_empty():
		cave = CaveLayout.new(layout_path)
		assert(cave.size == grid_size, "Map size/layout mismatch: %s" % map_id)
		# Prepare once during loading, never on the first automatic-battle frame.
		cave.prepare_connectivity()
		if map_id == "c2_well_core":
			cave.set_access_gate_open(bool(GameState.unlocks.get("c2_core_access", false)))
			EventBus.quest_rewarded.connect(_on_quest_rewarded)
	if map_id == "corruption_source" and layout_path.is_empty():
		add_child(preload("res://scripts/world/cave_props.gd").new())
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
	var cell := Vector2i(grid_size.x / 2, grid_size.y / 2)
	return Iso.grid_to_world(cave.nearest_walkable(cell) if cave != null else cell)

## 把世界坐标夹回地图可用范围（M1-10 读档坐标容错）：
## 坏档 / 版本变更导致坐标越界时，玩家仍会落在边界内而不是墙外。
func clamp_to_map(world: Vector2) -> Vector2:
	var g := Iso.world_to_grid(world)
	var margin := 2.0
	var hi_x := maxf(margin, float(grid_size.x - 1) - margin)
	var hi_y := maxf(margin, float(grid_size.y - 1) - margin)
	var bounded := Iso.grid_pt(clampf(g.x, margin, hi_x), clampf(g.y, margin, hi_y))
	if cave == null:
		return bounded
	var cell := Vector2i(Iso.world_to_grid(bounded).round())
	return bounded if cave.is_walkable(cell) else Iso.grid_to_world(cave.nearest_walkable(cell))

func is_walkable_cell(cell: Vector2i) -> bool:
	return cave == null or cave.is_walkable(cell)

func is_locked_boss_area(world: Vector2) -> bool:
	return cave != null and cave.is_behind_access_gate(Vector2i(Iso.world_to_grid(world).round()))

func _on_quest_rewarded(_quest_id: String) -> void:
	if map_id != "c2_well_core" or cave == null or not bool(GameState.unlocks.get("c2_core_access", false)):
		return
	cave.set_access_gate_open(true)
	var walls := get_node_or_null("CaveWalls")
	if walls != null:
		walls.name = "RetiredCaveWalls"
		walls.queue_free()
	_build_cave_walls()
	queue_redraw()

func route(from_world: Vector2, to_world: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if cave == null:
		result.append(to_world)
		return result
	var start := Vector2i(Iso.world_to_grid(from_world).round())
	var finish := Vector2i(Iso.world_to_grid(to_world).round())
	return cave.smooth_path(from_world, cave.path(start, finish))

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
	_build_cave_walls()

func _build_cave_walls() -> void:
	if cave == null:
		return
	var rock := StaticBody2D.new()
	rock.name = "CaveWalls"
	add_child(rock)
	# Every wall uses the same immutable diamond; only node positions differ.
	var shape := ConvexPolygonShape2D.new()
	shape.points = PackedVector2Array([Vector2(-31, 0), Vector2(0, -15), Vector2(31, 0), Vector2(0, 15)])
	for cell in cave.boundary_cells():
		var hit := CollisionShape2D.new()
		hit.shape = shape
		hit.position = Iso.grid_to_world(cell)
		rock.add_child(hit)

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
	if cave != null and map_id == "corruption_source":
		# Cave void continues beyond the rectangular planning grid; the outer
		# isometric diamond is a camera extent, not a visible island edge.
		draw_rect(Rect2(-Vector2.ONE * 10000.0, Vector2.ONE * 20000.0), Color("090806"))
		_draw_tile_floor(CAVE_TILES, true)
		# 先铺地，再收集墙段。端点计数用来识别真正的断头，避免每格墙都露出方切面。
		var wall_edges: Array = []
		var endpoint_counts: Dictionary = {}
		for col in range(w):
			for row in range(h):
				var cell := Vector2i(col, row)
				if cave.is_walkable(cell):
					_collect_cave_edges(cell, Iso.grid_to_world(cell), wall_edges, endpoint_counts)
		for edge in wall_edges:
			_draw_cliff_face(edge.a, edge.b, edge.cell, endpoint_counts[Vector2i(edge.a)] == 1, endpoint_counts[Vector2i(edge.b)] == 1)
		return

	# 地面填充（整块菱形，一次绘制）
	var camp_style := map_id == "camp" or sample_camp_theme
	var themed := camp_style or map_id == "wild_trial" or map_id == "ash_land"
	var fill := Color("806346") if camp_style else (Color("515a42") if map_id == "wild_trial" else Color("4b4443"))
	draw_colored_polygon(corners, fill if themed else COLOR_FILL)
	if themed:
		var tiles: Array = CAMP_TILES if camp_style else (WILD_TILES if map_id == "wild_trial" else ASH_TILES)
		_draw_tile_floor(tiles, false, camp_style)
		var camp_outline := PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]])
		draw_polyline(camp_outline, Color("a89978") if camp_style else Color("747565"), 2.0)
		return

	if cave != null:
		var cells := cave.blocked_cells()
		var builder := FlatTileMesh.new(cells.size())
		for cell: Vector2i in cells:
			builder.add_quad(Iso.tile_points(cell))
		_blocked_mesh = builder.build()
		if _blocked_mesh != null:
			draw_mesh(_blocked_mesh, null, Transform2D.IDENTITY, Color("222b2b"))

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

## One tiny atlas avoids thousands of material/texture switches. Transparent
## tile rectangles retain their original col/row insertion order in the mesh.
func _draw_tile_floor(tiles: Array, cave_style: bool = false, camp_style: bool = false) -> void:
	if _tile_atlas == null or _atlas_tiles != tiles:
		var atlas := Image.create(64 * tiles.size(), 32, false, Image.FORMAT_RGBA8)
		for i in range(tiles.size()):
			var image := (tiles[i] as Texture2D).get_image()
			assert(image.get_size() == Vector2i(64, 32), "Floor tiles must be 64x32")
			image.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(image, Rect2i(0, 0, 64, 32), Vector2i(i * 64, 0))
		_tile_atlas = ImageTexture.create_from_image(atlas)
		_atlas_tiles = tiles
	var builder := FlatTileMesh.new(grid_size.x * grid_size.y, true)
	for col in range(grid_size.x):
		for row in range(grid_size.y):
			var cell := Vector2i(col, row)
			if cave != null and not cave.is_walkable(cell):
				continue
			var variation := posmod(col * 73 + row * 37 + col * row * 11, 19)
			var tile := 1 if variation < 4 else 2 if variation == 5 else 0
			if not cave_style:
				var road_center := 20 if sample_camp_theme else grid_size.y / 2
				if camp_style and (absi(row - road_center) <= 1 or absi(col - road_center) <= 1):
					tile = 3
				if not camp_style and absi(row - grid_size.y / 2) <= 1:
					tile = 3
			var origin := Iso.grid_to_world(cell) - Vector2(32, 16)
			var u0 := float(tile) / tiles.size()
			var u1 := float(tile + 1) / tiles.size()
			builder.add_quad(PackedVector2Array([
				origin, origin + Vector2(64, 0), origin + Vector2(64, 32), origin + Vector2(0, 32),
			]), PackedVector2Array([Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)]))
	_tile_mesh = builder.build()
	if _tile_mesh != null:
		draw_mesh(_tile_mesh, _tile_atlas, Transform2D.IDENTITY, Color("a9aaae") if cave_style else Color.WHITE)

func _collect_cave_edges(cell: Vector2i, center: Vector2, wall_edges: Array, endpoint_counts: Dictionary) -> void:
	# Rear edges hang down onto the floor, reading as an interior cave wall.
	if not cave.is_walkable(cell + Vector2i(1, 0)):
		_add_cave_wall_edge(center + Vector2(0, -16), center + Vector2(32, 0), cell, wall_edges, endpoint_counts)
	if not cave.is_walkable(cell + Vector2i(0, 1)):
		_add_cave_wall_edge(center + Vector2(-32, 0), center + Vector2(0, -16), cell, wall_edges, endpoint_counts)
	# The screen-facing edges stay flush with the floor. A thin rocky seam
	# joins stepped wall runs without adding another exposed cliff face.
	if not cave.is_walkable(cell + Vector2i(-1, 0)):
		_draw_cave_seam(center + Vector2(-32, 0), center + Vector2(0, 16), cell)
	if not cave.is_walkable(cell + Vector2i(0, -1)):
		_draw_cave_seam(center + Vector2(0, 16), center + Vector2(32, 0), cell)

func _add_cave_wall_edge(a: Vector2, b: Vector2, cell: Vector2i, wall_edges: Array, endpoint_counts: Dictionary) -> void:
	wall_edges.append({"a": a, "b": b, "cell": cell})
	for point in [a, b]:
		var key := Vector2i(point)
		endpoint_counts[key] = int(endpoint_counts.get(key, 0)) + 1

func _draw_cave_seam(a: Vector2, b: Vector2, cell: Vector2i) -> void:
	var seed := posmod(cell.x * 17 + cell.y * 29, 5)
	var mid := a.lerp(b, 0.5) + Vector2(0, float(seed - 2))
	draw_polyline(PackedVector2Array([a, mid, b]), Color("433b32"), 2.0)

func _draw_cliff_face(a: Vector2, b: Vector2, cell: Vector2i, cap_a: bool, cap_b: bool) -> void:
	var fall := Vector2(0, 21)
	var top := PackedVector2Array([a, a.lerp(b, 0.25) + Vector2(0, -2), a.lerp(b, 0.5) + Vector2(0, 2), a.lerp(b, 0.75) + Vector2(0, -3), b])
	var bottom := PackedVector2Array([
		top[0] + Vector2(0, 4) if cap_a else top[0] + fall,
		top[1] + fall + Vector2(0, 4), top[2] + fall,
		top[3] + fall + Vector2(0, 3),
		top[4] + Vector2(0, 4) if cap_b else top[4] + fall,
	])
	var face := PackedVector2Array([top[0], top[1], top[2], top[3], top[4], bottom[4], bottom[3], bottom[2], bottom[1], bottom[0]])
	draw_colored_polygon(face, Color("61594f"))
	draw_polyline(top, Color("a99b82"), 1.5)
	draw_polyline(bottom, Color("352f2b"), 1.5)
	for i in range(1, 5):
		var t := float(i) / 5.0
		var notch := a.lerp(b, t)
		var depth := 12.0 + float(posmod(cell.x * 17 + cell.y * 31 + i * 7, 10))
		draw_line(notch, notch + Vector2(1, depth), Color("302b28") if i % 2 == 0 else Color("928572"), 1.0)
