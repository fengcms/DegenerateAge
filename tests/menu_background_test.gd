extends Node
## 主菜单背景的资源、会话随机、面板流转及缩放回归，使用隔离运行器保护真实存档。
## 窗口模式可通过 DA_MENU_CAPTURE_DIR 指定临时截图目录，验证正式 Main 场景而非重绘模拟图。

const BACKGROUND := preload("res://scripts/ui/main_menu_background.gd")
var _failures: Array[String] = []
var _arrival_count := 0

## 先隔离验证随机源，再装配正式主场景检验三图、尺寸、子面板与暂停状态。
func _ready() -> void:
	GameState.reset_to_defaults()
	SaveManager.active_slot = -1
	SaveManager.autosave_enabled = false
	GameState.menu_mode = "menu"
	EventBus.toast_requested.connect(_track_arrival)
	if get_tree().has_meta(BACKGROUND.SESSION_KEY):
		get_tree().remove_meta(BACKGROUND.SESSION_KEY)
	seed(71110)
	var expected_random := randi()
	seed(71110)
	var probe := BACKGROUND.new()
	add_child(probe)
	_check(randi() == expected_random, "背景抽签不消费玩法全局随机序列")
	var selected: String = probe.session_background_path()
	_check(BACKGROUND.BACKGROUND_PATHS.has(selected), "首次抽签只能选择已登记素材")
	_check(probe._picture.texture != null, "首次菜单加载选中纹理")
	probe.set_active(false)
	_check(probe._picture.texture == null and not probe.visible, "退出菜单释放纹理引用并隐藏")
	probe.queue_free()
	await get_tree().process_frame
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await _settle()
	var background = main.get_node("UI/MainMenuBackground")
	var menu = main.get_node("UI/MenuPanel")
	_check(background.session_background_path() == selected, "背景节点重建后仍沿用本次启动选择")
	_check(background.visible and menu.visible, "正式主菜单显示插画")
	_check(_arrival_count == 0, "主菜单不显示世界抵达提示")
	_check(background.get_index() > main.get_node("UI/Hud").get_index(), "插画覆盖世界 HUD")
	_check(background.get_index() < main.get_node("UI/SavePanel").get_index(), "存档面板位于插画上层")
	# 尺寸矩阵明确模拟玩家选择普通窗口，覆盖自动启动最大化后的用户操作。
	get_window().mode = Window.MODE_WINDOWED
	for path in BACKGROUND.BACKGROUND_PATHS:
		get_tree().set_meta(BACKGROUND.SESSION_KEY, path)
		background.set_active(false)
		background.set_active(true)
		var texture: Texture2D = background._picture.texture
		_check(texture != null and texture.get_size() == Vector2(1402, 1122), "三张运行纹理均可导入：" + path)
		for window_size in [Vector2i(1280, 800), Vector2i(1600, 900), Vector2i(1024, 768)]:
			get_window().size = window_size
			await _settle()
			_check_full_background(background)
			_check(background._picture.texture == texture, "调整窗口不重抽或重建纹理")
			await _capture("%s-%dx%d" % [path.get_file().get_basename(), window_size.x, window_size.y])
	get_tree().set_meta(BACKGROUND.SESSION_KEY, selected)
	background.set_active(false)
	background.set_active(true)
	var session_texture: Texture2D = background._picture.texture
	get_window().size = Vector2i(1280, 800)
	SettingsRuntime.mark_display_customized("uiScale")
	for ui_scale in [0.8, 1.0, 1.5, 2.0]:
		GameState.settings["uiScale"] = ui_scale
		SettingsRuntime.apply_ui_scale_to(main.get_node("UI"))
		await _settle()
		_check_full_background(background)
	GameState.settings["uiScale"] = 1.0
	SettingsRuntime.apply_ui_scale_to(main.get_node("UI"))
	menu._open_settings()
	await _settle()
	_check(not menu.visible and background.is_visible_in_tree(), "设置页面保留主菜单背景")
	_check(background._picture.texture == session_texture, "打开设置不换图")
	await _capture("settings")
	main.get_node("UI/SettingsPanel").set_open(false)
	await _settle()
	_check(menu.visible and background._picture.texture == session_texture, "设置返回保持同张背景")
	for mode in ["new", "load"]:
		menu._open_slots(mode)
		await _settle()
		_check(not menu.visible and background.is_visible_in_tree(), "存档页面保留背景：" + mode)
		_check(background._picture.texture == session_texture, "存档页面不换图：" + mode)
		await _capture("slots-" + mode)
		main.get_node("UI/SavePanel").set_open(false)
		await _settle()
		_check(menu.visible, "存档页面返回主菜单：" + mode)
	# 直接切换模式模拟暂停，真实新建/继续/读档重载另由 MenuFlowTest 覆盖。
	session_texture = null
	GameState.menu_mode = "world"
	menu.open_pause()
	main.get_node("Game")._notify_arrival()
	_check(_arrival_count == 1, "进入世界仍显示正常抵达提示")
	_check(not background.visible and background._picture.texture == null, "暂停不显示插画且无纹理引用")
	_check(is_equal_approx(menu._dim.color.a, 0.84), "暂停保持原有世界遮罩强度")
	await _capture("pause")
	menu.resume_game()
	_check(not background.visible and not get_tree().paused, "恢复游戏不残留背景或暂停")
	menu.open_main()
	_check(background._picture.texture.resource_path == selected, "返回主菜单重新加载本次启动原图")
	_check(is_equal_approx(menu._dim.color.a, 0.16), "主菜单使用轻遮罩")
	var toasts: VBoxContainer = main.get_node("UI/Hud")._toast_box
	var toast_count := toasts.get_child_count()
	EventBus.toast_requested.emit("回归检查：读档失败仍可见", "danger")
	_check(toasts.is_visible_in_tree() and toasts.get_child_count() == toast_count + 1, "主菜单仍显示必要错误提示")
	get_tree().paused = false
	print("[MenuBackgroundTest] ", "全部通过 ✅" if _failures.is_empty() else str(_failures))
	get_tree().quit(0 if _failures.is_empty() else 1)

## 验证背景按 UI CanvasLayer 变换后精确覆盖视口，且子纹理遵循铺满和不接管输入的契约。
func _check_full_background(background: Control) -> void:
	var rect := background.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, background.size)
	var viewport_rect := get_viewport().get_visible_rect()
	_check(rect.position.is_equal_approx(viewport_rect.position) and rect.size.is_equal_approx(viewport_rect.size), "不同窗口/UI 比例均覆盖视口")
	_check(background._picture.size.is_equal_approx(background.size), "图片铺满背景控件")
	_check(background._picture.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED, "纹理等比裁切、不拉伸")
	_check(background._picture.mouse_filter == Control.MOUSE_FILTER_IGNORE, "图片子层不抢按钮输入")

## 等待正式场景的延迟初始化和窗口布局合并完成。
func _settle() -> void:
	for _frame in range(4):
		await get_tree().process_frame

## 仅在显式指定截图目录且存在真实渲染时保存当前视口，不产生仓库截图或玩家存档。
func _capture(label: String) -> void:
	var directory := OS.get_environment("DA_MENU_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	_check(picture != null and not picture.is_empty(), "窗口实际发生渲染")
	if picture != null:
		_check(picture.save_png(directory.path_join(label + ".png")) == OK, "保存实机截图：" + label)

## 聚合失败并输出明确错误，由运行器检查完成标记与退出状态。
func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
		push_error("[MenuBackgroundTest] " + message)

## 只统计本地图的抵达事件，验证菜单抑制和世界正常提示两条分支。
func _track_arrival(message: String, _kind: String) -> void:
	if message == Localization.tr_key("msg.game.p007") % MapService.display_name(GameState.current_map):
		_arrival_count += 1
