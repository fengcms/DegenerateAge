extends "res://tools/camp_combat/main.gd"
## 模块化外围连续遭遇场，复用正式安全区、导航、刷新、战斗和拾取；不登记正式地图或存档。
const ROUTE_ID := "camp_route_trial"
const WAYPOINTS := [Vector2i(7,8),Vector2i(21,8),Vector2i(37,8),Vector2i(55,8)]
var spawner: MonsterSpawner
var reached_end := false
var trips := 0
var feedback: Label
var feedback_time := 0.0
var hud_time := 0.0
var route_verify := false
var defeated_points: Dictionary = {}

## 先复用实战装配，再改成同源长地图、跟随镜头和正式刷新点；共享表仅临时追加独立ID。
func _ready() -> void:
	super._ready()
	verify = false
	for enemy in enemies:
		enemy.free()
	enemies.clear()
	var definition := _map_definition()
	if DataLoader.get_entry("maps",ROUTE_ID)==null:
		DataLoader.tables.maps.append(definition)
	GameState.current_map = ROUTE_ID
	hero.position = Iso.grid_to_world(WAYPOINTS[0])
	hero.sample_art.previous_position = hero.position
	var ground := get_node("Ground") as IsoGround
	assert(ground.grid_size==Vector2i(definition.size.w,definition.size.h),"路线配置与实际地面尺寸不一致")
	ground.map_id = ROUTE_ID
	var camera := get_node("Camera2D") as Camera2D
	remove_child(camera)
	hero.add_child(camera)
	camera.position = Vector2(0,-70)
	spawner = load("res://tools/camp_combat/route_spawner.gd").new()
	spawner.scene = self
	add_child(spawner)
	spawner.setup(ground,hero)
	spawner.spawn_from_map(ROUTE_ID)
	var panel := HBoxContainer.new()
	panel.position = Vector2(20,102)
	caption.get_parent().add_child(panel)
	for index in range(WAYPOINTS.size()):
		var button := Button.new()
		button.text = ["返回营地","前往旧哨口","前往林间路","前往外围终点"][index]
		# 按钮只发送正式移动命令，人物仍须沿路线实际走到目标。
		button.pressed.connect(_travel.bind(index))
		panel.add_child(button)
	var rest := Button.new()
	rest.text = "原地休整（X）"
	rest.pressed.connect(_rest)
	panel.add_child(rest)
	feedback = Label.new()
	feedback.position = Vector2(20,142)
	caption.get_parent().add_child(feedback)
	EventBus.toast_requested.connect(_notice)
	route_verify = "--verify-route" in OS.get_cmdline_user_args()
	if route_verify:
		_verify_route.call_deferred()

## 用正式移动命令前往路线节点；安全区回程允许撤离，输入失败通过短消息反馈。
func _travel(index: int) -> void:
	GameState.set_auto_battle(false)
	if hero.request_map_move(Iso.grid_to_world(WAYPOINTS[index])):
		_notice("正在前往"+["营地","旧哨口","林间路","外围终点"][index],"info")
	else:
		_notice("当前无法移动；倒地后按R重新开始","info")

## 接收正式系统提示，复用一个Label，不为连续提示堆积节点。
func _notice(message: String, _kind: String) -> void:
	feedback.text = message
	feedback_time = 4.0
	hud_time = 0.0

## 每帧仅更新遮挡，HUD以5Hz同步；往返进度为场景展示，不额外发奖励。
func _process(delta: float) -> void:
	if hero==null or feedback==null:
		return
	for occluder in camp.occluders:
		occluder.update_reveal(hero.position,delta)
	feedback_time -= delta
	if feedback_time<=0:
		feedback.text = ""
	if hero.position.distance_to(Iso.grid_to_world(WAYPOINTS[3]))<65:
		reached_end = true
	if reached_end and MapService.is_in_safe_area(ROUTE_ID,hero.position):
		trips += 1
		reached_end = false
		_notice("已返回营地，可以休整后再次出发","info")
	hud_time -= delta
	if hud_time>0:
		return
	hud_time = 0.2
	caption.text = "营地外围 · WASD移动 / 点击怪物追击 · F自动战斗 / G拾取 · R重新开始\n生命 %d/%d · 自动战斗 %s · 击败 %d · 金币 %d · 拾取 %d · 完成往返 %d\n%s" % [GameState.player.hp,GameState.max_hp(),"开" if GameState.auto_battle_on else "关",kills,GameState.gold,pickups,trips,"已经倒地，按R重新开始" if hero.is_dead else "正在休整恢复，移动或受击会中断" if hero.is_sitting else "营地内安全，X休整恢复；怪物击败60秒后刷新"]

## 从当前存活实体中选择离点击脚底最近的目标，避免长期持有死亡实体引用。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("sit_toggle"):
		_rest()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var point := get_global_mouse_position()
		var nearest: Monster
		var distance := 55.0
		for node in get_tree().get_nodes_in_group("enemies"):
			var enemy := node as Monster
			if enemy==null or enemy.is_dead:
				continue
			var candidate := point.distance_to(enemy.global_position+Vector2(0,-35))
			if candidate<distance:
				distance = candidate
				nearest = enemy
		if nearest!=null:
			hero.request_target_attack(nearest)
		else:
			hero.request_map_move(point)
		return
	super._unhandled_input(event)

## 正式走过三个窄口、战斗并回营；超时或死亡失败，不能用传送冒充路线完成。
func _verify_route() -> void:
	assert((get_node("Ground") as IsoGround).grid_size==Vector2i(64,16))
	var initial_created: int = spawner.created
	for index in range(1,4):
		_travel(index)
		var deadline := Time.get_ticks_msec()+60000
		while hero.position.distance_to(Iso.grid_to_world(WAYPOINTS[index]))>35 and Time.get_ticks_msec()<deadline:
			await get_tree().physics_frame
			assert(not hero.is_dead,"路线移动中死亡")
		assert(hero.position.distance_to(Iso.grid_to_world(WAYPOINTS[index]))<=35,"窄口路线未抵达")
		await _capture("route_arrive_%d"%index)
		for point_index in range((index-1)*2,index*2):
			var point: Dictionary = spawner._points[point_index]
			var key := String(point.monster_id)+"#"+str(point.ordinal)
			var before := int(defeated_points.get(key,0))
			assert(is_instance_valid(point.entry),"本组刷新点未激活")
			assert(hero.request_target_attack(point.entry))
			deadline = Time.get_ticks_msec()+60000
			while int(defeated_points.get(key,0))==before and Time.get_ticks_msec()<deadline:
				await get_tree().physics_frame
				assert(not hero.is_dead,"遭遇战中死亡")
			assert(int(defeated_points.get(key,0))>before,"未击败指定遭遇点，不能以其他刷新的击杀替代")
		await get_tree().create_timer(3.0).timeout
		await _capture("route_encounter_%d"%index)
		print("ROUTE_ENCOUNTER: ",index," kills=",kills," hp=",GameState.player.hp," created=",spawner.created)
	_travel(3)
	var deadline := Time.get_ticks_msec()+30000
	while not reached_end and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
	assert(reached_end)
	_travel(0)
	deadline = Time.get_ticks_msec()+60000
	while trips<1 and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
		assert(not hero.is_dead)
	assert(trips==1 and pickups>0 and GameState.gold>0)
	assert(spawner.created>initial_created,"未实际加载后续刷新点")
	await _capture("route_return")
	print("CAMP_ROUTE_OK: kills=",kills," pickups=",pickups," created=",spawner.created," trips=",trips)
	get_tree().quit()

## 读取本场独立地图配置；压力验收可覆盖该入口，正式地图表不写盘。
func _map_definition() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tools/camp_combat/route_map.json"))

## 调用现有休整规则，不额外恢复生命；本阶段使用待机外观，HUD明确休整状态。
func _rest() -> void:
	hero.set_sitting(not hero.is_sitting)

## 以正式刷新点身份登记死亡，验收不能把旧组重生后的击杀误算成后续遭遇。
func _on_point_killed(_id: String, key: String) -> void:
	defeated_points[key] = int(defeated_points.get(key,0))+1
