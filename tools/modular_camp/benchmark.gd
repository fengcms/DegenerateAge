extends "res://main.gd"
## 隔离营地正常窗口性能采样：两布局各预热3秒、移动30秒，不强制绘制、不写正式存档。
## 输出帧间隔分位、绘制次数、节点与内存；仅小样本基线，不代表密集战斗或长期挂机。

## 沿用样板初始化，再启动专用采样；正常窗口可见性由实际绘制帧计数核对。
func _ready() -> void:
	super._ready()
	_benchmark.call_deferred()

## 对每个布局固定路线往返并播放两怪攻击，按实际时钟采样，最后检查反复切图的节点释放。
func _benchmark() -> void:
	var layout_nodes: Dictionary = {}
	for index in range(2):
		_switch_layout(index)
		await get_tree().create_timer(3.0).timeout
		var samples: Array[float] = []
		var draw_calls: Array[float] = []
		var physics_ms: Array[float] = []
		var script_ms: Array[float] = []
		var started := Time.get_ticks_usec()
		var previous := started
		var drawn_before := Engine.get_frames_drawn()
		var next_attack := started
		var outbound := true
		var nodes_before := get_tree().get_node_count()
		layout_nodes[index] = nodes_before
		var previous_position := player.position
		var traveled := 0.0
		while Time.get_ticks_usec()-started<30000000:
			if waypoints.is_empty():
				_route(Iso.grid_to_world(Vector2i(13,13) if outbound else Vector2i(layouts[index].start[0],layouts[index].start[1])))
				outbound = not outbound
			if Time.get_ticks_usec()>=next_attack:
				_start_monster_attacks()
				next_attack = Time.get_ticks_usec()+1000000
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now-previous)/1000.0)
			previous = now
			traveled += player.position.distance_to(previous_position)
			previous_position = player.position
			draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
			script_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
		var drawn := Engine.get_frames_drawn()-drawn_before
		assert(drawn>=samples.size()*0.9,"正常窗口未持续绘制，本轮不能作为渲染性能基线")
		assert(traveled>100,"采样期间没有真实移动，不能代表移动场景")
		assert(get_tree().get_node_count()==nodes_before,"持续移动期间节点增长")
		print("CAMP_BENCHMARK: ",JSON.stringify({"layout":index,"traveled_pixels":traveled,"samples":samples.size(),"drawn":drawn,"frame_ms":_distribution(samples),"process_ms":_distribution(script_ms),"physics_ms":_distribution(physics_ms),"draw_calls":_distribution(draw_calls),"nodes":nodes_before,"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC)}))
	for cycle in range(6):
		_switch_layout(cycle%2)
		await get_tree().process_frame
		await get_tree().process_frame
		assert(get_tree().get_node_count()==layout_nodes[cycle%2],"重复切图后节点未释放")
		print("CAMP_RELEASE: ",cycle," nodes=",get_tree().get_node_count()," static_bytes=",Performance.get_monitor(Performance.MEMORY_STATIC))
	print("MODULAR_CAMP_BENCHMARK_OK")
	get_tree().quit()

## 对本阶段离线样本排序输出毫秒分位与峰值；不在正常游戏热路径调用。
func _distribution(values: Array[float]) -> Dictionary:
	values.sort()
	return {"median":values[values.size()/2],"p95":values[mini(values.size()-1,floori(values.size()*0.95))],"p99":values[mini(values.size()-1,floori(values.size()*0.99))],"max":values[-1]}
