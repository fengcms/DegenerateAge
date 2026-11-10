extends Node
## 实际窗口显示验收：正式 Main、菜单点击、设置、背包及百首禁域18席拥挤战斗。
## 对照固定窗口与最大化的整帧采样，不代表长期自动战斗或其他操作系统性能。
## 采样暂停自动渲染并逐帧 force_draw(false)，覆盖绘制提交成本，不宣称原生交换链 FPS。
var failures: Array[String] = []
var main: Node
var rendered := 0

## 创建隔离角色与正式主场景，验证自动布局后进行同场景窗口对照。
func _ready() -> void:
	if not DiagnosticProbeGuard.require_isolated(self):
		return
	if SettingsRuntime.is_headless():
		push_error("DisplayAcceptanceTest 必须通过 --rendered 执行")
		get_tree().quit(1)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.frame_post_draw.connect(_drawn)
	GameState.reset_to_defaults()
	SettingsRuntime.load_display_policy({})
	SaveManager.active_slot = -1
	SaveManager.autosave_enabled = false
	GameState.menu_mode = "menu"
	GameState.current_map = "c7_boss_field"
	GameState.player.level = 1234
	GameState.player.hpFlat = 10000000
	GameState.player.hp = GameState.max_hp()
	GameState.save_pos = Iso.grid_to_world(Vector2i(80, 60))
	GameState.has_save_pos = true
	await get_tree().process_frame
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	# 在菜单开始异步布局前保护测试角色，避免入场的真实Boss提前杀死夹具。
	var guarded_player := main.get_node("Game/Entities/Player") as PlayerCharacter
	guarded_player._invuln = 100000.0
	await settle()
	var max_size := get_window().size
	var background = main.get_node("UI/MainMenuBackground")
	var chosen: String = background.session_background_path()
	var expected := DisplayEnvironment.recommended_scale(SettingsRuntime._screen_snapshot)
	check(SettingsRuntime.ui_scale_value() == expected, "正式Main启用屏幕推荐")
	await capture("menu-auto")
	var menu = main.get_node("UI/MenuPanel")
	menu._open_settings()
	var settings = main.get_node("UI/SettingsPanel")
	var tabs := find_tabs(settings)
	tabs.current_tab = 1
	await settle()
	for label in settings._scale_status.values():
		check(label.text.contains(str(roundi(expected * 100))), "设置页显示当前实际推荐百分比")
	await capture("settings-auto")
	var close := find_button(settings, Localization.tr_key("ui.settings_panel.p007"))
	check(close != null, "设置关闭按钮存在")
	if close != null:
		await click_button(close)
		check(not settings.visible and menu.visible, "高密度缩放后实际鼠标点击仍落在关闭按钮")
	check(background.session_background_path() == chosen, "屏幕适配和菜单流转不重新抽背景")
	GameState.menu_mode = "world"
	menu.resume_game()
	await settle()
	var inventory = main.get_node("UI/InventoryPanel")
	inventory.set_open(true)
	await settle()
	await capture("inventory-auto")
	inventory.set_open(false)
	var world := main.get_node("Game")
	var player := world.get_node("Entities/Player") as PlayerCharacter
	player.set_physics_process(false)
	player.get_node("AutoPilot").set_physics_process(false)
	player._invuln = 100000.0
	var ground := world.get_node("Ground") as IsoGround
	var spawner := world.get_node("Spawner") as MonsterSpawner
	spawner.set_process(false)
	for point in spawner._points:
		if is_instance_valid(point.get("entry")):
			point.entry.queue_free()
		point.entry = null
	await get_tree().process_frame
	spawner.setup(ground, null)
	for point in spawner._points:
		spawner._spawn(point)
	var bosses := get_tree().get_nodes_in_group("enemies")
	check(bosses.size() == 18, "正式刷新预算保持18席")
	for index in bosses.size():
		var boss := bosses[index] as Monster
		boss.global_position = ground.clamp_to_map(player.global_position + Vector2.from_angle(index * 2.399963) * (110 + index % 5 * 28))
		boss.spawn_position = boss.global_position
		boss.level = 1234 + index
		boss._enter(Monster.State.CHASE)
		boss._announce_boss_hp()
	await settle()
	await capture("bosses-auto")
	var bar = main.get_node("UI/BossHealthBar")
	check(bar.bar_count() == 3, "最大化完整HUD保留三Boss独立状态栏")
	for row in bar._rows.values():
		check(row._level.text.length() == 4 and row._level.size.x >= row._level.get_minimum_size().x, "四位等级完整显示")
	# 同一批18只Boss对照：固定窗口100%、最大化推荐值，不以缩减敌人数掩盖成本。
	# 由采样循环逐帧绘制，避免 macOS 遮挡停绘及自动/强制绘制叠加。
	RenderingServer.render_loop_enabled = false
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 800)
	for axis in SettingsRuntime.SCALE_KEYS:
		GameState.settings[axis] = 1.0
		SettingsRuntime.mark_display_customized(axis)
	SettingsRuntime.refresh_display_scales()
	await sample(3.0, false)
	await sample(6.0, true, "1280x800-manual100")
	SettingsRuntime.restore_automatic_scale()
	SettingsRuntime.apply_window_preferences()
	SettingsRuntime.refresh_display_scales()
	await sample(4.0, false)
	check(get_window().size == max_size, "恢复自动窗口回到工作区最大尺寸")
	for batch in range(3):
		await sample(6.0, true, "max-auto-%d" % batch)
	check(not player.is_dead and not get_tree().paused, "性能采样期间角色存活且世界持续模拟")
	check(bosses.size() == get_tree().get_nodes_in_group("enemies").size(), "采样前后敌人数一致")
	await capture("bosses-auto-final")
	GameState.settings.uiScale = 1.5
	SettingsRuntime.mark_display_customized("uiScale")
	SettingsRuntime.refresh_display_scales()
	check(SettingsRuntime.ui_scale_value() == 1.5 and SettingsRuntime.text_scale_value() == expected, "手动UI150%与自动文字独立")
	await capture("bosses-ui150-text-auto")
	get_tree().paused = false
	RenderingServer.render_loop_enabled = true
	print("[DisplayAcceptanceTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

## 记录真实渲染帧，采样必须确认窗口确实提交绘制。
func _drawn() -> void:
	rendered += 1

## 等待窗口管理器和多层延迟布局完成，避免把装配中间态当成验收结果。
func settle() -> void:
	await get_tree().create_timer(0.6).timeout

## 递归找到正式页签容器，不依赖自动生成的节点名称。
func find_tabs(node: Node) -> TabContainer:
	if node is TabContainer:
		return node
	for child in node.get_children():
		var found := find_tabs(child)
		if found != null:
			return found
	return null

## 根据可见按钮文字查找真实交互目标。
func find_button(node: Node, caption: String) -> Button:
	if node is Button and (node.text == caption or node.tooltip_text == caption) and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := find_button(child, caption)
		if found != null:
			return found
	return null

## 通过视口像素坐标注入真实鼠标按下/释放，检验 CanvasLayer 缩放后的命中位置。
func click_button(button: Button) -> void:
	var position := button.get_global_transform_with_canvas() * (button.size * 0.5)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await settle()

## 可选截图仅写调用者指定临时目录，未设置路径时仍等待实际绘制。
func capture(label: String) -> void:
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var directory := OS.get_environment("DA_DISPLAY_CAPTURE_DIR")
	if not directory.is_empty():
		check(get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "截图写入：" + label)

## 现实秒整帧间隔采样；输出尾部时间、绘制调用和内存，保留节点数量用于检查短时趋势。
func sample(seconds: float, collect: bool, label: String = "") -> void:
	var values: Array[float] = []
	var deadline := Time.get_ticks_usec() + int(seconds * 1000000)
	var last := Time.get_ticks_usec()
	var initial_rendered := rendered
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
		RenderingServer.force_draw(false, get_process_delta_time())
		var now := Time.get_ticks_usec()
		values.append((now - last) / 1000.0)
		last = now
	if not collect:
		return
	check(rendered - initial_rendered == values.size(), "每个性能采样帧恰好实际绘制一次")
	values.sort()
	print("[PERF] display ", JSON.stringify({"case": label, "size": str(get_window().size), "ui": SettingsRuntime.ui_scale_value(),
		"frames": values.size(), "rendered": rendered - initial_rendered, "p50_ms": values[int(values.size() * 0.5)],
		"p95_ms": values[int(values.size() * 0.95)], "p99_ms": values[int(values.size() * 0.99)],
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"texture_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"nodes": get_tree().get_node_count()}))

## 汇总失败并以退出码交给隔离运行器。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[DisplayAcceptanceTest] " + message)
