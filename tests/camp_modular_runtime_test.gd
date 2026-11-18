extends Node
## 正式Game营地的窗口短时装配/渲染回归；固定镜头三轮加载，记录真实绘制覆盖、帧时与节点。
## 不声称战斗帧率；路线、碰撞、NPC和旧档由营地集成验收覆盖。本测试不写真实存档。
var drawn := 0

## 统计实际提交的绘制帧，窗口被遮挡导致覆盖不足必须失败。
func _count_draw() -> void:
	drawn += 1

## 装配正式世界三次并采样，每轮释放地图；无窗口仅进行资源/生命周期契约检查。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "camp"
	var rendered := DisplayServer.get_name()!="headless"
	if rendered:
		DisplayServer.window_move_to_foreground()
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP,true)
		RenderingServer.frame_post_draw.connect(_count_draw)
	Engine.max_fps = 120
	var results: Array = []
	for round_index in range(3):
		var start := Time.get_ticks_usec()
		var world := preload("res://scenes/Game.tscn").instantiate()
		add_child(world)
		var load_ms := (Time.get_ticks_usec()-start)/1000.0
		await get_tree().physics_frame
		var player := world.get_node("Entities/Player") as PlayerCharacter
		player.set_physics_process(false)
		player.velocity = Vector2.ZERO
		var ground := world.get_node("Ground") as IsoGround
		var modular := ground.get_node_or_null("ModularTerrain")
		if modular != null:
			assert(modular.get_child_count()==3,"模块地面必须固定三个合批节点")
			for id in ["blacksmith","merchant","elder_tree"]:
				var prop := ground.get_node("Camp_%s_front" % id)
				assert(prop.material is ShaderMaterial,"新模块必须保留局部遮挡材质")
				assert(prop.get("mask_image") != null,"屋顶树冠遮挡掩码缺失")
				_check_reveal(prop,ground)
		var samples: Array[float] = []
		var coverage := drawn
		var previous := Time.get_ticks_usec()
		var count := 600 if rendered else 4
		for index in range(count):
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			samples.append((now-previous)/1000.0)
			previous = now
		if rendered:
			assert(drawn-coverage>=count*0.9,"真实绘制覆盖不足，不接受性能结果")
		samples.sort()
		results.append({"round":round_index,"load_ms":load_ms,"frames":count,"drawn":drawn-coverage,
			"median_ms":samples[int(count*0.5)],"p95_ms":samples[int(count*0.95)],"p99_ms":samples[int(count*0.99)],"peak_ms":samples[-1],
			"nodes":get_tree().get_node_count(),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
			"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
		world.queue_free()
		await get_tree().process_frame
	assert(results[1].nodes==results[2].nodes,"重载营地节点数持续增加")
	var tag := "baseline" if OS.get_environment("CAMP_RUNTIME_BASELINE")=="1" else "modular"
	FileAccess.open("/tmp/degenerateage-camp-runtime-"+tag+".json",FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	print("[CampModularRuntimeTest] PASS")
	get_tree().quit()

## 在真实可走位置寻找遮挡样本，验证后方局部淡出及前方恢复，不改变物理轮廓。
func _check_reveal(prop: Node2D, ground: IsoGround) -> void:
	var found := false
	for dx in range(-240,241,24):
		for dy in range(-180,0,24):
			var point: Vector2 = prop.position+Vector2(dx,dy)
			if ground.is_walkable_cell(Vector2i(Iso.world_to_grid(point).round())) and prop.overlaps_actor(point):
				prop.update_reveal(point,0.3)
				assert(prop.target_reveal and is_equal_approx(prop.reveal_amount,1.0),"可走位置遮挡未淡出")
				found = true
				break
		if found:
			break
	assert(found,"模块缺少可走后方遮挡验收点："+prop.name)
	prop.update_reveal(prop.position+Vector2(0,24),0.3)
	assert(not prop.target_reveal and is_zero_approx(prop.reveal_amount),"前方未恢复完整物件")
