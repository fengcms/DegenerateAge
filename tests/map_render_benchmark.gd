extends Node
## 实际窗口的地图渲染 A/B 诊断，比较地面和地图 UI 的绘制成本。
## 冻结玩法后显式绘制，不代表完整战斗帧率；营地正式美术与原白盒用同场景比较。

var _rendered_frames := 0

## 递归冻结玩法节点，保持地图、视口和玩家位置样本可比。
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		freeze(child)

## 收集大/小地图控件，供按探索缓存规则刷新或隐藏。
func canvases(node: Node, out: Array[MapCanvas]) -> void:
	if node is MapCanvas:
		out.append(node)
	for child in node.get_children():
		canvases(child, out)

## 在 140 个真实渲染帧中采样帧间隔和绘制调用；前 20 帧用于预热。
func sample(label: String, player: PlayerCharacter, maps: Array[MapCanvas]) -> void:
	var origin := player.position
	var timings: Array[float] = []
	var draw_calls := 0.0
	var drawn_start := _rendered_frames
	var last := Time.get_ticks_usec()
	var refresh_at := last
	for i in range(140):
		player.position = origin + Vector2(sin(i * 0.025) * 60.0, 0)
		var now := Time.get_ticks_usec()
		if now - refresh_at >= 200000:
			refresh_at = now
			for map in maps:
				if map.is_visible_in_tree():
					map.refresh()
		await get_tree().process_frame
		# Force a real draw even if macOS occludes the test window.
		RenderingServer.force_draw(false)
		now = Time.get_ticks_usec()
		if i >= 20:
			timings.append((now - last) / 1000.0)
			draw_calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		last = now
	player.position = origin
	timings.sort()
	print("[PERF] %s: frame median %.3f ms, P95 %.3f ms, P99 %.3f ms, peak %.3f ms, draws %.1f" % [
		label, timings[timings.size() / 2], timings[int(timings.size() * 0.95)],
		timings[int(timings.size() * 0.99)], timings[-1], draw_calls / timings.size()])
	assert(_rendered_frames - drawn_start >= 140, "Each sample must actually render")
	print("[PERF] rendered frames: ", _rendered_frames - drawn_start)

## 在实际 GL 窗口中逐图测试正常、隐藏地面和隐藏地图 UI 三种绘制情形。
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("FAIL: MapRenderBenchmark requires --rendered")
		get_tree().quit(1)
		return
	RenderingServer.frame_post_draw.connect(func() -> void: _rendered_frames += 1)
	# Explicit draws avoid an occluded window silently skipping the render loop.
	RenderingServer.render_loop_enabled = false
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("[PERF] rendered viewport: ", get_viewport().get_visible_rect().size)
	var map_ids := ["camp"] if OS.get_environment("DEGENERATEAGE_RENDER_ONLY_CAMP") == "1" \
		else ["camp", "c2_lower_works", "wild_trial", "corruption_source"]
	for map_id in map_ids:
		GameState.reset_to_defaults()
		GameState.current_map = map_id
		var explored := {}
		var blocks := Fog.block_grid(map_id)
		for id in range(blocks.x * blocks.y):
			explored[str(id)] = true
		GameState.explored_maps[map_id] = explored
		var main := preload("res://scenes/Main.tscn").instantiate()
		add_child(main)
		freeze(main)
		var maps: Array[MapCanvas] = []
		canvases(main, maps)
		var player := main.get_node("Game/Entities/Player") as PlayerCharacter
		(player.get_node("Camera2D") as Camera2D).position_smoothing_enabled = false
		await sample(map_id + " normal", player, maps)
		var capture_dir := OS.get_environment("DEGENERATEAGE_RENDER_CAPTURE")
		if not capture_dir.is_empty():
			DirAccess.make_dir_recursive_absolute(capture_dir)
			get_viewport().get_texture().get_image().save_png(capture_dir.path_join(map_id + ".png"))
		var ground := main.get_node("Game/Ground") as IsoGround
		ground.hide()
		await sample(map_id + " ground hidden", player, maps)
		ground.show()
		for map in maps:
			map.hide()
		await sample(map_id + " maps hidden", player, maps)
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("[MapRenderBenchmark] PASS")
	get_tree().quit()
