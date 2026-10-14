class_name IsoGround
extends Node2D
## 等距地面、纹理图集合批与静态边界碰撞；第一章从布局文件读取道路和多格实体。
## 地面仍采用 64×32 网格，通行与绘制共用运行布局掩码；第二章沿用现有地形路径。

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
	preload("res://assets/tiles/chapter1_v2/ash_land/road_soft.png"),
]
const CAVE_TILES := [
	preload("res://assets/tiles/cave/tile_0.png"),
	preload("res://assets/tiles/cave/tile_1.png"),
	preload("res://assets/tiles/cave/tile_2.png"),
	preload("res://assets/tiles/cave/tile_3.png"),
]
const CH1_CAMP_EDGES := [
	preload("res://assets/tiles/chapter1_v2/camp/road_edge_n.png"), preload("res://assets/tiles/chapter1_v2/camp/road_edge_e.png"),
	preload("res://assets/tiles/chapter1_v2/camp/road_edge_s.png"), preload("res://assets/tiles/chapter1_v2/camp/road_edge_w.png"),
	preload("res://assets/tiles/chapter1_v2/camp/road_edge_ne.png"), preload("res://assets/tiles/chapter1_v2/camp/road_edge_se.png"),
	preload("res://assets/tiles/chapter1_v2/camp/road_edge_sw.png"), preload("res://assets/tiles/chapter1_v2/camp/road_edge_nw.png"),
]
const CH1_WILD_EDGES := [
	preload("res://assets/tiles/chapter1_v2/wild_trial/road_edge_n.png"), preload("res://assets/tiles/chapter1_v2/wild_trial/road_edge_e.png"),
	preload("res://assets/tiles/chapter1_v2/wild_trial/road_edge_s.png"), preload("res://assets/tiles/chapter1_v2/wild_trial/road_edge_w.png"),
	preload("res://assets/tiles/chapter1_v2/wild_trial/road_edge_ne.png"), preload("res://assets/tiles/chapter1_v2/wild_trial/road_edge_se.png"),
	preload("res://assets/tiles/chapter1_v2/wild_trial/road_edge_sw.png"), preload("res://assets/tiles/chapter1_v2/wild_trial/road_edge_nw.png"),
]
const CH1_ASH_EDGES := [
	preload("res://assets/tiles/chapter1_v2/ash_land/road_edge_n.png"), preload("res://assets/tiles/chapter1_v2/ash_land/road_edge_e.png"),
	preload("res://assets/tiles/chapter1_v2/ash_land/road_edge_s.png"), preload("res://assets/tiles/chapter1_v2/ash_land/road_edge_w.png"),
	preload("res://assets/tiles/chapter1_v2/ash_land/road_edge_ne.png"), preload("res://assets/tiles/chapter1_v2/ash_land/road_edge_se.png"),
	preload("res://assets/tiles/chapter1_v2/ash_land/road_edge_sw.png"), preload("res://assets/tiles/chapter1_v2/ash_land/road_edge_nw.png"),
]
const CH1_CAVE_EDGES := [
	preload("res://assets/tiles/chapter1_v2/corruption_source/road_edge_n.png"), preload("res://assets/tiles/chapter1_v2/corruption_source/road_edge_e.png"),
	preload("res://assets/tiles/chapter1_v2/corruption_source/road_edge_s.png"), preload("res://assets/tiles/chapter1_v2/corruption_source/road_edge_w.png"),
	preload("res://assets/tiles/chapter1_v2/corruption_source/road_edge_ne.png"), preload("res://assets/tiles/chapter1_v2/corruption_source/road_edge_se.png"),
	preload("res://assets/tiles/chapter1_v2/corruption_source/road_edge_sw.png"), preload("res://assets/tiles/chapter1_v2/corruption_source/road_edge_nw.png"),
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
var _chapter_one_art: ChapterOneMapArt = null
var _chapter_one_road_rows: Array = []

## 进入地图时装配布局、地面、第一章静态实体与碰撞；所有重建都在加载阶段完成。
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
	if map_id in ["camp", "wild_trial", "ash_land", "corruption_source"] and not sample_camp_theme:
		_load_chapter_one_art()
	elif sample_camp_theme:
		add_child(preload("res://scripts/world/sample_camp_props.gd").new())
	_build_boundary()
	queue_redraw()

## 读取当前地图元数据及逻辑尺寸；缺失条目时保留编辑器预览默认值。
func _load_map() -> void:
	var m = DataLoader.get_entry("maps", map_id)
	if m == null:
		push_warning("[IsoGround] 未找到地图数据 '%s'，回退默认尺寸 %s" % [map_id, grid_size])
		return
	map_data = m
	var s = m.get("size", null)
	if s is Dictionary:
		grid_size = Vector2i(int(s.get("w", grid_size.x)), int(s.get("h", grid_size.y)))

## 从当前布局版本读取第一章道路与实体文件，禁止使用旧固定装饰坐标。
func _load_chapter_one_art() -> void:
	var path := "res://data/map_art/chapter1_v2/%s.json" % map_id
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "缺少第一章地图美术布局：%s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "第一章地图美术布局无效：%s" % path)
	var art_data: Dictionary = parsed
	assert(String(art_data.get("layoutVersion", "")) == String(map_data.get("layoutVersion", "")),
		"第一章地图美术布局版本不一致：%s" % map_id)
	var extent: Array = art_data.get("grid_size", [])
	assert(extent.size() == 2 and Vector2i(int(extent[0]), int(extent[1])) == grid_size,
		"第一章地图美术尺寸不一致：%s" % map_id)
	_chapter_one_road_rows = art_data.get("road_rows", [])
	assert(_chapter_one_road_rows.size() == grid_size.y, "第一章道路行数不正确：%s" % map_id)
	_chapter_one_art = ChapterOneMapArt.new()
	_chapter_one_art.configure(map_id, art_data)
	add_child(_chapter_one_art)

## 返回离地图中心最近的合法世界坐标，供默认出生点使用。
func get_map_center_world() -> Vector2:
	var cell := Vector2i(grid_size.x / 2, grid_size.y / 2)
	return Iso.grid_to_world(cave.nearest_walkable(cell) if cave != null else cell)

## 将越界或已阻挡的世界位置修正到可走格，供读档和寻路目标容错。
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

## 查询运行掩码中的格通行状态；无掩码的预览地图按可走处理。
func is_walkable_cell(cell: Vector2i) -> bool:
	return cave == null or cave.is_walkable(cell)

## 判断井心动态门禁后方区域，其他地图恒为未锁定。
func is_locked_boss_area(world: Vector2) -> bool:
	return cave != null and cave.is_behind_access_gate(Vector2i(Iso.world_to_grid(world).round()))

## 第二章井心通行解锁后更新导航与墙碰撞，第一章无此动态门禁。
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

## 用同一布局掩码规划世界坐标路线；无布局时直接返回目标点。
func route(from_world: Vector2, to_world: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if cave == null:
		result.append(to_world)
		return result
	var start := Vector2i(Iso.world_to_grid(from_world).round())
	var finish := Vector2i(Iso.world_to_grid(to_world).round())
	return cave.smooth_path(from_world, cave.path(start, finish))

## 返回投影后地图的世界包围盒，供相机限制使用。
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

## 按投影顺序求外边界四角，供底图、边框与物理边界共用。
func _outer_corners() -> PackedVector2Array:
	var w := grid_size.x
	var h := grid_size.y
	return PackedVector2Array([
		Iso.tile_corner(Vector2i(w - 1, 0), Iso.DIR_E),
		Iso.tile_corner(Vector2i(w - 1, h - 1), Iso.DIR_N),
		Iso.tile_corner(Vector2i(0, h - 1), Iso.DIR_W),
		Iso.tile_corner(Vector2i(0, 0), Iso.DIR_S),
	])

## 创建地图外边界和布局阻挡碰撞；第一章阻挡由多格实体提供。
func _build_boundary() -> void:
	var pts := _outer_corners()
	var body := StaticBody2D.new()
	body.name = "Boundary"
	add_child(body)
	for i in range(pts.size()):
		_add_wall(body, pts[i], pts[(i + 1) % pts.size()])
	_build_cave_walls()

## 建立静态阻挡体；第一章每个大实体一个合并轮廓，其他图复用逐边缘形状。
func _build_cave_walls() -> void:
	if cave == null:
		return
	var rock := StaticBody2D.new()
	rock.name = "CaveWalls"
	add_child(rock)
	if _chapter_one_art != null:
		_chapter_one_art.add_collisions_to(rock)
		return
	# Every wall uses the same immutable diamond; only node positions differ.
	var shape := ConvexPolygonShape2D.new()
	shape.points = PackedVector2Array([Vector2(-31, 0), Vector2(0, -15), Vector2(31, 0), Vector2(0, 15)])
	for cell in cave.boundary_cells():
		var hit := CollisionShape2D.new()
		hit.shape = shape
		hit.position = Iso.grid_to_world(cell)
		rock.add_child(hit)

## 将一条外边界线段转为矩形碰撞形状，不影响内部布局掩码。
func _add_wall(body: StaticBody2D, a: Vector2, b: Vector2) -> void:
	var seg := b - a
	var shape := RectangleShape2D.new()
	shape.size = Vector2(seg.length() + WALL_THICKNESS, WALL_THICKNESS)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = (a + b) * 0.5
	cs.rotation = seg.angle()
	body.add_child(cs)

## 绘制纹理地面、阻挡顶面和洞壁外观；只在装载或显式失效时重绘。
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
		_draw_chapter_one_blocked_floor()
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

## 用一次图集网格绘制全部可走格；道路索引来自同版本布局，不按旧中线猜测。
## 透明瓦片仍保持原来的列、行插入顺序，以免破坏等距遮盖。
func _draw_tile_floor(tiles: Array, cave_style: bool = false, camp_style: bool = false) -> void:
	var active_tiles: Array = tiles
	if not _chapter_one_road_rows.is_empty():
		active_tiles = tiles + _chapter_one_road_edges()
	if _tile_atlas == null or _atlas_tiles != active_tiles:
		var atlas := Image.create(64 * active_tiles.size(), 32, false, Image.FORMAT_RGBA8)
		for i in range(active_tiles.size()):
			var image := (active_tiles[i] as Texture2D).get_image()
			assert(image.get_size() == Vector2i(64, 32), "Floor tiles must be 64x32")
			image.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(image, Rect2i(0, 0, 64, 32), Vector2i(i * 64, 0))
		_tile_atlas = ImageTexture.create_from_image(atlas)
		_atlas_tiles = active_tiles
	var builder := FlatTileMesh.new(grid_size.x * grid_size.y, true)
	for col in range(grid_size.x):
		for row in range(grid_size.y):
			var cell := Vector2i(col, row)
			if cave != null and not cave.is_walkable(cell):
				continue
			var variation := posmod(col * 73 + row * 37 + col * row * 11, 19)
			var tile := 1 if variation < 4 else 2 if variation == 5 else 0
			if not _chapter_one_road_rows.is_empty():
				var road_tile := _chapter_one_road_tile_index(cell)
				if road_tile >= 0:
					tile = road_tile
			elif not cave_style:
				var road_center := 20 if sample_camp_theme else grid_size.y / 2
				if camp_style and (absi(row - road_center) <= 1 or absi(col - road_center) <= 1):
					tile = 3
				if not camp_style and absi(row - grid_size.y / 2) <= 1:
					tile = 3
			var origin := Iso.grid_to_world(cell) - Vector2(32, 16)
			var u0 := float(tile) / active_tiles.size()
			var u1 := float(tile + 1) / active_tiles.size()
			builder.add_quad(PackedVector2Array([
				origin, origin + Vector2(64, 0), origin + Vector2(64, 32), origin + Vector2(0, 32),
			]), PackedVector2Array([Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)]))
	_tile_mesh = builder.build()
	if _tile_mesh != null:
		draw_mesh(_tile_mesh, _tile_atlas, Transform2D.IDENTITY, Color("a9aaae") if cave_style else Color.WHITE)

## 返回本图八张 1×1 道路边缘/转角纹理；第二章不调用。
func _chapter_one_road_edges() -> Array:
	match map_id:
		"camp": return CH1_CAMP_EDGES
		"wild_trial": return CH1_WILD_EDGES
		"ash_land": return CH1_ASH_EDGES
		"corruption_source": return CH1_CAVE_EDGES
	return []

## 根据四邻格路面记录选中心、单边或双边过渡；返回 -1 表示普通地砖。
func _chapter_one_road_tile_index(cell: Vector2i) -> int:
	if String(_chapter_one_road_rows[cell.y])[cell.x] == "1":
		return 3
	var bits := 0
	for pair in [[Vector2i(0, -1), 1], [Vector2i(1, 0), 2],
			[Vector2i(0, 1), 4], [Vector2i(-1, 0), 8]]:
		var neighbor: Vector2i = cell + pair[0]
		if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < grid_size.x and neighbor.y < grid_size.y:
			if String(_chapter_one_road_rows[neighbor.y])[neighbor.x] == "1":
				bits |= int(pair[1])
	match bits:
		0: return -1
		1: return 4
		2: return 5
		4: return 6
		8: return 7
		3: return 8
		6: return 9
		12: return 10
		9: return 11
	return 3

## 合批画出新版布局的阻挡顶面；大型实体再覆盖轮廓细节。
func _draw_chapter_one_blocked_floor() -> void:
	if cave == null or _chapter_one_art == null:
		return
	var cells := cave.blocked_cells()
	var builder := FlatTileMesh.new(cells.size(), true)
	var tile_count := _atlas_tiles.size()
	for cell: Vector2i in cells:
		var variation := posmod(cell.x * 17 + cell.y * 23, 7)
		var tile := 2 if variation == 0 else 1 if variation == 1 else 0
		var origin := Iso.grid_to_world(cell) - Vector2(32, 16)
		var u0 := float(tile) / tile_count
		var u1 := float(tile + 1) / tile_count
		builder.add_quad(PackedVector2Array([
			origin, origin + Vector2(64, 0), origin + Vector2(64, 32), origin + Vector2(0, 32),
		]), PackedVector2Array([Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)]))
	_blocked_mesh = builder.build()
	if _blocked_mesh == null:
		return
	var color := Color("777067") if map_id == "camp" else Color("69745e") if map_id == "wild_trial" else Color("6c6161")
	draw_mesh(_blocked_mesh, _tile_atlas, Transform2D.IDENTITY, color)

## 收集可走格邻接洞壁的可见边，并统计端点以区分连续面与断头。
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

## 向本帧洞壁绘制列表增加一条边，同时累加两个端点的连接数。
func _add_cave_wall_edge(a: Vector2, b: Vector2, cell: Vector2i, wall_edges: Array, endpoint_counts: Dictionary) -> void:
	wall_edges.append({"a": a, "b": b, "cell": cell})
	for point in [a, b]:
		var key := Vector2i(point)
		endpoint_counts[key] = int(endpoint_counts.get(key, 0)) + 1

## 在屏幕朝向的洞壁边缘画低对比接缝，不生成新的碰撞。
func _draw_cave_seam(a: Vector2, b: Vector2, cell: Vector2i) -> void:
	var seed := posmod(cell.x * 17 + cell.y * 29, 5)
	var mid := a.lerp(b, 0.5) + Vector2(0, float(seed - 2))
	draw_polyline(PackedVector2Array([a, mid, b]), Color("433b32"), 2.0)

## 依据端点状态绘制连续洞壁立面及断头，保持现有低成本程序纹理。
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
