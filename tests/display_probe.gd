extends Node
## M5-9a~c 显示适配实测（开发期工具，M5 打包前随其他工具清理）。依据：工程文档 17 §4 / §5 U1。
##
## 目的：证明渲染策略切换后「窗口放大 = 看到更多地图，元素像素尺寸不变」，
##       实测 U1（Retina 下 get_visible_rect() 的单位），
##       并验证 M5-9c 的「显示适配」是三轴各乘一次、且各轴倍率与之相乘。
##
## 运行（**必须开窗**：需要真实渲染与窗口尺寸变化）：
##   GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##   "$GODOT" --path . res://tests/DisplayProbe.tscn -- --tag=after
##   "$GODOT" --path . res://tests/DisplayProbe.tscn -- --tag=before --legacy   # 复现旧策略做对照
##   "$GODOT" --path . res://tests/DisplayProbe.tscn -- --tag=m59c --display-scale=1.25   # 显示适配（手动）
##   参数：--tag=名称（输出文件名后缀，默认 after）｜--legacy（推回 canvas_items 复现旧行为）
##         --map-scale=X（M5-9b 地图倍率模式）｜--display-scale=X（M5-9c 显示适配手动模式，可配
##         --ui-scale=Y / --text-scale=Z 观察三轴相乘）
##
## 策略由主场景 `main.gd` → `SettingsRuntime.apply_display_strategy()` 在运行时应用
## （见该函数注释：为何不写进 project.godot）。
##
## 输出：
##   /tmp/degenerateage_m59a_<tag>_<W>x<H>.png   （各窗口尺寸截图）
##   /tmp/degenerateage_m59b_map<X>_<W>x<H>.png  （地图倍率截图）
##   /tmp/degenerateage_m59c_ds<X>_<W>x<H>.png   （显示适配截图）
##   stdout 指标表：窗口尺寸 / 可见视口 / 世界→窗口总倍率 / 玩家像素高 / 可见世界宽高 / 三轴倍率

const MAIN_SCENE := "res://scenes/Main.tscn"
const MAP_ID := "wild_trial"
const SIZES: Array[Vector2i] = [Vector2i(1280, 800), Vector2i(1920, 1200)]

var _failures: Array[String] = []
var _rows: Array[Dictionary] = []
var _tag := "after"
var _legacy := false
var _map_scale := 0.0      # >0 = M5-9b 地图倍率模式（固定窗口，只变相机 zoom）
var _display_scale := 0.0  # >0 = M5-9c 显示适配模式（固定窗口，手动系数 × 三轴倍率）
var _ui_scale := 1.0
var _text_scale := 1.0
var _resize_check := false # M5-9c：窗口尺寸变化 → 去抖重算（真窗口，不手动调 apply）

var _main: Node = null
var _player: PlayerCharacter = null
var _cam: Camera2D = null

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--tag="):
			_tag = String(arg).split("=", true, 1)[1]
		elif String(arg) == "--legacy":
			_legacy = true
		elif String(arg).begins_with("--map-scale="):
			_map_scale = float(String(arg).split("=", true, 1)[1])
		elif String(arg).begins_with("--display-scale="):
			_display_scale = float(String(arg).split("=", true, 1)[1])
		elif String(arg).begins_with("--ui-scale="):
			_ui_scale = float(String(arg).split("=", true, 1)[1])
		elif String(arg).begins_with("--text-scale="):
			_text_scale = float(String(arg).split("=", true, 1)[1])
		elif String(arg) == "--resize-check":
			_resize_check = true
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

	# ⚠ M5-9c：挂到 SceneTree **根**下而不是探针节点下 —— `set_current_scene` 要求新当前场景
	# 是根的直接子节点；否则引擎报 `p_scene->get_parent() != root` 且**赋值被拒**，
	# `_measure_resize_reapply` 里切 current_scene 会静默失败（SettingsRuntime 找不到 "UI"）。
	# 又：本函数经 `_ready` 的 await 链同步执行，此刻根「busy setting up children」，
	# 直接 add_child 会失败 ⇒ 必须 call_deferred（下面的等待帧足以让它入树并 _ready）。
	_main = load(MAIN_SCENE).instantiate()
	get_tree().root.add_child.call_deferred(_main)
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

	if _map_scale > 0.0:
		await _measure_map_scale()
	elif _display_scale > 0.0:
		await _measure_display_scale()
	elif _resize_check:
		await _measure_resize_reapply()
	else:
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

## M5-9b：固定窗口 1280×800，只变地图倍率 —— 验证「地图显示大小」= 相机 zoom 的端到端效果。
func _measure_map_scale() -> void:
	var window := get_window()
	window.size = Vector2i(1280, 800)
	for _i in range(15):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	GameState.settings["mapScale"] = _map_scale
	SettingsRuntime.apply_map_scale_to(_cam)
	_cam.reset_smoothing()
	for _i in range(5):
		await get_tree().process_frame
	var vp := get_viewport()
	var canvas_scale := vp.get_canvas_transform().get_scale()
	var to_window := canvas_scale * vp.get_final_transform().get_scale()
	var vis := vp.get_visible_rect().size
	var world_visible := Vector2(vis.x / maxf(canvas_scale.x, 0.0001), vis.y / maxf(canvas_scale.y, 0.0001))
	print("[地图倍率 %.2f] 相机 zoom=%s ｜ 可见世界=%.0f×%.0f ｜ 玩家像素高=%.1f" % [
		_map_scale, str(_cam.zoom), world_visible.x, world_visible.y, PlayerCharacter.RADIUS * 2.0 * to_window.x,
	])
	await _capture("/tmp/degenerateage_m59b_map%s_%dx%d.png" % [str(_map_scale).replace(".", "p"), window.size.x, window.size.y])

## M5-9c：固定窗口 1280×800，手动显示适配系数 × 三轴各自倍率。
## 验证「三轴各乘一次、且与各轴自身倍率相乘」——注意探针里 Main 不是 current_scene，
## 故三轴都得用 *_to(...) 直传节点（与 M5-9b 同因）。
func _measure_display_scale() -> void:
	var window := get_window()
	window.size = Vector2i(1280, 800)
	for _i in range(15):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var ui: CanvasLayer = _main.get_node_or_null("UI") as CanvasLayer
	var hud: Control = _main.get_node_or_null("UI/Hud") as Control
	if ui == null:
		_failures.append("显示适配模式未能取到 UI CanvasLayer")
		return
	GameState.settings["displayScaleMode"] = "manual"
	GameState.settings["displayScale"] = _display_scale
	GameState.settings["uiScale"] = _ui_scale
	GameState.settings["textScale"] = _text_scale
	GameState.settings["mapScale"] = 1.0
	SettingsRuntime.apply_ui_scale_to(ui)
	SettingsRuntime.apply_text_scale_to(ui)
	SettingsRuntime.apply_map_scale_to(_cam)
	_cam.reset_smoothing()
	for _i in range(8):
		await get_tree().process_frame
	var factor := SettingsRuntime.display_scale_factor()
	var label := _first_scaled_label(hud)
	var font_now := int(label.get_theme_font_size("font_size")) if label != null else -1
	var font_base := int(label.get_meta("base_font_size", 0)) if label != null else 0
	print("[显示适配 %.2f｜界面 %.2f｜文字 %.2f] 系数=%.4f ｜ 界面轴 transform=%.4f（期望 %.4f）｜ 地图轴 zoom=%s（期望 %.4f）｜ 文字轴 %d/%d（期望 %.4f）｜ HUD 根尺寸=%s ｜ 可见视口=%s" % [
		_display_scale, _ui_scale, _text_scale, factor,
		ui.transform.x.x, _ui_scale * factor,
		str(_cam.zoom), 1.0 * factor,
		font_now, font_base, _text_scale * factor,
		str(hud.size) if hud != null else "-", str(get_viewport().get_visible_rect().size),
	])
	await _capture("/tmp/degenerateage_m59c_%s_%dx%d.png" % [_tag, window.size.x, window.size.y])

## HUD 内第一个带 base_font_size 元数据的 Label（即 `_text_scale_node` 认定的缩放对象）。
func _first_scaled_label(node: Node) -> Label:
	if node == null:
		return null
	if node is Label and node.has_meta("base_font_size"):
		return node as Label
	for child in node.get_children():
		var found := _first_scaled_label(child)
		if found != null:
			return found
	return null

## M5-9c：真窗口下验证「窗口尺寸变化 → 去抖重算」自己跑起来了（**故意不手动调用 apply_***）。
## 关键：HUD 根控件被 `apply_ui_scale_to` 设为 TOP_LEFT 锚点 + 显式 size = 视口/倍率，
## 所以它**不会**靠锚点自动跟随窗口 —— 只有 size_changed 回调真的执行了，size 才会更新。
func _measure_resize_reapply() -> void:
	var ui: CanvasLayer = _main.get_node_or_null("UI") as CanvasLayer
	var hud: Control = _main.get_node_or_null("UI/Hud") as Control
	if ui == null or hud == null:
		_failures.append("重算检查未能取到 UI / Hud 节点")
		return
	# 让 Main 成为 current_scene，使 SettingsRuntime 的节点路径解析与真实游戏一致；
	# 否则 `_apply_ui_scale()` 找不到 "UI" 会直接返回，本检查就变成空转。
	get_tree().current_scene = _main
	GameState.settings["uiScale"] = 1.5
	GameState.settings["displayScaleMode"] = "auto"
	SettingsRuntime.apply_all()
	for _i in range(5):
		await get_tree().process_frame
	print("[重算] 初始：可见视口=%s HUD 根尺寸=%s（uiScale=1.5）" % [
		str(get_viewport().get_visible_rect().size), str(hud.size),
	])
	for size in SIZES:
		var before := hud.size
		get_window().size = size
		for _i in range(20):
			await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		var vis := get_viewport().get_visible_rect().size
		var expected := vis / 1.5
		var ok := hud.size.is_equal_approx(expected)
		print("[重算 %s] HUD 根尺寸 %s → %s ｜ 可见视口=%s ｜ 期望=%s ⇒ %s" % [
			str(size), str(before), str(hud.size), str(vis), str(expected), "✅" if ok else "❌",
		])
		if not ok:
			_failures.append("窗口 %s 下 UI 未随 size_changed 重算：期望 %s 实际 %s" % [str(size), str(expected), str(hud.size)])
		await _capture("/tmp/degenerateage_m59c_resize_%dx%d.png" % [size.x, size.y])
	GameState.settings["uiScale"] = 1.0

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
