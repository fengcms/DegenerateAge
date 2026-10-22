extends Node
## 幸存者营地 B 第二版全图验收：核对开放外围、透明层、固定 NPC 和实走路线。
## 使用正式 Game 场景与布局，不写存档；窗口模式保存全图与局部截图。

const GAME := preload("res://scenes/Game.tscn")
const MANIFEST := "res://assets/maps/camp_style_full_b_v2/manifest.json"
const OPEN_PERIMETER := [Vector2i(63, 91), Vector2i(89, 65), Vector2i(42, 90),
	Vector2i(77, 46), Vector2i(65, 34), Vector2i(33, 34), Vector2i(18, 67),
	Vector2i(90, 42), Vector2i(66, 18), Vector2i(33, 44), Vector2i(46, 28)]
const NPC_CELLS := {"shop": Vector2i(43, 63), "quest": Vector2i(64, 48),
	"blacksmith": Vector2i(49, 78), "warehouse": Vector2i(72, 56),
	"carter": Vector2i(46, 33)}
const ROUTES := [
	{"id": "warehouse", "start": [930, 330], "end": [1350, 325]},
	{"id": "guardian_lamp", "start": [710, 430], "end": [870, 430]},
	{"id": "caravan", "start": [900, 610], "end": [1415, 690]},
	{"id": "training_fire", "start": [600, 620], "end": [710, 680]},
]

## 载入正式营地并逐项核对 B 全图图层、布局、NPC 与真实移动。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "camp"
	var world := GAME.instantiate()
	add_child(world)
	await get_tree().physics_frame
	var ground := world.get_node("Ground") as IsoGround
	var player := world.get_node("Entities/Player") as PlayerCharacter
	var camera := player.get_node("Camera2D") as Camera2D
	assert(ground.get_world_bounds().size == Vector2(3200, 1800)
		and ground.grid_size == Vector2i(110, 110), "营地矩形尺寸或通行网格变更")
	var layout: Dictionary = ground._camp_whitebox
	var expected_ids: Dictionary = {}
	var entity_ids: Dictionary = {}
	for entry: Dictionary in layout["entities"]:
		expected_ids[String(entry["id"])] = true
		entity_ids[String(entry["id"])] = true
	for entry: Dictionary in layout["fences"]:
		expected_ids[String(entry["id"])] = true
	assert(expected_ids.size() == 11 and ground.get_node("CaveWalls").get_child_count() == 11,
		"开放外围后应保持 7 个实体与 4 段训练场围栏")
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	assert(file != null, "全图清单缺失")
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	assert(String(manifest["layout_id"]) == String(layout["id"]), "美术与障碍版本不一致")
	var atlas := Image.new()
	var roads := Image.new()
	assert(atlas.load(String(manifest["ground_tile"])) == OK)
	assert(roads.load(String(manifest["road_overlay"])) == OK)
	assert(atlas.get_size() == Vector2i(2048, 2048) and atlas.get_pixel(0, 0).a > 0.99,
		"重复地纹应是不含物件的实体地表")
	for point: Vector2i in [Vector2i(100, 110), Vector2i(320, 480), Vector2i(800, 850)]:
		var color := atlas.get_pixelv(point)
		assert(color == atlas.get_pixelv(point + Vector2i(0, 1024))
			and color == atlas.get_pixelv(point + Vector2i(1024, 0)),
			"地表循环单元不得翻转草丛或石纹：%s" % point)
	assert(roads.get_size() == Vector2i(1672, 941) and roads.get_pixel(1600, 850).a < 0.01,
		"独立道路层空白区须真正透明")
	if manifest.has("ground_overlay"):
		var ground_patches := Image.new()
		assert(ground_patches.load(String(manifest["ground_overlay"])) == OK
			and ground_patches.get_size() == Vector2i(1672, 941)
			and ground._camp_ground_overlay != null, "已绘制地面必须以独立画布贴图加载")
	else:
		assert(ground._camp_ground_overlay == null, "未绘制地面时不应占用额外纹理")
	var actual_ids: Dictionary = {}
	var art_rects: Dictionary = {}
	for entry: Dictionary in manifest["objects"]:
		var id := String(entry["id"])
		assert(expected_ids.has(id) and not actual_ids.has(id), "新美术实体与原障碍不一致：%s" % id)
		actual_ids[id] = true
		art_rects[id] = entry["rect"]
		assert(ground.has_node("Camp_%s_front" % id), "实体前沿缺失：%s" % id)
		if entity_ids.has(id):
			assert(ground.has_node("Camp_%s_back" % id), "可绕行实体背层缺失：%s" % id)
			_check_split_alpha(entry)
	assert(actual_ids.size() == expected_ids.size() and ground._camp_foreground_count == 11,
		"保留的实体与障碍必须有整体视觉前沿")
	assert(float(art_rects["caravan"][2]) < float(art_rects["warehouse"][2]) * 0.75,
		"马车应明显小于仓库")
	assert(absf(float(art_rects["guardian_lamp"][2]) / float(art_rects["guardian_lamp"][3])
		- 0.56) < 0.02, "中央灯应保留源图宽高比")
	var blocked := _scan_original_footprints(ground, layout)
	assert(blocked > 150, "逐格障碍扫描覆盖不足")
	_check_open_perimeter(world, ground)
	_check_npc_positions(world, ground)
	print("[PERF] 营地 B 全图原障碍逐格扫描不可走格心：", blocked)
	for route: Dictionary in ROUTES:
		await _walk(world, ground, player, camera, route)
	if DisplayServer.get_name() != "headless":
		await _save_overview(world, ground, camera)
	print("[CampFullArtAcceptanceTest] PASS")
	print("[CampFullArtAcceptanceTest] 覆盖：全图 11 个整体实体、开放外围、固定 NPC 与四条实走路线")
	get_tree().quit()

## 检查原十一处外围障碍的位置已可走且没有遗留物理碰撞。
func _check_open_perimeter(world: Node2D, ground: IsoGround) -> void:
	var cave_walls := ground.get_node("CaveWalls") as StaticBody2D
	for cell: Vector2i in OPEN_PERIMETER:
		assert(ground.cave.is_walkable(cell), "已撤外围仍不可走：%s" % cell)
		var query := PhysicsPointQueryParameters2D.new()
		query.position = Iso.grid_to_world(cell)
		for hit: Dictionary in world.get_world_2d().direct_space_state.intersect_point(query):
			assert(hit.get("collider") != cave_walls, "已撤外围残留碰撞：%s" % cell)
	print("[PERF] 营地 B 第二版开放外围抽查点：", OPEN_PERIMETER.size())

## 核对一个可绕行整体精灵的前沿与背层 alpha 互斥，避免屋顶重复贴进地面。
func _check_split_alpha(entry: Dictionary) -> void:
	var back := Image.new()
	var front := Image.new()
	assert(back.load(String(entry["back"])) == OK and front.load(String(entry["front"])) == OK)
	assert(back.get_size() == front.get_size(), "整体实体分层尺寸不同：%s" % entry["id"])
	for y in range(back.get_height()):
		for x in range(back.get_width()):
			assert(back.get_pixel(x, y).a * front.get_pixel(x, y).a < 0.001,
				"整体实体背层/前沿重复像素：%s" % entry["id"])

## 扫描原布局全部实体足迹和障碍多边形内的网格中心，不修改通行数据。
func _scan_original_footprints(ground: IsoGround, layout: Dictionary) -> int:
	var polygons: Array = []
	for entry: Dictionary in layout["entities"]:
		polygons.append(entry["footprint"])
	for entry: Dictionary in layout["fences"]:
		polygons.append(entry["polygon"])
	var checked := 0
	for raw: Array in polygons:
		var polygon := PackedVector2Array()
		for point: Array in raw:
			polygon.append(ground._camp_canvas_to_world(point))
		for y in range(ground.grid_size.y):
			for x in range(ground.grid_size.x):
				var cell := Vector2i(x, y)
				if not Geometry2D.is_point_in_polygon(Iso.grid_to_world(cell), polygon):
					continue
				checked += 1
				assert(not ground.cave.is_walkable(cell), "原实体足迹中有可走格：%s" % cell)
	return checked

## 检查落点未被美术改动埋进障碍，NPC 位置逐一与原 maps.json 配置比较。
func _check_npc_positions(world: Node2D, ground: IsoGround) -> void:
	var specs: Array = MapService.current_npcs()
	var arrival: Array = MapService.data_for("camp")["carterArrival"]
	# 不写死格子号：落点口径由 `TownCarterArrivalTest` 逐座城镇校验（2026-10-22 六座
	# 城镇已统一挪到车夫旁），这里只守「美术与外围开放没有把落点埋进障碍」这条本场景的职责。
	# 原断言写死 [42,30]，数据改成 [48,34] 后它必然误红，且红的原因跟美术毫无关系。
	assert(arrival.size() == 2
		and ground.cave.is_walkable(Vector2i(int(arrival[0]), int(arrival[1]))),
		"马车旅行落点不应随美术与外围开放偏移（必须仍是可走格）")
	var npcs := world.get_node("Npcs")
	assert(npcs.get_child_count() == specs.size() and specs.size() == 5, "营地 NPC 数量变更")
	for spec: Dictionary in specs:
		var cell: Array = spec["cell"]
		var configured := Vector2i(int(cell[0]), int(cell[1]))
		assert(configured == NPC_CELLS[String(spec["role"])], "NPC 配置坐标不应随美术变化")
		var target := Iso.grid_to_world(configured)
		var found := false
		for npc: Npc in npcs.get_children():
			if npc.role == String(spec["role"]):
				assert(npc.global_position.distance_to(target) < 0.01, "NPC 位置变更：%s" % npc.role)
				found = true
		assert(found, "NPC 丢失：%s" % spec["role"])

## 让正式玩家沿原导航绕新实体行走，并逐物理帧确认脚底可通行。
func _walk(world: Node2D, ground: IsoGround, player: PlayerCharacter,
		camera: Camera2D, route: Dictionary) -> void:
	var id := String(route["id"])
	var start := ground.clamp_to_map(ground._camp_canvas_to_world(route["start"]))
	var target := ground.clamp_to_map(ground._camp_canvas_to_world(route["end"]))
	player.clear_travel_intent()
	player.global_position = start
	camera.reset_smoothing()
	assert(ground.route(start, target).size() > 1 and player.request_map_move(target),
		"新增整体实体观察路线不可达：%s" % id)
	var traveled := 0.0
	for frame in range(720):
		var previous := player.global_position
		await get_tree().physics_frame
		traveled += previous.distance_to(player.global_position)
		var cell := Vector2i(Iso.world_to_grid(player.global_position).round())
		assert(ground.cave.is_walkable(cell), "玩家踏入原障碍：%s/%s" % [id, cell])
		if frame == 30 and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			assert(get_viewport().get_texture().get_image().save_png(
				"/tmp/camp_full_walk_%s.png" % id) == OK, "全图路线截图失败：%s" % id)
		if player.global_position.distance_to(target) <= 35.0:
			break
	assert(traveled > 100.0 and player.global_position.distance_to(target) <= 35.0,
		"玩家没有绕原障碍到达目的地：%s" % id)
	print("[PERF] 营地 B 全图实走 ", id, " 世界像素：", roundi(traveled))

## 在固定矩形镜头保存全图与 200% 地表画面，检查纹理、围栏和整体实体。
func _save_overview(world: Node2D, ground: IsoGround, camera: Camera2D) -> void:
	camera.top_level = true
	camera.global_position = ground.get_world_bounds().get_center()
	var size := get_viewport().get_visible_rect().size
	camera.zoom = Vector2.ONE * minf((size.x-24.0)/3200.0, (size.y-24.0)/1800.0)
	camera.make_current()
	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png("/tmp/camp_full_b_overview.png") == OK,
		"B 全图概览截图失败")
	camera.global_position = ground._camp_canvas_to_world([830, 475])
	camera.zoom = Vector2.ONE * 2.0
	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png("/tmp/camp_full_b_ground_200.png") == OK,
		"B 二版地表 200% 实际窗口截图失败")
