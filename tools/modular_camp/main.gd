extends Node2D
## 模块化营地结构验证场：数据拼装地形与物件，复用Iso、FlatTileMesh与CaveLayout。
## 验证新风格模块试装与真实物理绕障，不读写正式存档；动画和完整环境包尚未完成。
const OFFSET := Vector2(640, 665)
const DEFINITIONS := {
	"shelter": {"path":"assets/environment/camp_modular_v1/shelter.png", "height":200, "footprint":[[0,0],[1,0],[2,0],[3,0],[0,1],[1,1],[2,1],[3,1],[0,2],[1,2],[2,2],[3,2],[0,3],[1,3],[2,3],[3,3]]},
	"tree": {"path":"assets/environment/camp_modular_v1/tree.png", "height":230, "footprint":[[0,0]]},
	"crate": {"path":"assets/tiles/camp/crate.png", "height":45, "footprint":[[0,0]]},
	"wall_other": {"path":"assets/environment/camp_modular_v1/wall_other.png", "height":56, "footprint":[[0,0]]},
	"wall_corner": {"path":"assets/environment/camp_modular_v1/wall_corner.png", "height":56, "footprint":[[0,0]]},
	"wall": {"path":"assets/environment/camp_modular_v1/wall.png", "height":56, "footprint":[[0,0]]}
}
var layouts: Array
var selected_layout := 0
var world: Node2D
var player: CharacterBody2D
var navigator: CaveLayout
var waypoints: Array[Vector2] = []
var textures: Dictionary = {}
var atlas: Texture2D
var grass_atlas: Texture2D
var shape_ids: Array
var collision_cells: Dictionary = {}
var label: Label
var debug_visible := false
var moved_wall := false
var physics_steps := 0
var occluders: Array[SampleOccluder] = []

## 读取固定资产并建立第一个布局，自动验收模式覆盖两个布局和墙移动。
func _ready() -> void:
	layouts = JSON.parse_string(FileAccess.get_file_as_string("res://layouts.json"))
	_build_atlas()
	label = Label.new()
	label.position = Vector2(20,20)
	add_child(label)
	_switch_layout(0)
	if "--verify" in OS.get_cmdline_user_args():
		_verify.call_deferred()

## 路径缓存按资源路径共享，仅在首次使用时解码。
func _texture(path: String) -> Texture2D:
	if not textures.has(path):
		textures[path] = load("res://" + path) as Texture2D
	return textures[path]

## 读取离线编译的16相位地面与47种道路图集，游戏启动不重复处理源稿。
func _build_atlas() -> void:
	shape_ids = SampleRoadRules.shapes()
	atlas = _texture("assets/environment/camp_modular_v1/terrain_atlas.png")
	grass_atlas = _texture("assets/environment/camp_modular_v1/grass_atlas.png")

## 每层各建一个合批网格：土底、草土覆盖、道路，按固定顺序叠加。
func _ground(rows: Array, layer: int) -> void:
	var builder := FlatTileMesh.new(256,true)
	for y in range(16):
		for x in range(16):
			if layer>0 and rows[y][x] != "1":
				continue
			var slot := shape_ids.find(SampleRoadRules.at(rows,Vector2i(x,y)))+1 if layer>0 else 0
			var origin := Iso.grid_to_world(Vector2i(x,y))-Vector2(32,16)
			var variant := posmod(x,4)+posmod(y,4)*4
			var left := float(variant)/16.0
			var right := float(variant+1)/16.0
			var top := float(slot)/48.0
			var bottom := float(slot+1)/48.0
			builder.add_quad(PackedVector2Array([origin,origin+Vector2(64,0),origin+Vector2(64,32),origin+Vector2(0,32)]),PackedVector2Array([Vector2(left,top),Vector2(right,top),Vector2(right,bottom),Vector2(left,bottom)]))
	var mesh := MeshInstance2D.new()
	mesh.mesh = builder.build()
	mesh.texture = grass_atlas if layer==1 else atlas
	mesh.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mesh.z_index = -4000+layer
	world.add_child(mesh)

## 静态贴花共用一张图集和一个网格，固定地面层，不建立任何碰撞节点。
func _decals(entries: Array) -> void:
	assert(entries.size()<=48,"样板贴花超出预算")
	var builder := FlatTileMesh.new(entries.size(),true)
	for entry in entries:
		var center := Iso.grid_pt(float(entry.cell[0]),float(entry.cell[1]))
		var size := Vector2(128,64)*float(entry.get("scale",0.7))
		var origin := center-size*0.5
		var slot := 0 if entry.kind=="roots" else 1
		var left := slot*0.5
		builder.add_quad(PackedVector2Array([origin,origin+Vector2(size.x,0),origin+size,origin+Vector2(0,size.y)]),PackedVector2Array([Vector2(left,0),Vector2(left+0.5,0),Vector2(left+0.5,1),Vector2(left,1)]))
	var mesh := MeshInstance2D.new()
	mesh.name = "GroundDecals"
	mesh.modulate = Color(0.82,0.8,0.76,0.65)
	mesh.mesh = builder.build()
	mesh.texture = _texture("assets/environment/camp_modular_v1/decals_atlas.png")
	mesh.z_index = -3997
	world.add_child(mesh)

## 用同一物件占地生成贴图、阻挡掩码和物理菱形，切图时释放旧场景及路线。
func _switch_layout(index: int) -> void:
	selected_layout = index
	waypoints.clear()
	collision_cells.clear()
	occluders.clear()
	if world != null:
		remove_child(world)
		world.queue_free()
	world = Node2D.new()
	world.position = OFFSET
	add_child(world)
	var definition: Dictionary = layouts[index]
	_ground(definition.roads,0)
	_ground(definition.grass,1)
	_ground(definition.roads,2)
	_decals(definition.decals)
	var blocked: Dictionary = {}
	for raw in definition.objects:
		var object: Dictionary = raw
		var spec: Dictionary = DEFINITIONS[object.kind]
		var cell := Vector2i(object.cell[0],object.cell[1])
		if moved_wall and object == definition.objects[3]:
			cell += Vector2i(0,2)
		var sprite: Sprite2D = SampleOccluder.new() if object.kind in ["tree","shelter"] else Sprite2D.new()
		if sprite is SampleOccluder:
			sprite.upper_limit = 0.68 if object.kind=="tree" else 0.56
			occluders.append(sprite)
		sprite.texture = _texture(spec.path)
		sprite.set_meta("module_kind", object.kind)
		sprite.position = Iso.grid_to_world(cell)
		sprite.offset.y = -sprite.texture.get_height()*0.5+4
		sprite.scale = Vector2.ONE * float(spec.height)/sprite.texture.get_height()
		sprite.z_index = roundi(sprite.position.y)
		world.add_child(sprite)
		for footprint in spec.footprint:
			blocked[cell+Vector2i(footprint[0],footprint[1])] = true
	for y in range(-1,17):
		for x in range(-1,17):
			if x == -1 or y == -1 or x == 16 or y == 16:
				blocked[Vector2i(x,y)] = true
	var rows: Array = []
	for y in range(16):
		var row := ""
		for x in range(16):
			row += "0" if blocked.has(Vector2i(x,y)) else "1"
		rows.append(row)
	var file := FileAccess.open("res://compiled_layout.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"grid_size":[16,16],"walkable_rows":rows}))
	file.close()
	navigator = CaveLayout.new("res://compiled_layout.json")
	for cell in blocked:
		var body := StaticBody2D.new()
		var polygon := CollisionPolygon2D.new()
		polygon.polygon = Iso.tile_points(cell)
		body.add_child(polygon)
		world.add_child(body)
		collision_cells[cell] = body
		var overlay := Polygon2D.new()
		overlay.polygon = polygon.polygon
		overlay.color = Color(1,0.2,0.1,0.28)
		overlay.visible = debug_visible
		overlay.add_to_group("sample_debug")
		overlay.z_index = 3000
		world.add_child(overlay)
	player = CharacterBody2D.new()
	player.position = Iso.grid_to_world(Vector2i(2,2))
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	player.add_child(shape)
	var art := Sprite2D.new()
	art.texture = _texture("assets/art_pilot/hero.png")
	art.offset.y = -art.texture.get_height()*0.5
	player.add_child(art)
	world.add_child(player)
	label.text = "模块化结构样板 %s · Tab切换布局 · 点击寻路 / WASD移动 · B碰撞 · M移动墙\n新材质与独立物件试装 · 土草路＋贴花 / 树冠屋顶局部淡出 · 角色仍为静态占位" % definition.name

## 鼠标仅在目标可达时创建既有导航路线；编辑操作整体重建小样板并失效旧路线。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			moved_wall = false
			_switch_layout(1-selected_layout)
		elif event.keycode == KEY_B:
			debug_visible = not debug_visible
			for overlay in get_tree().get_nodes_in_group("sample_debug"):
				overlay.visible = debug_visible
		elif event.keycode == KEY_M:
			moved_wall = not moved_wall
			_switch_layout(selected_layout)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_route(event.position-OFFSET)

## 复用CaveLayout的连通判断与路径平滑，不实现新的寻路算法。
func _route(target: Vector2) -> void:
	var start := Vector2i(Iso.world_to_grid(player.position).round())
	var finish := Vector2i(Iso.world_to_grid(target).round())
	waypoints.clear()
	if navigator.reachable(start,finish):
		waypoints = navigator.smooth_path(player.position,navigator.path(start,finish))

## 以真实CharacterBody2D和半径12碰撞移动；贴图不播放伪动画。
func _physics_process(delta: float) -> void:
	physics_steps += 1
	var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	if direction != Vector2.ZERO:
		waypoints.clear()
	elif not waypoints.is_empty():
		if player.position.distance_to(waypoints[0]) < 4:
			waypoints.pop_front()
		if not waypoints.is_empty():
			direction = player.position.direction_to(waypoints[0])
	player.velocity = direction.normalized()*150.0
	player.move_and_slide()
	player.z_index = clampi(roundi(player.position.y),-3500,3500)
	for occluder in occluders:
		occluder.update_reveal(player.position,delta)

## 验证所有邻接规范化、两布局通行碰撞一致、真实物理绕障以及移动墙后的缓存更新。
func _verify() -> void:
	assert(shape_ids.size()==47)
	assert(atlas.get_size()==Vector2(1024,1536))
	for texture in [atlas,grass_atlas]:
		assert(texture.get_size()==Vector2(1024,1536))
		var pixels: Image = texture.get_image()
		for row in range(48):
			for column in range(16):
				assert(pixels.get_pixel(column*64+32,row*32+16).a>0.99,"图集中心缺失")
				assert(pixels.get_pixel(column*64,row*32).a==0.0,"地砖角部透明区污染")
	for bits in range(256):
		assert(SampleRoadRules.normalize(SampleRoadRules.normalize(bits))==SampleRoadRules.normalize(bits))
	# 随机排列覆盖连接与非连接边，验证共享边的alpha完全一致。
	var random := RandomNumberGenerator.new()
	random.seed = 2718
	var test_rows: Array = []
	for y in range(16):
		var row := ""
		for x in range(16):
			row += "1" if random.randf()>0.35 else "0"
		test_rows.append(row)
	for edge in [Vector2(0.25,0.38),Vector2(0.08,0.49)]:
		for y in range(15):
			for x in range(15):
				if test_rows[y][x] != "1":
					continue
				var current := SampleRoadRules.at(test_rows,Vector2i(x,y))
				for step in range(21):
					var coordinate := -0.5+step*0.05
					if test_rows[y][x+1] == "1":
						var neighbor := SampleRoadRules.at(test_rows,Vector2i(x+1,y))
						assert(is_equal_approx(SampleRoadRules.coverage(current,0.5,coordinate,edge.x,edge.y),SampleRoadRules.coverage(neighbor,-0.5,coordinate,edge.x,edge.y)),"横向共边不连续")
					if test_rows[y+1][x] == "1":
						var neighbor := SampleRoadRules.at(test_rows,Vector2i(x,y+1))
						assert(is_equal_approx(SampleRoadRules.coverage(current,coordinate,0.5,edge.x,edge.y),SampleRoadRules.coverage(neighbor,coordinate,-0.5,edge.x,edge.y)),"纵向共边不连续")
	var captures := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			captures = argument.trim_prefix("--capture=")
	for index in range(2):
		moved_wall = false
		_switch_layout(index)
		for row in range(16):
			for col in range(16):
				assert(not (layouts[index].grass[row][col]=="1" and layouts[index].roads[row][col]=="1"),"草覆盖了道路格")
		await get_tree().physics_frame
		for y in range(16):
			for x in range(16):
				assert(navigator.is_walkable(Vector2i(x,y)) == not collision_cells.has(Vector2i(x,y)))
		if not captures.is_empty():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(captures+"/layout_%d.png"%index)
		if index==0:
			await _verify_occlusion(captures)
		_route(Iso.grid_to_world(Vector2i(13,13)))
		assert(not waypoints.is_empty())
		var deadline := Time.get_ticks_msec()+15000
		while not waypoints.is_empty() and Time.get_ticks_msec()<deadline:
			await get_tree().physics_frame
		assert(player.position.distance_to(Iso.grid_to_world(Vector2i(13,13)))<8,"真实移动未到达目标")
		var door_start := Vector2i(5,9) if index == 0 else Vector2i(7,7)
		var door_goal := door_start+Vector2i(0,2)
		player.position = Iso.grid_to_world(door_start)
		await get_tree().physics_frame
		_route(Iso.grid_to_world(door_goal))
		assert(not waypoints.is_empty(),"门洞不可达")
		deadline = Time.get_ticks_msec()+15000
		while not waypoints.is_empty() and Time.get_ticks_msec()<deadline:
			await get_tree().physics_frame
		assert(player.position.distance_to(Iso.grid_to_world(door_goal))<8,"门洞实际通行失败")
		var crossing_start := Vector2i(3,9) if index == 0 else Vector2i(5,7)
		var crossing_goal := crossing_start+Vector2i(0,2)
		player.position = Iso.grid_to_world(crossing_start)
		await get_tree().physics_frame
		assert(player.test_move(player.global_transform,Iso.grid_to_world(crossing_goal)-player.position),"墙体没有阻挡物理移动")
		assert(not navigator.segment_walkable(player.position,Iso.grid_to_world(crossing_goal)), "测试路径没有穿过障碍")
		_route(Iso.grid_to_world(crossing_goal))
		assert(waypoints.size()>1, "绕障路径缺失")
		deadline = Time.get_ticks_msec()+15000
		while not waypoints.is_empty() and Time.get_ticks_msec()<deadline:
			await get_tree().physics_frame
		assert(player.position.distance_to(Iso.grid_to_world(crossing_goal))<8,"绕墙未到达目标")
		var wall: Array = layouts[index].objects[3].cell
		var old := Vector2i(wall[0],wall[1])
		moved_wall = true
		_switch_layout(index)
		assert(navigator.is_walkable(old))
		assert(not navigator.is_walkable(old+Vector2i(0,2)))
		assert(waypoints.is_empty())
	print("MODULAR_CAMP_VERIFY_OK: 256 masks / 47 shapes / 2 layouts / physics routes / moved wall")
	get_tree().quit()

## 实际寻路到可通行遮挡点验证淡出；另定点验证恢复和远处不误触发，不冒充新动作动画。
func _verify_occlusion(captures: String) -> void:
	var origin := player.position
	var blocked := navigator.blocked_cells().duplicate()
	var revision := navigator.navigation_revision
	var collision_count := collision_cells.size()
	for occluder in occluders:
		var kind: String = occluder.get_meta("module_kind")
		var target := occluder.position+Vector2(0,-30 if kind=="tree" else -80)
		var chosen := Vector2.INF
		var best := INF
		for y in range(16):
			for x in range(16):
				var cell := Vector2i(x,y)
				var candidate := Iso.grid_to_world(cell)
				if navigator.is_walkable(cell) and occluder.overlaps_actor(candidate):
					var distance := candidate.distance_squared_to(target)
					if distance<best:
						best = distance
						chosen = candidate
		assert(chosen!=Vector2.INF,"没有可通行的遮挡验证点")
		player.position = origin
		_route(chosen)
		assert(not waypoints.is_empty(),"遮挡点缺少可达路线")
		var deadline := Time.get_ticks_msec()+15000
		while not waypoints.is_empty() and Time.get_ticks_msec()<deadline:
			await get_tree().physics_frame
		assert(player.position.distance_to(chosen)<8,"未能实际走到遮挡点")
		await get_tree().create_timer(0.35).timeout
		assert(occluder.target_reveal and occluder.reveal_amount>0.99,"遮挡时未淡出")
		assert(player.z_index<occluder.z_index)
		if not captures.is_empty():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(captures+"/"+kind+"_reveal.png")
		player.position = occluder.position+Vector2(0,35)
		await get_tree().create_timer(0.35).timeout
		assert(not occluder.target_reveal and occluder.reveal_amount<0.01,"前方未恢复")
		assert(player.z_index>occluder.z_index)
		if not captures.is_empty():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(captures+"/"+kind+"_restored.png")
		player.position = occluder.position+Vector2(500,-30)
		await get_tree().create_timer(0.25).timeout
		assert(not occluder.target_reveal,"远处误触发淡出")
	assert(navigator.navigation_revision==revision and navigator.blocked_cells()==blocked)
	assert(collision_cells.size()==collision_count,"显示淡出改动了物理障碍")
	assert(world.get_node("GroundDecals").get_child_count()==0,"贴花不应建立碰撞子节点")
	player.position = origin
