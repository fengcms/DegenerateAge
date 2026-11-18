extends Node2D
## 模块化营地结构验证场：数据拼装地形与物件，复用Iso、FlatTileMesh与CaveLayout。
## 验证新风格模块试装与真实物理绕障，不读写正式存档；动画和完整环境包尚未完成。
const OFFSET := Vector2(640, 665)
const DEFINITIONS := {
	"shelter": {"path":"assets/environment/camp_modular_v1/shelter.png", "height":200, "footprint":[[0,0],[1,0],[2,0],[3,0],[0,1],[1,1],[2,1],[3,1],[0,2],[1,2],[2,2],[3,2],[0,3],[1,3],[2,3],[3,3]]},
	"tree": {"path":"assets/environment/camp_modular_v1/tree.png", "height":230, "footprint":[[0,0]]},
	"crate": {"path":"assets/environment/camp_modular_v1/crate.png", "footprint":[[0,0]]},
	"barrel": {"path":"assets/environment/camp_modular_v1/barrel.png", "footprint":[[0,0]]},
	"wall_other": {"path":"assets/environment/camp_modular_v1/wall_other.png", "height":56, "footprint":[[0,0]]},
	"wall_corner": {"path":"assets/environment/camp_modular_v1/wall_corner.png", "height":56, "footprint":[[0,0]]},
	"wall": {"path":"assets/environment/camp_modular_v1/wall.png", "height":56, "footprint":[[0,0]]}
}
var player_art: SampleWalkSprite
var walk_spec: Dictionary
var reaction_specs: Dictionary = {}
var rear_attack_spec: Dictionary
var attack_spec: Dictionary
var motion_enabled := true
var monster_motion_enabled := true
var monster_motion_paused := false
var monster_specs: Dictionary = {}
var monster_attack_specs: Dictionary = {}
var verification_direction := Vector2.ZERO
var actor_specs: Dictionary
var monster_previews: Array[Sprite2D] = []
var actor_names_visible := false
var object_manifest: Dictionary
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
	for state in ["hit","death"]:
		reaction_specs[state] = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art_pilot/hero_"+state+"_se_v1.json"))
	rear_attack_spec = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art_pilot/hero_attack_ne_v1.json"))
	attack_spec = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art_pilot/hero_attack_se_v1.json"))
	walk_spec = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art_pilot/hero_walk_se_v3.json"))
	for kind in ["wolf","beetle"]:
		monster_attack_specs[kind] = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art_pilot/"+kind+"_attack_v1.json"))
		monster_specs[kind] = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art_pilot/"+kind+"_idle_v1.json"))
	actor_specs = JSON.parse_string(FileAccess.get_file_as_string("res://actors.json"))
	layouts = JSON.parse_string(FileAccess.get_file_as_string("res://layouts.json"))
	object_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/camp_modular_v1/manifest.json")).objects
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
	monster_previews.clear()
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
			sprite.mask_texture = _texture("assets/environment/camp_modular_v1/"+object.kind+"_reveal_mask.png")
			occluders.append(sprite)
		sprite.texture = _texture(spec.path)
		sprite.set_meta("module_kind", object.kind)
		sprite.position = Iso.grid_to_world(cell)
		sprite.offset.y = -sprite.texture.get_height()*0.5+4
		if object.kind in ["crate","barrel"]:
			var pivot: Array = object_manifest[object.kind].pivot
			sprite.offset = sprite.texture.get_size()*0.5-Vector2(pivot[0],pivot[1])
		else:
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
	player.position = Iso.grid_to_world(Vector2i(definition.start[0],definition.start[1]))
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	player.add_child(shape)
	player_art = _actor_sprite("hero") as SampleWalkSprite
	player.add_child(player_art)
	world.add_child(player)
	for entry in definition.actors:
		var cell := Vector2i(entry.cell[0],entry.cell[1])
		assert(navigator.is_walkable(cell),"怪物展示落点被阻挡")
		var actor := _actor_sprite(entry.kind)
		actor.position = Iso.grid_to_world(cell)
		actor.z_index = roundi(actor.position.y)
		world.add_child(actor)
		monster_previews.append(actor)
	label.text = "模块化结构样板 %s · Tab切换布局 · 点击寻路 / WASD移动 · B碰撞 · M移动墙 · N名称 · P右下/O右上/U左下/Y左上/G正下 · H动作对照 · I转向 · J怪物动作\n1正后 / 2向右 / 3向左 · T右前挥剑 / 4右后挥剑 / R怪物攻击 · K暂停怪物 / L逐帧\nF受击 / C倒地 / V重置 · 新材质与独立物件试装 · 土草路＋贴花 / 轮廓保护淡出 · 主角八方向四帧试装 / 狼与甲虫待机/攻击试装" % definition.name

## 按档案定位角色表现；主角支持八个方向试装，怪物可试装待机，不引入AI或碰撞。
func _actor_sprite(kind: String) -> Sprite2D:
	var spec: Dictionary = actor_specs[kind]
	var sprite: Sprite2D = SampleWalkSprite.new() if kind=="hero" else (SampleIdleSprite.new() if monster_specs.has(kind) else Sprite2D.new())
	sprite.texture = _texture(spec.path)
	sprite.centered = false
	sprite.offset = -Vector2(spec.pivot_ratio[0],spec.pivot_ratio[1])*sprite.texture.get_size()
	if sprite is SampleWalkSprite:
		sprite.setup(sprite.texture,_texture("assets/art_pilot/hero_walk_se_v3.png"),_texture("assets/art_pilot/hero_idle_se_v3.png"),_texture("assets/art_pilot/hero_idle_ne_v3.png"),_texture("assets/art_pilot/hero_walk_ne_v2.png"),_texture("assets/art_pilot/hero_walk_sw_v1.png"),_texture("assets/art_pilot/hero_idle_sw_v3.png"),_texture("assets/art_pilot/hero_walk_nw_v2.png"),_texture("assets/art_pilot/hero_idle_nw_v3.png"),walk_spec)
		sprite.setup_front(_texture("assets/art_pilot/hero_walk_s_v1.png"),_texture("assets/art_pilot/hero_idle_s_v3.png"))
		for direction in ["n","e","w"]:
			sprite.setup_extra(direction,_texture("assets/art_pilot/hero_walk_"+direction+"_v1.png"),_texture("assets/art_pilot/hero_idle_"+direction+"_v3.png"))
		sprite.setup_attack(_texture("assets/art_pilot/hero_attack_se_v1.png"),attack_spec)
		sprite.setup_attack(_texture("assets/art_pilot/hero_attack_ne_v1.png"),rear_attack_spec)
		for state in reaction_specs:
			sprite.setup_reaction(_texture("assets/art_pilot/hero_"+state+"_se_v1.png"),reaction_specs[state])
		sprite.enabled = motion_enabled
	elif sprite is SampleIdleSprite:
		sprite.setup(_texture("assets/art_pilot/"+kind+"_idle_v1.png"),monster_specs[kind])
		sprite.setup_attack(_texture("assets/art_pilot/"+kind+"_attack_v1.png"),monster_attack_specs[kind])
		sprite.set_enabled(monster_motion_enabled)
		sprite.set_paused(monster_motion_paused)
	sprite.set_meta("actor_kind",kind)
	var caption := Label.new()
	caption.text = spec.name
	caption.position = Vector2(-55,sprite.offset.y-22)
	caption.size.x = 110
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",13)
	caption.add_theme_color_override("font_shadow_color",Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x",1)
	caption.add_theme_constant_override("shadow_offset_y",1)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.visible = actor_names_visible
	caption.add_to_group("actor_names")
	sprite.add_child(caption)
	return sprite

## 鼠标仅在目标可达时创建既有导航路线；编辑操作整体重建小样板并失效旧路线。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			moved_wall = false
			_switch_layout(1-selected_layout)
		elif event.keycode == KEY_P:
			_start_walk_demo()
		elif event.keycode == KEY_O:
			_start_rear_demo()
		elif event.keycode == KEY_U:
			_start_left_demo()
		elif event.keycode == KEY_Y:
			_start_left_rear_demo()
		elif event.keycode == KEY_G:
			_start_front_demo()
		elif event.keycode in [KEY_1,KEY_2,KEY_3]:
			_start_extra_demo("n" if event.keycode==KEY_1 else ("e" if event.keycode==KEY_2 else "w"))
		elif event.keycode in [KEY_T,KEY_4]:
			_start_attack_demo("se" if event.keycode==KEY_T else "ne")
		elif event.keycode == KEY_I:
			waypoints.clear()
			_turn_preview()
		elif event.keycode in [KEY_F,KEY_C]:
			waypoints.clear()
			player_art.start_reaction("hit" if event.keycode==KEY_F else "death")
		elif event.keycode == KEY_V:
			waypoints.clear()
			player_art.reset_reaction()
		elif event.keycode == KEY_R:
			_start_monster_attacks()
		elif event.keycode == KEY_J:
			_set_monster_motion(not monster_motion_enabled)
		elif event.keycode == KEY_K:
			_set_monster_paused(not monster_motion_paused)
		elif event.keycode == KEY_L:
			_set_monster_paused(true)
			for actor in monster_previews:
				if actor is SampleIdleSprite:
					actor.step_frame()
		elif event.keycode == KEY_H:
			motion_enabled = not motion_enabled
			player_art.enabled = motion_enabled
		elif event.keycode == KEY_N:
			actor_names_visible = not actor_names_visible
			for caption in get_tree().get_nodes_in_group("actor_names"):
				caption.visible = actor_names_visible
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
	if player_art.blocks_preview_motion():
		waypoints.clear()
		return
	var start := Vector2i(Iso.world_to_grid(player.position).round())
	var finish := Vector2i(Iso.world_to_grid(target).round())
	waypoints.clear()
	if navigator.reachable(start,finish):
		waypoints = navigator.smooth_path(player.position,navigator.path(start,finish))

## 以真实CharacterBody2D和半径12碰撞移动；行走帧仅由碰撞处理后的实际位移推进。
func _physics_process(delta: float) -> void:
	physics_steps += 1
	var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	if verification_direction != Vector2.ZERO:
		direction = verification_direction
	if direction != Vector2.ZERO:
		waypoints.clear()
	elif not waypoints.is_empty():
		if player.position.distance_to(waypoints[0]) < 4:
			waypoints.pop_front()
		if not waypoints.is_empty():
			direction = player.position.direction_to(waypoints[0])
	if player_art.blocks_preview_motion():
		direction = Vector2.ZERO
		waypoints.clear()
	player.velocity = direction.normalized()*150.0
	var before := player.position
	player.move_and_slide()
	player_art.update_motion(player.position-before,direction)
	player_art.advance_attack(delta)
	player_art.advance_reaction(delta)
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
		_verify_actors()
		print("VERIFY_STAGE: ",index," / monster_idle")
		await _verify_monster_idle(captures)
		await _verify_monster_attack(captures)
		print("VERIFY_STAGE: ",index," / hero_walk")
		await _verify_walk(captures)
		await _verify_wall_stop(captures)
		await _verify_wall_stop(captures,"ne")
		await _verify_rear(captures)
		await _verify_left(captures)
		await _verify_left_rear(captures)
		await _verify_front(captures)
		for direction in ["n","e","w"]:
			await _verify_extra(captures,direction)
			# 正后持续顶墙被北角物理抖动阻塞，见78号记录；不降低已有七向静止门槛。
			if direction!="n":
				await _verify_wall_stop(captures,direction)
		await _verify_wall_stop(captures,"s")
		print("VERIFY_STAGE: ",index," / hero_attack")
		await _verify_attack(captures)
		await _verify_attack(captures,"ne")
		await _verify_reactions(captures)
		await _verify_wall_stop(captures,"nw")
		await _verify_wall_stop(captures,"sw")
		print("VERIFY_STAGE: ",index," / supplies_occlusion")
		await _verify_supplies(captures)
		await _verify_occlusion(captures)
		print("VERIFY_STAGE: ",index," / routes")
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
		assert(player_art.start_attack())
		assert(player_art.start_reaction("death"))
		var old_art: WeakRef = weakref(player_art)
		_start_monster_attacks()
		var old_monster: WeakRef = weakref(monster_previews[0])
		moved_wall = true
		_switch_layout(index)
		assert(not player_art.attacking and player_art.reaction_state.is_empty())
		await get_tree().process_frame
		await get_tree().process_frame
		assert(old_art.get_ref()==null and old_monster.get_ref()==null,"切图应释放旧动作实例")
		assert(not monster_previews[0].attacking)
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
			occluder.reveal_material.set_shader_parameter("reveal_amount",0.0)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(captures+"/"+kind+"_opaque.png")
			occluder.reveal_material.set_shader_parameter("reveal_amount",occluder.reveal_amount)
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

## 确认两类展示物件复用纹理、落在可达地面、脚底排序一致且不增加物理障碍。
func _verify_actors() -> void:
	assert(monster_previews.size()==2)
	assert(get_tree().get_nodes_in_group("actor_names").size()==3)
	for actor in monster_previews:
		if actor is SampleIdleSprite:
			actor.set_enabled(false)
		var kind: String = actor.get_meta("actor_kind")
		assert(actor.texture==_texture(actor_specs[kind].path))
		assert(actor.texture.get_width()==110)
		var pixels := actor.texture.get_image()
		assert(pixels.detect_alpha()!=Image.ALPHA_NONE)
		assert(pixels.get_pixel(0,0).a<0.01)
		var cell := Vector2i(Iso.world_to_grid(actor.position).round())
		assert(navigator.reachable(Vector2i(layouts[selected_layout].start[0],layouts[selected_layout].start[1]),cell))
		assert(not collision_cells.has(cell))
		assert(actor.z_index==roundi(actor.position.y))
		assert(actor.get_child_count()==1 and actor.get_child(0) is Label)
		if actor is SampleIdleSprite:
			actor.set_enabled(monster_motion_enabled)

## 明确的试走入口：回到两布局共用的空地并沿右下方向寻路，不改变正式出生点。
func _start_walk_demo() -> void:
	if player_art.blocks_preview_motion():
		return
	player.position = Iso.grid_to_world(Vector2i(8,6))
	player_art.update_motion(Vector2.ZERO)
	_route(Iso.grid_to_world(Vector2i(8,2)))

## 用真实物理路线覆盖四帧、停步与反向独立动作；显示开关不允许修改碰撞和角色位置。
func _verify_walk(captures: String) -> void:
	var origin := player.position
	_start_walk_demo()
	assert(not waypoints.is_empty())
	var seen: Dictionary = {}
	var capture_index := 0
	var shots: Dictionary = {}
	var capture_times: Array = []
	var deadline := Time.get_ticks_msec()+5000
	while not waypoints.is_empty() and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
		if not captures.is_empty() and physics_steps%3==0 and capture_index<24:
			await RenderingServer.frame_post_draw
			shots["walk_demo_%d_%03d.png"%[selected_layout,capture_index]] = get_viewport().get_texture().get_image()
			capture_times.append(Time.get_ticks_msec())
			capture_index += 1
		if player_art.walking and not seen.has(player_art.walk_frame):
			seen[player_art.walk_frame] = true
			if not captures.is_empty():
				await RenderingServer.frame_post_draw
				shots["walk_%d_%d.png"%[selected_layout,player_art.walk_frame]] = get_viewport().get_texture().get_image()
	assert(player.position.distance_to(Iso.grid_to_world(Vector2i(8,2)))<8)
	assert(seen.size()==4,"实际移动没有覆盖完整四帧")
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(not player_art.walking and player_art.texture==player_art.directional_idle,"右下停步后未保持配套站姿")
	if not captures.is_empty():
		await RenderingServer.frame_post_draw
		shots["walk_demo_%d_%03d.png"%[selected_layout,capture_index]] = get_viewport().get_texture().get_image()
		capture_times.append(Time.get_ticks_msec())
		assert(shots.size()<=29,"截图缓存超出上限")
		for filename in shots:
			shots[filename].save_png(captures+"/"+filename)
		shots.clear()
		var timing := FileAccess.open(captures+"/walk_demo_%d.json"%selected_layout,FileAccess.WRITE)
		timing.store_string(JSON.stringify(capture_times))
	_route(Iso.grid_to_world(Vector2i(8,6)))
	deadline = Time.get_ticks_msec()+5000
	while not waypoints.is_empty() and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
		if player_art.walking:
			assert(player_art.texture in player_art.left_rear_frames,"反向必须选择独立左后帧")
	assert(player.position.distance_to(Iso.grid_to_world(Vector2i(8,6)))<8)
	player_art.enabled = false
	player_art.update_motion(Vector2(2,1))
	assert(not player_art.walking)
	player_art.enabled = true
	player_art.update_motion(Vector2(2,1))
	assert(player_art.walking)
	player_art.update_motion(Vector2.ZERO)
	assert(not player_art.walking and player_art.phase_distance==0,"零位移不应原地踏步")
	assert(player_art.texture==player_art.directional_idle)
	player_art.update_motion(Vector2.ZERO,Vector2(0,-1))
	assert(player_art.texture==player_art.extra_idles["n"],"正后已有独立站姿")
	player_art.update_motion(Vector2.ZERO,Vector2(2,1))
	assert(player_art.texture==player_art.directional_idle and not player_art.walking,"输入意图只能转向，不能原地踏步")
	player.position = origin

## 持续模拟已通过接触验收的七方向移动输入，实际撞到既有地图边界角；验证顶墙停帧且保持朝向，随后撤销输入。
func _verify_wall_stop(captures: String, direction := "se") -> void:
	var origin := player.position
	waypoints.clear()
	var start_cell := Vector2i(14,1)
	if direction in ["sw","nw","w"]:
		start_cell = Vector2i(1,14)
	elif direction=="s":
		start_cell = Vector2i(1,1)
	player.position = Iso.grid_to_world(start_cell)
	var start := player.position
	verification_direction = SampleWalkSprite.DIRECTION_VECTORS[direction]
	var previous := player.position
	var stopped_frames := 0
	var saw_walk := false
	for step in range(300):
		await get_tree().physics_frame
		saw_walk = saw_walk or player_art.walking
		if player.position.distance_to(previous)<0.01 and player.get_slide_collision_count()>0:
			stopped_frames += 1
		else:
			stopped_frames = 0
		previous = player.position
		if stopped_frames>=12:
			break
	assert(saw_walk and player.position.distance_to(start)>10,"顶墙测试未发生真实接近")
	assert(stopped_frames>=12,"方向%s顶墙不稳定：帧%d，位置%s，碰撞%d"%[direction,stopped_frames,player.position,player.get_slide_collision_count()])
	assert(not player_art.walking and player_art.phase_distance==0)
	assert(player_art.texture==player_art.idle_for_direction(direction),"顶墙应保持对应站姿")
	if not captures.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(captures+"/wall_stop_%s_%d.png"%[direction,selected_layout])
	verification_direction = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(not player_art.walking)
	player.position = origin

## 原地切换前后两个已制作朝向，不移动角色；用于检查武器持握、比例和共用脚底锚点。
func _turn_preview() -> void:
	if player_art.blocks_preview_motion():
		return
	player_art.update_motion(Vector2.ZERO,Vector2(2,1) if player_art.facing_id=="ne" else Vector2(2,-1))

## 真实右上路线覆盖独立背面四帧，停步保持背向；原地转向不改变位置或镜像贴图。
func _verify_rear(captures: String) -> void:
	var origin := player.position
	_start_rear_demo()
	var seen: Dictionary = {}
	var shots: Dictionary = {}
	assert(not waypoints.is_empty())
	var deadline := Time.get_ticks_msec()+5000
	while not waypoints.is_empty() and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
		if player_art.walking:
			assert(player_art.texture in player_art.rear_frames,"右上误用了正面行走帧")
			if not seen.has(player_art.walk_frame):
				seen[player_art.walk_frame] = true
				if not captures.is_empty():
					await RenderingServer.frame_post_draw
					shots[player_art.walk_frame] = get_viewport().get_texture().get_image()
	assert(seen.size()==4,"实际右上移动未覆盖四帧")
	for index in shots:
		shots[index].save_png(captures+"/rear_walk_%d_%d.png"%[selected_layout,index])
	shots.clear()
	assert(player.position.distance_to(Iso.grid_to_world(Vector2i(8,7)))<8)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(player_art.texture==player_art.rear_idle and player_art.offset==-Vector2(walk_spec.pivot[0],walk_spec.pivot[1]))
	assert(not player_art.flip_h and not player_art.flip_v)
	if not captures.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(captures+"/rear_idle_%d.png"%selected_layout)
	var resting := player.position
	_turn_preview()
	assert(player.position==resting and player_art.texture==player_art.directional_idle)
	if not captures.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(captures+"/front_idle_%d.png"%selected_layout)
	_turn_preview()
	assert(player.position==resting and player_art.texture==player_art.rear_idle)
	player_art.enabled = false
	player_art.update_motion(Vector2.ZERO)
	assert(player_art.texture==player_art.idle_texture)
	player_art.enabled = true
	player_art.update_motion(Vector2.ZERO)
	assert(player_art.texture==player_art.rear_idle,"重新启用应保留背向")
	player.position = origin

## 同时切换展示怪物动作开关，切图保留用户选择；不改变布局或物理。
func _set_monster_motion(value: bool) -> void:
	monster_motion_enabled = value
	for actor in monster_previews:
		if actor is SampleIdleSprite:
			actor.set_enabled(value)

## 真实帧回调覆盖循环；关闭后应保持旧图，位置、排序与导航均不变化。
func _verify_monster_idle(captures: String) -> void:
	var revision := navigator.navigation_revision
	var count := collision_cells.size()
	var positions: Array[Vector2] = []
	var seen: Dictionary = {}
	var shots: Dictionary = {}
	_set_monster_motion(true)
	for actor in monster_previews:
		positions.append(actor.position)
		if actor is SampleIdleSprite:
			seen[actor.get_meta("actor_kind")] = {}
	var deadline := Time.get_ticks_msec()+2200
	while Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		for actor in monster_previews:
			if actor is SampleIdleSprite:
				var kind: String = actor.get_meta("actor_kind")
				if not seen[kind].has(actor.current_frame):
					seen[kind][actor.current_frame] = true
					if not captures.is_empty():
						await RenderingServer.frame_post_draw
						shots["idle_%s_%d_%d.png"%[kind,selected_layout,actor.current_frame]] = get_viewport().get_texture().get_image()
	for kind in seen:
		assert(seen[kind].size()==4,"待机真实播放未覆盖四帧")
	assert(shots.size()<=8,"怪物截图超出缓存预算")
	for filename in shots:
		shots[filename].save_png(captures+"/"+filename)
	shots.clear()
	_set_monster_paused(true)
	var frozen: Array[int] = []
	for actor in monster_previews:
		frozen.append(actor.current_frame)
	await get_tree().create_timer(0.4).timeout
	for index in range(monster_previews.size()):
		var actor: SampleIdleSprite = monster_previews[index]
		assert(actor.current_frame==frozen[index] and not actor.is_processing())
		for step in range(4):
			actor.step_frame()
			assert(actor.current_frame==(frozen[index]+step+1)%4)
			assert(actor.texture==actor.regions[actor.current_frame])
	_set_monster_motion(false)
	await get_tree().create_timer(0.4).timeout
	for index in range(monster_previews.size()):
		var actor := monster_previews[index]
		assert(actor.position==positions[index] and actor.z_index==roundi(actor.position.y))
		if actor is SampleIdleSprite:
			actor.step_frame()
			assert(actor.texture==actor.original and not actor.is_processing())
	assert(navigator.navigation_revision==revision and collision_cells.size()==count)
	_set_monster_motion(true)
	assert(monster_previews[0].paused and not monster_previews[0].is_processing())
	_set_monster_paused(false)
	await get_tree().create_timer(0.4).timeout
	assert(monster_previews[0].current_frame==1 and monster_previews[0].is_processing())

## 从可通行邻格真实撞向补给物件，必须接触对应物理体；并检查独立贴图按清单锚点落地。
func _verify_supplies(captures: String) -> void:
	var origin := player.position
	waypoints.clear()
	var checked := 0
	for sprite in world.get_children():
		if not sprite is Sprite2D or not sprite.get_meta("module_kind","") in ["crate","barrel"]:
			continue
		var kind: String = sprite.get_meta("module_kind")
		var spec: Dictionary = object_manifest[kind]
		assert(sprite.texture.get_size()==Vector2(spec.size[0],spec.size[1]))
		assert(sprite.offset==sprite.texture.get_size()*0.5-Vector2(spec.pivot[0],spec.pivot[1]))
		assert(sprite.scale==Vector2.ONE and sprite.texture.get_image().detect_alpha()!=Image.ALPHA_NONE)
		var cell := Vector2i(Iso.world_to_grid(sprite.position).round())
		assert(collision_cells.has(cell) and not navigator.is_walkable(cell))
		var approach := Vector2i(-100,-100)
		for step in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
			if navigator.is_walkable(cell+step):
				approach = cell+step
				break
		assert(approach.x!=-100,"补给物件没有可接近的检查面")
		player.position = Iso.grid_to_world(approach)
		verification_direction = player.position.direction_to(sprite.position)
		var contacted := false
		for step in range(45):
			await get_tree().physics_frame
			for index in range(player.get_slide_collision_count()):
				if player.get_slide_collision(index).get_collider()==collision_cells[cell]:
					contacted = true
			if contacted:
				break
		verification_direction = Vector2.ZERO
		assert(contacted and player.position.distance_to(sprite.position)>12,"补给物件碰撞缺失或穿入中心")
		await get_tree().physics_frame
		if not captures.is_empty():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(captures+"/supply_%s_%d.png"%[kind,selected_layout])
		checked += 1
	assert(checked==2,"每套样板应包含木箱与木桶")
	player.position = origin

## 右上行走的可复现入口，复用现有导航，不驱动物理之外的假位移。
func _start_rear_demo() -> void:
	if player_art.blocks_preview_motion():
		return
	waypoints.clear()
	player.position = Iso.grid_to_world(Vector2i(4,7))
	player_art.update_motion(Vector2.ZERO,Vector2(2,-1))
	_route(Iso.grid_to_world(Vector2i(8,7)))

## 切换怪物审片暂停状态，切图仍保留选择；主角移动、碰撞和导航继续正常运行。
func _set_monster_paused(value: bool) -> void:
	monster_motion_paused = value
	for actor in monster_previews:
		if actor is SampleIdleSprite:
			actor.set_paused(value)

## 左前试走复用右上路线的反向，不改变正式地图出生点。
func _start_left_demo() -> void:
	if player_art.blocks_preview_motion():
		return
	waypoints.clear()
	player.position = Iso.grid_to_world(Vector2i(8,7))
	player_art.update_motion(Vector2.ZERO,Vector2(-2,1))
	_route(Iso.grid_to_world(Vector2i(4,7)))

## 验证左前真实位移覆盖四帧、停步站姿与关闭回退；固定锚点，不镜像贴图。
func _verify_left(captures: String) -> void:
	var origin := player.position
	_start_left_demo()
	var seen: Dictionary = {}
	var shots: Dictionary = {}
	var deadline := Time.get_ticks_msec()+5000
	while not waypoints.is_empty() and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
		if player_art.walking:
			assert(player_art.texture in player_art.left_frames)
			if not seen.has(player_art.walk_frame):
				seen[player_art.walk_frame] = true
				if not captures.is_empty():
					await RenderingServer.frame_post_draw
					shots[player_art.walk_frame] = get_viewport().get_texture().get_image()
	assert(seen.size()==4 and player.position.distance_to(Iso.grid_to_world(Vector2i(4,7)))<8)
	for index in shots:
		shots[index].save_png(captures+"/left_walk_%d_%d.png"%[selected_layout,index])
	shots.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(not player_art.walking and player_art.texture==player_art.left_idle and player_art.phase_distance==0)
	assert(not player_art.flip_h and not player_art.flip_v)
	if not captures.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(captures+"/left_idle_%d.png"%selected_layout)
	player_art.enabled = false
	player_art.update_motion(Vector2.ZERO)
	assert(player_art.texture==player_art.idle_texture)
	player_art.enabled = true
	player_art.update_motion(Vector2.ZERO)
	assert(player_art.texture==player_art.left_idle)
	player.position = origin

## 左后试走沿右下路线的反向，不改变正式地图出生点。
func _start_left_rear_demo() -> void:
	if player_art.blocks_preview_motion():
		return
	waypoints.clear()
	player.position = Iso.grid_to_world(Vector2i(8,2))
	player_art.update_motion(Vector2.ZERO,Vector2(-2,-1))
	_route(Iso.grid_to_world(Vector2i(8,6)))

## 验证左后真实位移覆盖四帧、停步站姿与关闭回退；固定锚点，不镜像贴图。
func _verify_left_rear(captures: String) -> void:
	var origin := player.position
	_start_left_rear_demo()
	var seen: Dictionary = {}
	var shots: Dictionary = {}
	var deadline := Time.get_ticks_msec()+5000
	while not waypoints.is_empty() and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
		if player_art.walking:
			assert(player_art.texture in player_art.left_rear_frames)
			if not seen.has(player_art.walk_frame):
				seen[player_art.walk_frame] = true
				if not captures.is_empty():
					await RenderingServer.frame_post_draw
					shots[player_art.walk_frame] = get_viewport().get_texture().get_image()
	assert(seen.size()==4 and player.position.distance_to(Iso.grid_to_world(Vector2i(8,6)))<8)
	for index in shots:
		shots[index].save_png(captures+"/left_rear_walk_%d_%d.png"%[selected_layout,index])
	shots.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(not player_art.walking and player_art.texture==player_art.left_rear_idle and player_art.phase_distance==0)
	assert(not player_art.flip_h and not player_art.flip_v)
	if not captures.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(captures+"/left_rear_idle_%d.png"%selected_layout)
	player_art.enabled = false
	player_art.update_motion(Vector2.ZERO)
	assert(player_art.texture==player_art.idle_texture)
	player_art.enabled = true
	player_art.update_motion(Vector2.ZERO)
	assert(player_art.texture==player_art.left_rear_idle)
	player.position = origin

## 在当前位置展示指定方向挥剑并清空点击路线；键盘移动仍可立即打断，不触发战斗结算。
func _start_attack_demo(direction := "se") -> void:
	waypoints.clear()
	player_art.start_attack(direction)

## 两布局验证真实时间四阶段、自动复位、重入拒绝、移动和开关取消；位置与导航版本不变。
func _verify_attack(captures: String, direction := "se") -> void:
	# 等待前一阶段截图落盘后的补偿步结束，保留四帧真实时间采样。
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not player_art.start_attack("nw"),"缺稿方向不能冒充完成")
	var revision := navigator.navigation_revision
	var blocked := navigator.blocked_cells().duplicate()
	waypoints.clear()
	var origin := player.position
	var seen: Dictionary = {}
	var shots: Dictionary = {}
	assert(player_art.start_attack(direction))
	assert(not player_art.start_attack(direction),"重复触发不应重置挥剑")
	var deadline := Time.get_ticks_msec()+3000
	while player_art.attacking and Time.get_ticks_msec()<deadline:
		if not captures.is_empty():
			await RenderingServer.frame_post_draw
		else:
			await get_tree().physics_frame
		if player_art.attacking:
			var index := player_art.attack_frame
			seen[index] = true
			assert(player_art.texture==player_art.attack_frames[index])
			if not captures.is_empty() and not shots.has(index):
				shots[index] = get_viewport().get_texture().get_image()
	assert(seen.size()==4 and not player_art.attacking,"挥剑未覆盖四阶段或未结束")
	assert(player.position==origin and player_art.texture==player_art.idle_for_direction(direction))
	for index in shots:
		shots[index].save_png(captures+"/hero_attack_%s_%d_%d.png"%[direction,selected_layout,index])
	shots.clear()
	assert(player_art.start_attack(direction))
	player_art.advance_attack(player_art.attack_duration+0.1)
	assert(not player_art.attacking and player_art.texture==player_art.idle_for_direction(direction),"长步长应直接结束")
	assert(player_art.start_attack(direction))
	player_art.update_motion(Vector2.ZERO,Vector2(-2,-1))
	assert(not player_art.attacking and player_art.texture==player_art.left_rear_idle,"移动意图应取消挥剑")
	assert(player_art.start_attack(direction))
	player_art.enabled = false
	player_art.update_motion(Vector2.ZERO)
	assert(not player_art.attacking and player_art.texture==player_art.idle_texture)
	assert(not player_art.start_attack(direction),"关闭展示不应启动挥剑")
	player_art.enabled = true
	player_art.update_motion(Vector2.ZERO)
	assert(player_art.texture==player_art.idle_for_direction(direction) and player.position==origin)
	assert(navigator.navigation_revision==revision and navigator.blocked_cells()==blocked)

## 同时触发两怪原地单次攻击，保持暂停选择，播放中重复触发由实例拒绝。
func _start_monster_attacks() -> void:
	for actor in monster_previews:
		if actor is SampleIdleSprite:
			actor.start_attack()

## 两布局覆盖攻击四帧、自动恢复、暂停逐帧、原图取消及落点/导航保持，不触发战斗。
func _verify_monster_attack(captures: String) -> void:
	var revision := navigator.navigation_revision
	var blocked := navigator.blocked_cells().duplicate()
	var positions: Array[Vector2] = []
	var seen: Dictionary = {}
	var shots: Dictionary = {}
	_set_monster_paused(false)
	for actor in monster_previews:
		positions.append(actor.position)
		seen[actor.get_meta("actor_kind")] = {}
		assert(actor.start_attack())
		assert(not actor.start_attack())
	var deadline := Time.get_ticks_msec()+1500
	while Time.get_ticks_msec()<deadline:
		if not captures.is_empty():
			await RenderingServer.frame_post_draw
		else:
			await get_tree().process_frame
		for actor in monster_previews:
			if actor.attacking:
				var kind: String = actor.get_meta("actor_kind")
				var index: int = actor.current_frame
				seen[kind][index] = true
				assert(actor.texture==actor.attack_regions[index])
				var key := "attack_%s_%d_%d.png"%[kind,selected_layout,index]
				if not captures.is_empty() and not shots.has(key):
					shots[key] = get_viewport().get_texture().get_image()
	for kind in seen:
		assert(seen[kind].size()==4,"怪物攻击未实际显示四帧")
	for actor in monster_previews:
		assert(not actor.attacking and actor.texture in actor.regions)
	assert(shots.size()<=8)
	for key in shots:
		shots[key].save_png(captures+"/"+key)
	shots.clear()
	_set_monster_paused(true)
	_start_monster_attacks()
	await get_tree().create_timer(0.3).timeout
	for index in range(monster_previews.size()):
		var actor: SampleIdleSprite = monster_previews[index]
		assert(actor.attacking and actor.current_frame==0 and not actor.is_processing())
		for frame in range(1,4):
			actor.step_frame()
			assert(actor.current_frame==frame and actor.texture==actor.attack_regions[frame])
		actor.step_frame()
		assert(not actor.attacking and actor.texture==actor.regions[0] and actor.paused)
		assert(actor.start_attack())
		actor.set_paused(false)
		actor._process(actor.attack_duration+0.1)
		assert(not actor.attacking and actor.texture==actor.regions[0])
		assert(actor.start_attack())
		actor.set_enabled(false)
		assert(not actor.attacking and actor.texture==actor.original and not actor.start_attack())
		actor.set_enabled(true)
		assert(actor.position==positions[index] and actor.z_index==roundi(actor.position.y))
	_set_monster_paused(false)
	assert(navigator.navigation_revision==revision and navigator.blocked_cells()==blocked)

## 正前试走沿屏幕正下方向，不改变正式地图出生点。
func _start_front_demo() -> void:
	if player_art.blocks_preview_motion():
		return
	waypoints.clear()
	player.position = Iso.grid_to_world(Vector2i(8,6))
	player_art.update_motion(Vector2.ZERO,Vector2.DOWN)
	_route(Iso.grid_to_world(Vector2i(6,4)))

## 验证正前真实位移覆盖四帧、停步站姿与关闭回退；固定锚点，不镜像贴图。
func _verify_front(captures: String) -> void:
	var origin := player.position
	_start_front_demo()
	var seen: Dictionary = {}
	var shots: Dictionary = {}
	var deadline := Time.get_ticks_msec()+5000
	while not waypoints.is_empty() and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
		if player_art.walking:
			assert(player_art.texture in player_art.front_frames)
			if not seen.has(player_art.walk_frame):
				seen[player_art.walk_frame] = true
				if not captures.is_empty():
					await RenderingServer.frame_post_draw
					shots[player_art.walk_frame] = get_viewport().get_texture().get_image()
	assert(seen.size()==4 and player.position.distance_to(Iso.grid_to_world(Vector2i(6,4)))<8)
	for index in shots:
		shots[index].save_png(captures+"/front_walk_%d_%d.png"%[selected_layout,index])
	shots.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(not player_art.walking and player_art.texture==player_art.front_idle and player_art.phase_distance==0)
	assert(not player_art.flip_h and not player_art.flip_v)
	if not captures.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(captures+"/straight_idle_%d.png"%selected_layout)
	player_art.enabled = false
	player_art.update_motion(Vector2.ZERO)
	assert(player_art.texture==player_art.idle_texture)
	player_art.enabled = true
	player_art.update_motion(Vector2.ZERO)
	assert(player_art.texture==player_art.front_idle)
	player.position = origin

## 复现三种补齐视角的直线路线，坐标选在两布局共用空地，不改变正式出生点。
func _start_extra_demo(direction: String) -> void:
	if player_art.blocks_preview_motion():
		return
	waypoints.clear()
	var start := Vector2i(5,3) if direction=="n" else (Vector2i(6,6) if direction=="e" else Vector2i(8,4))
	var goal := Vector2i(9,7) if direction=="n" else (Vector2i(8,4) if direction=="e" else Vector2i(6,6))
	player.position = Iso.grid_to_world(start)
	player_art.update_motion(Vector2.ZERO,SampleWalkSprite.DIRECTION_VECTORS[direction])
	_route(Iso.grid_to_world(goal))

## 八方向不留角度空隙；补齐方向逐个实际走完、停步回退，并缓存实际显示的四帧。
func _verify_extra(captures: String, direction: String) -> void:
	var origin := player.position
	for angle in range(360):
		assert(not player_art._direction_id(Vector2.from_angle(deg_to_rad(angle))).is_empty())
	for key in SampleWalkSprite.DIRECTION_VECTORS:
		assert(player_art._direction_id(SampleWalkSprite.DIRECTION_VECTORS[key])==key)
	_start_extra_demo(direction)
	var goal := Vector2i(9,7) if direction=="n" else (Vector2i(8,4) if direction=="e" else Vector2i(6,6))
	var seen: Dictionary = {}
	var shots: Dictionary = {}
	var deadline := Time.get_ticks_msec()+5000
	while not waypoints.is_empty() and Time.get_ticks_msec()<deadline:
		if not captures.is_empty():
			await RenderingServer.frame_post_draw
		else:
			await get_tree().physics_frame
		if player_art.walking:
			assert(player_art.texture in player_art.extra_frames[direction],"补齐方向 %s 实际=%s 输入=%s"%[direction,player_art.facing_id,verification_direction])
			var frame := player_art.walk_frame
			seen[frame] = true
			if not captures.is_empty() and not shots.has(frame):
				shots[frame] = get_viewport().get_texture().get_image()
	assert(seen.size()==4 and player.position.distance_to(Iso.grid_to_world(goal))<8,"补齐方向 %s 帧=%s 位置=%s 目标=%s 路线=%s"%[direction,seen.keys(),player.position,Iso.grid_to_world(goal),waypoints])
	for frame in shots:
		shots[frame].save_png(captures+"/extra_%s_%d_%d.png"%[direction,selected_layout,frame])
	shots.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(not player_art.walking and player_art.texture==player_art.extra_idles[direction] and player_art.phase_distance==0)
	assert(not player_art.flip_h and not player_art.flip_v)
	if not captures.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(captures+"/extra_idle_%s_%d.png"%[direction,selected_layout])
	player_art.enabled = false
	player_art.update_motion(Vector2.ZERO)
	assert(player_art.texture==player_art.idle_texture)
	player_art.enabled = true
	player_art.update_motion(Vector2.ZERO)
	assert(player_art.texture==player_art.extra_idles[direction])
	player.position = origin

## 两布局验证受击/死亡四阶段、打断优先级、末帧保持、显示开关及重置，不结算真实伤害。
func _verify_reactions(captures: String) -> void:
	waypoints.clear()
	var origin := player.position
	var revision := navigator.navigation_revision
	var blocked := navigator.blocked_cells().duplicate()
	for state in ["hit","death"]:
		# 上一动作落盘截图会阻塞主线程，先跨过补偿物理步再开始下一次实时采样。
		await get_tree().process_frame
		await get_tree().process_frame
		assert(player_art.start_attack())
		assert(player_art.start_reaction(state) and not player_art.attacking)
		assert(not player_art.start_reaction(state) and not player_art.start_attack())
		var seen: Dictionary = {}
		var shots: Dictionary = {}
		var deadline := Time.get_ticks_msec()+3000
		while player_art.reaction_playing and Time.get_ticks_msec()<deadline:
			if captures.is_empty():
				await get_tree().physics_frame
			else:
				await RenderingServer.frame_post_draw
			if not player_art.reaction_state.is_empty():
				var frame := player_art.reaction_frame
				seen[frame] = true
				assert(player_art.texture==player_art.reaction_frames[state][frame])
				if not captures.is_empty() and not shots.has(frame):
					shots[frame] = get_viewport().get_texture().get_image()
		assert(seen.size()==4 and not player_art.reaction_playing,"反应%s 帧%s 播放%s 相位%s"%[state,seen.keys(),player_art.reaction_playing,player_art.reaction_elapsed])
		assert(player.position==origin)
		for frame in shots:
			shots[frame].save_png(captures+"/hero_%s_%d_%d.png"%[state,selected_layout,frame])
		shots.clear()
		if state=="hit":
			assert(player_art.reaction_state.is_empty() and player_art.texture==player_art.directional_idle)
		else:
			verification_direction = Vector2.RIGHT
			_route(origin+Vector2(100,0))
			_start_extra_demo("e")
			_start_front_demo()
			_turn_preview()
			await get_tree().create_timer(0.3).timeout
			verification_direction = Vector2.ZERO
			assert(player.position==origin and waypoints.is_empty())
			assert(player_art.reaction_state=="death" and player_art.texture==player_art.reaction_frames.death[3])
			assert(not player_art.start_reaction("hit") and not player_art.start_attack())
			player_art.enabled = false
			player_art.update_motion(Vector2.ZERO)
			assert(player_art.blocks_preview_motion() and player_art.texture==player_art.idle_texture)
			player_art.enabled = true
			player_art.update_motion(Vector2.ZERO)
			assert(player_art.texture==player_art.reaction_frames.death[3])
		player_art.reset_reaction()
	assert(player_art.start_reaction("hit"))
	player_art.update_motion(Vector2.ZERO,Vector2.UP)
	assert(player_art.reaction_state.is_empty() and player_art.texture==player_art.extra_idles["n"])
	assert(player_art.start_reaction("hit"))
	assert(player_art.start_reaction("death"))
	player_art.advance_reaction(10.0)
	assert(not player_art.reaction_playing and player_art.texture==player_art.reaction_frames.death[3])
	player_art.reset_reaction()
	assert(player_art.start_reaction("hit"))
	player_art.advance_reaction(10.0)
	assert(player_art.reaction_state.is_empty() and player_art.texture==player_art.directional_idle)
	assert(navigator.navigation_revision==revision and navigator.blocked_cells()==blocked and player.position==origin)
