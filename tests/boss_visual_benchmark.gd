extends Node2D
## 固定窗口、几何与数量对照旧预警和新表现的绘制成本；不代表完整战斗帧率。
var geos: Array[Dictionary] = []
var modern := false
var frame_ms: Array[float] = []
var draw_ms: Array[float] = []
var calls: Array[float] = []
var skin := {"color": "ce99d6", "motif": "seal", "marks": 8}

## 真实窗口预热后分别测1、18、100个重叠技能，记录整帧与绘制脚本分位数。
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1280, 800))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 120
	RenderingServer.set_default_clear_color(Color("17212a"))
	for count in [1, 18, 100]:
		_build(count)
		for mode in [false, true]:
			modern = mode
			frame_ms.clear()
			draw_ms.clear()
			calls.clear()
			for frame in range(140):
				var start := Time.get_ticks_usec()
				queue_redraw()
				await RenderingServer.frame_post_draw
				if frame >= 20:
					frame_ms.append((Time.get_ticks_usec() - start) / 1000.0)
					calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				elif frame == 19:
					draw_ms.clear()
			print("[BossVisualBenchmark] ", JSON.stringify({"count":count, "modern":modern, "frame_ms":_summary(frame_ms), "draw_script_ms":_summary(draw_ms), "draw_calls":_summary(calls), "nodes":get_tree().get_node_count(), "static_memory":Performance.get_monitor(Performance.MEMORY_STATIC), "video_memory":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}))
	print("[BossVisualBenchmark] 全部通过 ✅")
	get_tree().quit()

## 使用相同的固定地面几何，环形占四分之一，不执行游戏伤害或AI。
func _build(count: int) -> void:
	geos.clear()
	for i in range(count):
		var center := Iso.to_ground(Vector2(260 + (i % 10) * 70, 220 + (i / 10) * 35))
		match i % 4:
			0: geos.append({"kind":"ring", "center":center, "inner":50.0, "radius":110.0})
			1: geos.append({"kind":"circle", "center":center, "radius":100.0})
			2: geos.append({"kind":"fan", "center":center, "dir":Vector2.RIGHT, "radius":140.0, "arc":2.0})
			3: geos.append({"kind":"line", "from":center, "to":center + Vector2(220, 0), "half":30.0})

## 按旧代码原有分片数绘制基线；新版走正式表现入口及其装饰预算。
func _draw() -> void:
	var start := Time.get_ticks_usec()
	for geo in geos:
		if modern:
			BossSkillVisual.warning(self, geo, 0.7, skin)
		else:
			var fill := Color(1.0, 0.18, 0.08, 0.24)
			var edge := Color("ff7744")
			var center := Iso.from_ground(geo.get("center", Vector2.ZERO))
			match geo.kind:
				"ring":
					GroundFx.band(self, center, geo.inner, geo.radius, fill, 48)
					GroundFx.outline(self, center, geo.radius, Color("ffb454"), 3.0, 48)
					GroundFx.outline(self, center, geo.inner, Color("ffb454"), 2.0, 32)
				"circle":
					GroundFx.fill(self, center, geo.radius, fill)
					GroundFx.outline(self, center, geo.radius, edge, 2.0, 48)
				"fan":
					GroundFx.sector(self, center, Iso.from_ground(geo.dir), geo.radius, geo.arc, fill, 12)
					GroundFx.sector_outline(self, center, Iso.from_ground(geo.dir), geo.radius, geo.arc, edge, 2.0, 12)
				"line":
					var a := Iso.from_ground(geo["from"])
					var b := Iso.from_ground(geo["to"])
					GroundFx.band_quad(self, a, b, geo.half, fill)
					draw_line(a, b, edge, 2.0, true)
	draw_ms.append((Time.get_ticks_usec() - start) / 1000.0)

## 排序计算中位、尾部和峰值；单位由调用方字段说明。
func _summary(values: Array[float]) -> Dictionary:
	values.sort()
	return {"p50":values[int(values.size() * 0.5)], "p95":values[int(values.size() * 0.95)], "p99":values[int(values.size() * 0.99)], "max":values[-1]}
