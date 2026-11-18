extends Node2D
## 模块化营地真实战斗场：正式玩家/怪物/自动战斗/地面物，只替换场景装配和表现。
## 仅隔离启动器使用，不登记正式地图，不写玩家真实存档；F自动战斗、G拾取、R重开。
const Art = preload("res://tools/camp_combat/art.gd")
static var completed_waves := 0
static var release_counts: Array[int] = []
var soak := false
var recording := false
var samples: Array[float] = []
var drawn_start := 0
var previous_usec := 0
var slow_frames: Array[Dictionary] = []
var camp: Node2D
var hero: PlayerCharacter
var enemies: Array[Monster] = []
var caption: Label
var kills := 0
var pickups := 0
var damage_events := 0
var captured := false
var verify := false

## 创建独立初始角色和两怪遭遇，正式数值模板不改；使用三级成长作为本场演示起点。
func _ready() -> void:
	assert(OS.get_environment("DEGENERATE_CAMP_ISOLATED")=="1","必须经隔离启动器启动战斗样板")
	soak = "--soak-combat" in OS.get_cmdline_user_args()
	verify = "--verify-combat" in OS.get_cmdline_user_args() or soak
	GameState.reset_to_defaults()
	GameState.menu_mode = "world"
	GameState.current_map = "wild_trial"
	GameState.add_xp(800)
	GameState.player.hp = GameState.max_hp()
	GameState.settings.dropFlyAnim = true
	add_to_group("map_world")
	camp = load("res://tools/modular_camp/main.gd").new()
	add_child(camp)
	camp.set_physics_process(false)
	camp.set_process_unhandled_input(false)
	camp.label.hide()
	camp.world.position = Vector2.ZERO
	camp.player.free()
	for mover in camp.monster_movers:
		mover.free()
	for actor in camp.monster_previews:
		actor.free()
	var ground := load("res://tools/camp_combat/ground.gd").new() as IsoGround
	ground.name = "Ground"
	ground.cave = camp.navigator
	ground.map_id = "wild_trial"
	add_child(ground)
	var loot := Node2D.new()
	loot.add_to_group("loot_root")
	add_child(loot)
	hero = preload("res://scenes/entities/Player.tscn").instantiate()
	hero.position = Iso.grid_to_world(Vector2i(3,3))
	add_child(hero)
	hero.get_node("Camera2D").queue_free()
	hero.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	hero.safe_margin = 0.001
	_replace_art(hero,"hero")
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = Vector2(0,-260)
	add_child(camera)
	for entry in [{"id":"wolf_corrupted","art":"wolf","cell":Vector2i(9,5)},{"id":"shellback_bug","art":"beetle","cell":Vector2i(11,10)}]:
		var enemy := preload("res://scenes/entities/Monster.tscn").instantiate() as Monster
		enemy.monster_id = entry.id
		enemy.ai_enabled = true
		enemy.position = Iso.grid_to_world(entry.cell)
		add_child(enemy)
		enemy.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		enemy.safe_margin = 0.001
		_replace_art(enemy,entry.art)
		enemy.appearance_head_hp_y = -92.0
		enemy.died.connect(_on_kill)
		enemies.append(enemy)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	caption = Label.new()
	caption.position = Vector2(20,15)
	canvas.add_child(caption)
	EventBus.item_picked.connect(_on_pickup)
	EventBus.damage_dealt.connect(_on_damage)
	GameState.set_auto_pickup(true)
	print("COMBAT_READY level=",GameState.player.level," attack=",GameState.total_attack()," hp=",GameState.player.hp)
	if verify:
		_run_verification.call_deferred()

## 只替换宿主动作对象，保留正式调用接口与死亡清理识别，不改攻击或掉落函数。
func _replace_art(actor: CharacterBody2D, kind: String) -> void:
	if actor.sample_art != null:
		actor.sample_art.free()
	if actor is Monster and actor.dummy_art != null:
		actor.dummy_art.free()
		actor.dummy_art = null
	var art := Art.new()
	actor.add_child(art)
	art.setup(actor,kind)
	actor.sample_art = art
	actor.queue_redraw()

## 按键调用正式自动控制；点击敌人发起正式追击攻击，点击空地使用正式导航移动。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("auto_battle"):
		GameState.toggle_auto_battle()
	elif event.is_action_pressed("auto_pickup"):
		GameState.toggle_auto_pickup()
	elif event is InputEventKey and event.pressed and event.keycode==KEY_R:
		get_tree().reload_current_scene()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var point := get_global_mouse_position()
		for enemy in enemies:
			if is_instance_valid(enemy) and not enemy.is_dead and point.distance_to(enemy.global_position+Vector2(0,-35))<55:
				hero.request_target_attack(enemy)
				return
		hero.request_map_move(point)

## 固定两只遮挡物更新及简明战斗状态；不扫描地图，不加载素材，不自行结算奖励。
func _process(delta: float) -> void:
	if hero==null or caption==null:
		return
	if recording:
		var now := Time.get_ticks_usec()
		var elapsed_ms := float(now-previous_usec)/1000.0
		samples.append(elapsed_ms)
		if elapsed_ms>25:
			slow_frames.append({"frame":samples.size(),"ms":elapsed_ms,"damage":damage_events,"kills":kills,"pickups":pickups,"pose":hero.sample_art.pose,"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000})
		previous_usec = now
	for occluder in camp.occluders:
		occluder.update_reveal(hero.position,delta)
	caption.text = "营地战斗样板 · WASD移动 / 点击怪物追击 · F自动战斗 / G拾取 · R重新开始\n生命 %d/%d · 自动战斗 %s · 击败 %d/2 · 金币 %d · 拾取 %d\n击败腐化野狼与裂壳虫，收集战利品；R可重新开始" % [GameState.player.hp,GameState.max_hp(),"开" if GameState.auto_battle_on else "关",kills,GameState.gold,pickups]

## 只统计正式死亡信号，不在展示层发经验或掉落。
func _on_kill(_id: String) -> void:
	kills += 1

## 只统计正式物品拾取通知，金币和背包由既有入口修改。
func _on_pickup(_id: String) -> void:
	pickups += 1

## 记录正式攻击结算事件，供验收确认不是直接把怪物血量归零。
func _on_damage(_target: Node, _amount: int, _critical: bool) -> void:
	damage_events += 1

## 在真实物理时钟下完成追踪、互相攻击、死亡、正式掉落与拾取；失败不打印成功标记。
func _run_verification() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if soak:
		recording = true
		previous_usec = Time.get_ticks_usec()
		drawn_start = Engine.get_frames_drawn()
	var origin := hero.position
	var initial_xp := int(GameState.player.xp)
	GameState.set_auto_battle(true)
	var deadline := Time.get_ticks_msec()+90000
	var next_report := Time.get_ticks_msec()+3000
	while Time.get_ticks_msec()<deadline and (kills<2 or pickups<1):
		await get_tree().physics_frame
		if Time.get_ticks_msec()>=next_report:
			print("COMBAT_PROGRESS kills=",kills," attacks=",damage_events," pos=",hero.position," hp=",GameState.player.hp," auto=",GameState.auto_battle_on)
			next_report = Time.get_ticks_msec()+3000
		assert(not hero.is_dead,"样板玩家死亡，不能通过完整战斗验收")
		if not captured and damage_events>0:
			await _capture("combat")
			captured = true
	assert(kills==2 and damage_events>0,"未通过正式攻击完成两怪击杀")
	assert(hero.position.distance_to(origin)>20,"未发生真实追击移动")
	assert(pickups>0 and GameState.gold>0,"正式掉落未拾取入账")
	assert(hero.sample_art.hit_count>0,"怪物未实际命中玩家")
	assert(int(GameState.player.xp)!=initial_xp,"未通过正式死亡入口结算经验")
	await get_tree().create_timer(2.0).timeout
	for enemy in enemies:
		assert(not is_instance_valid(enemy),"死亡动画后未释放怪物")
	var loot_layer := get_tree().get_first_node_in_group("loot_root")
	var cleanup_deadline := Time.get_ticks_msec()+15000
	while loot_layer.get_child_count()>0 and Time.get_ticks_msec()<cleanup_deadline:
		await get_tree().physics_frame
	assert(loot_layer.get_child_count()==0,"拾取后地面物未清理")
	GameState.set_auto_battle(false)
	GameState.set_auto_pickup(false)
	await get_tree().create_timer(1.5).timeout
	await _capture("completed")
	if soak:
		recording = false
		_report_wave()
		completed_waves += 1
		if completed_waves<3:
			get_tree().reload_current_scene()
			return
		assert(release_counts[2]==release_counts[0],"同场重开后节点持续增长")
		print("CAMP_COMBAT_SOAK_OK: waves=3")
	print("CAMP_COMBAT_VERIFY_OK: kills=",kills," damage_events=",damage_events," pickups=",pickups," gold=",GameState.gold)
	get_tree().quit()

## 仅窗口验收主动绘制截图，路径由隔离启动参数提供，不作为性能测量。
func _capture(name: String) -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			await get_tree().process_frame
			RenderingServer.force_draw(false)
			get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--capture=")+"/"+name+".png")

## 正常窗口三轮真实战斗采样，不调用强制绘制；保留尖峰和节点数，静态内存仅作观测。
func _report_wave() -> void:
	var drawn := Engine.get_frames_drawn()-drawn_start
	assert(drawn>=samples.size()*0.9,"窗口没有持续绘制，不能作为战斗性能样本")
	print("COMBAT_SLOW_FRAMES: ",JSON.stringify(slow_frames))
	samples.sort()
	release_counts.append(get_tree().get_node_count())
	print("COMBAT_WAVE: ",JSON.stringify({"wave":completed_waves,"frames":samples.size(),"drawn":drawn,"median_ms":samples[samples.size()/2],"p95_ms":samples[mini(samples.size()-1,floori(samples.size()*0.95))],"p99_ms":samples[mini(samples.size()-1,floori(samples.size()*0.99))],"peak_ms":samples[-1],"nodes":get_tree().get_node_count(),"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}))
