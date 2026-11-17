extends Node2D
## 模块化营地结构验证场：数据拼装地形与物件，复用Iso、FlatTileMesh与CaveLayout。
## 验证新风格模块试装与真实物理绕障，不读写正式存档；动画和完整环境包尚未完成。
const OFFSET := Vector2(640, 665)
const DEFINITIONS := {
	"shelter": {"path":"assets/environment/camp_modular_v1/shelter.png", "height":200, "footprint":[[0,0],[1,0],[2,0],[3,0],[0,1],[1,1],[2,1],[3,1],[0,2],[1,2],[2,2],[3,2],[0,3],[1,3],[2,3],[3,3]]},
	"tree": {"path":"assets/environment/camp_modular_v1/tree.png", "height":230, "footprint":[[0,0]]},
	"crate": {"path":"assets/tiles/camp/crate.png", "height":45, "footprint":[[0,0]]},
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
var shape_ids: Array
var collision_cells: Dictionary = {}
var label: Label
var debug_visible := false
var moved_wall := false
var physics_steps := 0

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

## 建立一层合批网格，基础地面与道路分别只生成一个MeshInstance2D。
func _ground(rows: Array, roads: bool) -> void:
	var builder := FlatTileMesh.new(256,true)
	for y in range(16):
		for x in range(16):
			if roads and rows[y][x] != "1":
				continue
			var slot := shape_ids.find(SampleRoadRules.at(rows,Vector2i(x,y)))+1 if roads else 0
			var origin := Iso.grid_to_world(Vector2i(x,y))-Vector2(32,16)
			var variant := posmod(x,4)+posmod(y,4)*4
			var left := float(variant)/16.0
			var right := float(variant+1)/16.0
			var top := float(slot)/48.0
			var bottom := float(slot+1)/48.0
			builder.add_quad(PackedVector2Array([origin,origin+Vector2(64,0),origin+Vector2(64,32),origin+Vector2(0,32)]),PackedVector2Array([Vector2(left,top),Vector2(right,top),Vector2(right,bottom),Vector2(left,bottom)]))
	var mesh := MeshInstance2D.new()
	mesh.mesh = builder.build()
	mesh.texture = atlas
	mesh.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mesh.z_index = -4000 if not roads else -3999
	world.add_child(mesh)

## 用同一物件占地生成贴图、阻挡掩码和物理菱形，切图时释放旧场景及路线。
func _switch_layout(index: int) -> void:
	selected_layout = index
	waypoints.clear()
	collision_cells.clear()
	if world != null:
		remove_child(world)
		world.queue_free()
	world = Node2D.new()
	world.position = OFFSET
	add_child(world)
	var definition: Dictionary = layouts[index]
	_ground(definition.roads,false)
	_ground(definition.roads,true)
	var blocked: Dictionary = {}
	for raw in definition.objects:
		var object: Dictionary = raw
		var spec: Dictionary = DEFINITIONS[object.kind]
		var cell := Vector2i(object.cell[0],object.cell[1])
		if moved_wall and object == definition.objects[3]:
			cell += Vector2i(0,2)
		var sprite := Sprite2D.new()
		sprite.texture = _texture(spec.path)
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
	label.text = "模块化结构样板 %s · Tab切换布局 · 点击寻路 / WASD移动 · B碰撞 · M移动墙\n新材质与独立物件试装 · 4×4周期地面 / 47连接道路 · 角色仍为静态占位" % definition.name

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
func _physics_process(_delta: float) -> void:
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

## 验证所有邻接规范化、两布局通行碰撞一致、真实物理绕障以及移动墙后的缓存更新。
func _verify() -> void:
	assert(shape_ids.size()==47)
	assert(atlas.get_size()==Vector2(1024,1536))
	var pixels := atlas.get_image()
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
	for y in range(15):
		for x in range(15):
			if test_rows[y][x] != "1":
				continue
			var current := SampleRoadRules.at(test_rows,Vector2i(x,y))
			for step in range(21):
				var coordinate := -0.5+step*0.05
				if test_rows[y][x+1] == "1":
					var neighbor := SampleRoadRules.at(test_rows,Vector2i(x+1,y))
					assert(is_equal_approx(SampleRoadRules.coverage(current,0.5,coordinate),SampleRoadRules.coverage(neighbor,-0.5,coordinate)),"横向共边不连续")
				if test_rows[y+1][x] == "1":
					var neighbor := SampleRoadRules.at(test_rows,Vector2i(x,y+1))
					assert(is_equal_approx(SampleRoadRules.coverage(current,coordinate,0.5),SampleRoadRules.coverage(neighbor,coordinate,-0.5)),"纵向共边不连续")
	var captures := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			captures = argument.trim_prefix("--capture=")
	for index in range(2):
		moved_wall = false
		_switch_layout(index)
		await get_tree().physics_frame
		for y in range(16):
			for x in range(16):
				assert(navigator.is_walkable(Vector2i(x,y)) == not collision_cells.has(Vector2i(x,y)))
		if not captures.is_empty():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(captures+"/layout_%d.png"%index)
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
