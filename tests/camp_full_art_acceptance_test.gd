extends Node
## 幸存者营地 B 全图美术验收：核对全部原实体、透明层、固定 NPC 和实走路线。
## 使用正式 Game 场景与布局，不写存档；窗口模式保存全图与局部截图。

const GAME := preload("res://scenes/Game.tscn")
const MANIFEST := "res://assets/maps/camp_style_full_b/manifest.json"
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
	assert(expected_ids.size() == 22 and ground.get_node("CaveWalls").get_child_count() == 22,
		"原有 7 个实体与 15 段障碍必须保持")
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	assert(file != null, "全图清单缺失")
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	assert(String(manifest["layout_id"]) == String(layout["id"]), "美术与障碍版本不一致")
	var atlas := Image.new()
	var roads := Image.new()
	assert(atlas.load(String(manifest["ground_tile"])) == OK)
	assert(roads.load(String(manifest["road_overlay"])) == OK)
	assert(atlas.get_size() == Vector2i(1024, 1024) and atlas.get_pixel(0, 0).a > 0.99,
		"重复地纹应是不含物件的实体地表")
	assert(roads.get_size() == Vector2i(1672, 941) and roads.get_pixel(1600, 850).a < 0.01,
		"独立道路层空白区须真正透明")
	var actual_ids: Dictionary = {}
	for entry: Dictionary in manifest["objects"]:
		var id := String(entry["id"])
		assert(expected_ids.has(id) and not actual_ids.has(id), "新美术实体与原障碍不一致：%s" % id)
		actual_ids[id] = true
		assert(ground.has_node("Camp_%s_front" % id), "实体前沿缺失：%s" % id)
		if entity_ids.has(id):
			assert(ground.has_node("Camp_%s_back" % id), "可绕行实体背层缺失：%s" % id)
			_check_split_alpha(entry)
	assert(actual_ids.size() == expected_ids.size() and ground._camp_foreground_count == 22,
		"全部原实体与障碍必须有整体视觉前沿")
	var blocked := _scan_original_footprints(ground, layout)
	assert(blocked > 150, "逐格障碍扫描覆盖不足")
	_check_npc_positions(world)
	print("[PERF] 营地 B 全图原障碍逐格扫描不可走格心：", blocked)
	for route: Dictionary in ROUTES:
		await _walk(world, ground, player, camera, route)
	if DisplayServer.get_name() != "headless":
		await _save_overview(world, ground, camera)
	print("[CampFullArtAcceptanceTest] PASS · 全图 22 个整体实体、固定 NPC 与四条实走路线通过")
	get_tree().quit()

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

## NPC 位置逐一与原 maps.json 配置比较，防止贴图替换时服务点意外移动。
func _check_npc_positions(world: Node2D) -> void:
	var specs: Array = MapService.current_npcs()
	var npcs := world.get_node("Npcs")
	assert(npcs.get_child_count() == specs.size() and specs.size() == 5, "营地 NPC 数量变更")
	for spec: Dictionary in specs:
		var cell: Array = spec["cell"]
		var target := Iso.grid_to_world(Vector2i(int(cell[0]), int(cell[1])))
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

## 在固定矩形镜头保存正式全图画面，便于检查地面、围栏和整体实体。
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
