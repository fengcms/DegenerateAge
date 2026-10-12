extends Node
## M5-9a 显示适配实测（开发期工具，M5 打包前随其他工具清理）。依据：工程文档 17 §4 M5-9a / §5 U1。
##
## 目的：证明渲染策略切换后「窗口放大 = 看到更多地图，元素像素尺寸不变」，
##       并实测 U1（Retina 下 get_visible_rect() 的单位）。
##
## 运行（**必须开窗**：需要真实渲染与窗口尺寸变化）：
##   GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##   "$GODOT" --path . res://tests/DisplayProbe.tscn -- --tag=after
##   "$GODOT" --path . res://tests/DisplayProbe.tscn -- --tag=before --legacy   # 复现旧策略做对照
##   参数：--tag=名称（输出文件名后缀，默认 after）｜--legacy（推回 canvas_items 复现旧行为）
##
## 策略由主场景 `main.gd` → `SettingsRuntime.apply_display_strategy()` 在运行时应用
## （见该函数注释：为何不写进 project.godot）。
##
## 输出：
##   /tmp/degenerateage_m59a_<tag>_<W>x<H>.png   （各窗口尺寸截图）
##   stdout 指标表：窗口尺寸 / 可见视口 / 世界→窗口总倍率 / 玩家像素高 / 可见世界宽高

const MAIN_SCENE := "res://scenes/Main.tscn"
const MAP_ID := "wild_trial"
const SIZES: Array[Vector2i] = [Vector2i(1280, 800), Vector2i(1920, 1200)]

var _failures: Array[String] = []
var _rows: Array[Dictionary] = []
var _tag := "after"
var _legacy := false

var _main: Node = null
var _player: PlayerCharacter = null
var _cam: Camera2D = null

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--tag="):
			_tag = String(arg).split("=", true, 1)[1]
		elif String(arg) == "--legacy":
			_legacy = true
	await _run()
	get_tree().quit(0 if _failures.is_empty() else 1)

func _run() -> void:
	print("========== M5-9a 显示适配实测（tag=%s）==========" % _tag)
	print("[策略] stretch/mode = %s ｜ aspect = %s" % [
		str(ProjectSettings.get_setting("display/window/stretch/mode", "(默认)")),
		str(ProjectSettings.get_setting("display/window/stretch/aspect", "(默认)")),
	])
	_dump_u1()

	GameState.reset_to_defaults()
	GameState.menu_mode = "world"
	GameState.current_map = MAP_ID

	_main = load(MAIN_SCENE).instantiate()
	add_child(_main)
	for _i in range(25):
		await get_tree().process_frame

	# 探针里 Main 不是 current_scene，菜单不会自动打开；仍显式收口，避免污染截图。
	var menu: Control = _main.get_node_or_null("UI/MenuPanel")
	if menu != null:
		menu.visible = false
	get_tree().paused = false
	# --legacy：把主场景已应用的 disabled 推回 canvas_items，复现旧策略（回归对照基线）。
	if _legacy:
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		for _i in range(5):
			await get_tree().process_frame
	print("[策略生效] content_scale_mode = %d（0=DISABLED / 1=CANVAS_ITEMS）｜可见视口 = %s" % [
		int(get_window().content_scale_mode), str(get_viewport().get_visible_rect().size),
	])

	_player = _main.get_node_or_null("Game/Entities/Player") as PlayerCharacter
	_cam = _main.get_node_or_null("Game/Entities/Player/Camera2D") as Camera2D
	if _player == null or _cam == null:
		_failures.append("主场景缺少 Player / Camera2D")
		return

	# 固定场景：停掉玩家与自动战斗、清场怪物 —— 保证各尺寸截图只有"视野"一个变量。
	_player.set_physics_process(false)
	_player.set_process_input(false)
	_player.set_process_unhandled_input(false)
	var pilot: Node = _player.get_node_or_null("AutoPilot")
	if pilot != null:
		pilot.set_physics_process(false)
	var spawner: Node = _main.get_node_or_null("Game/Spawner")
	if spawner != null:
		spawner.set_process(false)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame

	var ground: Node = _main.get_node_or_null("Game/Ground")
	if ground != null:
		_player.global_position = ground.call("get_map_center_world")
	_cam.reset_smoothing()
	for _i in range(3):
		await get_tree().process_frame
	_cam.reset_smoothing()

	for size in SIZES:
		await _measure_at(size)

	_report()
	if not _failures.is_empty():
		for message in _failures:
			print("[DisplayProbe] 失败：", message)

## U1：确认 macOS 下视口可见尺寸的单位（逻辑点 or 物理像素）。
func _dump_u1() -> void:
	var window := get_window()
	var vp := get_viewport()
	print("[U1] 屏幕缩放 DisplayServer.screen_get_scale() = %.4f" % DisplayServer.screen_get_scale())
	print("[U1] 屏幕逻辑尺寸 screen_get_size()      = %s" % str(DisplayServer.screen_get_size()))
	print("[U1] 窗口尺寸 window.size               = %s" % str(window.size))
	print("[U1] 窗口尺寸 DisplayServer.window_get_size() = %s" % str(DisplayServer.window_get_size()))
	print("[U1] 可见视口 get_visible_rect().size   = %s" % str(vp.get_visible_rect().size))
	print("[U1] 视口物理尺寸 vp.get_visible_rect().size × screen_get_scale() = %s" % str(vp.get_visible_rect().size * DisplayServer.screen_get_scale()))
	print("[U1] allow_hidpi = %s" % str(ProjectSettings.get_setting("display/window/dpi/allow_hidpi", true)))
	print("[U1] content_scale_factor = %.4f" % vp.content_scale_factor)
	print("[U1] 根窗口 content_scale_mode = %d（0=DISABLED / 1=CANVAS_ITEMS / 2=VIEWPORT）" % int(window.content_scale_mode))
	print("[U1] 特性标签 OS.has_feature: headless=%s macos=%s debug=%s" % [
		str(OS.has_feature("headless")), str(OS.has_feature("macos")), str(OS.has_feature("debug")),
	])
	print("[U1] 启动参数 = %s" % str(OS.get_cmdline_args()))

## 切到指定窗口尺寸，采指标 + 截图。
func _measure_at(size: Vector2i) -> void:
	var window := get_window()
	window.size = size
	for _i in range(15):
		await get_tree().process_frame
	# 无头下没有渲染帧，frame_post_draw 永不发射 —— 必须跳过，否则挂死。
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

	var vp := get_viewport()
	var canvas_scale := vp.get_canvas_transform().get_scale()
	var final_scale := vp.get_final_transform().get_scale()
	var to_window := canvas_scale * final_scale
	var vis := vp.get_visible_rect().size
	var row := {
		"requested": size,
		"window": window.size,
		"visible": vis,
		"zoom": _cam.zoom,
		"canvas_scale": canvas_scale,
		"final_scale": final_scale,
		"to_window": to_window,
		"player_px": PlayerCharacter.RADIUS * 2.0 * to_window.x,
		"world_visible": Vector2(vis.x / maxf(canvas_scale.x, 0.0001), vis.y / maxf(canvas_scale.y, 0.0001)),
	}
	_rows.append(row)
	print("[尺寸 %s] window=%s 可见视口=%s zoom=%.3f canvas倍率=%.4f final倍率=%.4f 世界→窗口=%.4f | 玩家像素高=%.1f | 可见世界=%.0f×%.0f" % [
		str(size), str(window.size), str(vis), row["zoom"].x, canvas_scale.x, final_scale.x,
		to_window.x, row["player_px"], row["world_visible"].x, row["world_visible"].y,
	])
	await _capture("/tmp/degenerateage_m59a_%s_%dx%d.png" % [_tag, window.size.x, window.size.y])

func _capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[DisplayProbe] 跳过截图（headless）")
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[DisplayProbe] 截图 → ", path)

func _report() -> void:
	if _rows.size() < 2:
		_failures.append("指标不足（需 2 个窗口尺寸）")
		return
	var a: Dictionary = _rows[0]
	var b: Dictionary = _rows[1]
	print("---------- 判定 ----------")
	print("窗口面积比        = %.4f×" % ((float(b["window"].x) * float(b["window"].y)) / maxf(float(a["window"].x) * float(a["window"].y), 1.0)))
	print("玩家像素高        = %.1f → %.1f（比 %.4f×，期望 1.0）" % [a["player_px"], b["player_px"], b["player_px"] / maxf(a["player_px"], 0.0001)])
	print("可见世界宽        = %.0f → %.0f（比 %.4f×，期望 ≈ 窗口宽度比）" % [a["world_visible"].x, b["world_visible"].x, b["world_visible"].x / maxf(a["world_visible"].x, 0.0001)])
	print("最终倍率 canvas×final 窗口比 = %.4f → %.4f" % [a["to_window"].x, b["to_window"].x])
