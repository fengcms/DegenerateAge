extends Node
## 营地 A/B 样板固定窗口绘制基准，分别在独立进程加载单一风格。
## 输出相同镜头的三个倍率截图、场景初次/热装配时间与真实绘制帧统计；不代表战斗帧率。

const SAMPLE := preload("res://tests/CampStyleSample.tscn")

var _rendered_frames := 0

## 在 macOS Retina 1280×800 逻辑窗口中装配、采样并释放唯一风格样板。
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("FAIL: CampStyleBenchmark requires --rendered")
		get_tree().quit(1)
		return
	var style := OS.get_environment("DEGENERATEAGE_CAMP_BENCH_STYLE")
	assert(style in ["a", "b"], "分别以 a、b 单独启动固定窗口基准")
	RenderingServer.frame_post_draw.connect(_count_rendered_frame)
	RenderingServer.render_loop_enabled = false
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(2560, 1600))
	await get_tree().process_frame
	var baseline_texture := float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	var start := Time.get_ticks_usec()
	var sample := SAMPLE.instantiate()
	add_child(sample)
	var first_load_ms := (Time.get_ticks_usec() - start) / 1000.0
	await get_tree().physics_frame
	sample._help.visible = false
	_freeze(sample.world)
	var runs := {}
	for zoom in [1.0, 1.5, 2.0]:
		runs[str(zoom)] = await _measure_zoom(sample, style, zoom)
	var loaded_texture := float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	sample.queue_free()
	await get_tree().process_frame
	start = Time.get_ticks_usec()
	var warm_sample := SAMPLE.instantiate()
	add_child(warm_sample)
	var warm_load_ms := (Time.get_ticks_usec() - start) / 1000.0
	warm_sample.queue_free()
	var result := {
		"style": style.to_upper(),
		"logical_viewport": get_viewport().get_visible_rect().size,
		"physical_capture": [2560, 1600],
		"screen_scale": DisplayServer.screen_get_scale(),
		"first_scene_load_ms": first_load_ms,
		"warm_scene_load_ms": warm_load_ms,
		"texture_monitor_before_bytes": baseline_texture,
		"texture_monitor_loaded_bytes": loaded_texture,
		"texture_monitor_delta_bytes": loaded_texture - baseline_texture,
		"zoom_runs": runs,
	}
	var file := FileAccess.open("/tmp/camp_style_benchmark_%s.json" % style, FileAccess.WRITE)
	assert(file != null, "基准结果不可写")
	file.store_string(JSON.stringify(result, "\t") + "\n")
	print("[PERF] 营地样板 %s 首装 %.2f ms / 热装 %.2f ms / 纹理监视器差 %.2f MiB" % [
		style.to_upper(), first_load_ms, warm_load_ms,
		(loaded_texture-baseline_texture)/1048576.0])
	print("[CampStyleBenchmark] PASS")
	get_tree().quit()

## 记录确实发生的渲染帧，防止被窗口遮挡或最小化时产生虚假快数据。
func _count_rendered_frame() -> void:
	_rendered_frames += 1

## 冻结世界玩法更新，使 A/B 仅比较静态场景同镜头的渲染；不修改节点或资源。
func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

## 每个倍率预热 20 帧并采样 100 帧，记录帧间隔分位数、绘制调用和截图。
func _measure_zoom(sample: Node2D, style: String, zoom: float) -> Dictionary:
	sample._set_zoom(zoom)
	sample.camera.reset_smoothing()
	var durations: Array[float] = []
	var calls := 0.0
	var start_frames := _rendered_frames
	var previous := Time.get_ticks_usec()
	for frame in range(120):
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		var now := Time.get_ticks_usec()
		if frame >= 20:
			durations.append((now - previous) / 1000.0)
			calls += RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		previous = now
	durations.sort()
	assert(_rendered_frames - start_frames >= 120, "样板倍率未实际绘制：%.1f" % zoom)
	var capture := "/tmp/camp_style_benchmark_%s_%d.png" % [style, roundi(zoom*100.0)]
	assert(get_viewport().get_texture().get_image().save_png(capture) == OK,
		"基准截图失败：%s" % capture)
	var result := {
		"median_ms": durations[durations.size()/2],
		"p95_ms": durations[int(durations.size()*0.95)],
		"p99_ms": durations[int(durations.size()*0.99)],
		"peak_ms": durations[-1],
		"draw_calls_mean": calls/durations.size(),
		"rendered_frames": _rendered_frames-start_frames,
		"capture": capture,
	}
	print("[PERF] 营地样板 %s %d%% 中位 %.2f ms / P95 %.2f ms / 绘制 %.1f" % [
		style.to_upper(), roundi(zoom*100.0), result["median_ms"], result["p95_ms"],
		result["draw_calls_mean"]])
	return result
