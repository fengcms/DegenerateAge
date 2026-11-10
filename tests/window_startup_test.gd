extends Node
## 启动窗口工作区、会话幂等及显式偏好回归；实际窗口分支仅在 --rendered 下执行。
var failures: Array[String] = []

## 先验证负坐标与边框夹紧，再在真实窗口检验最大化、普通更新和自定义尺寸。
func _ready() -> void:
	if not DiagnosticProbeGuard.require_isolated(self):
		return
	var usable := Rect2i(-2560, 40, 2560, 1400)
	var fitted := DisplayEnvironment.fitted_rect(Vector2i(9999, 9999), usable, Vector2i(16, 64))
	check(fitted == Rect2i(-2560, 40, 2544, 1336), "超大请求夹紧且保留负屏幕坐标")
	check(DisplayEnvironment.fitted_rect(Vector2i(1280, 800), usable, Vector2i.ZERO) == Rect2i(-1920, 340, 1280, 800), "小窗口在当前工作区居中")
	check(DisplayEnvironment.has_parent_window(PackedStringArray(["--wid", "123"])) and DisplayEnvironment.has_parent_window(PackedStringArray(["--wid=123"])), "嵌入参数均被识别")
	check(not DisplayEnvironment.has_parent_window(PackedStringArray(["--editor"])), "独立编辑器游戏不误判嵌入")
	GameState.reset_to_defaults()
	SettingsRuntime.load_display_policy({})
	if not SettingsRuntime.is_headless():
		SettingsRuntime.initialize_startup_display()
		await get_tree().create_timer(0.5).timeout
		var window := get_window()
		var area := DisplayServer.screen_get_usable_rect(window.current_screen)
		var outer := Rect2i(DisplayServer.window_get_position_with_decorations(), DisplayServer.window_get_size_with_decorations())
		check(area.grow(2).encloses(outer), "最大窗口不遮挡工作区外菜单和 Dock")
		check(outer.size.x >= area.size.x - 2 and outer.size.y >= area.size.y - 2, "默认占满当前可用工作区")
		print("[WindowStartupTest] screen=", window.current_screen, " usable=", area, " client=", window.size, " outer=", outer)
		window.mode = Window.MODE_WINDOWED
		window.size = Vector2i(1100, 700)
		await get_tree().create_timer(0.4).timeout
		var current := window.size
		GameState.settings.musicVolume = 0.5
		SettingsRuntime.apply_all()
		SettingsRuntime.initialize_startup_display()
		await get_tree().process_frame
		check(window.mode == Window.MODE_WINDOWED and window.size == current, "改音量和重复启动入口均保留玩家本次窗口")
		check(SettingsRuntime.remember_current_window(), "明确记住当前窗口")
		check(SettingsRuntime.save_display_preferences(true), "自定义尺寸持久化成功")
		window.size = Vector2i(900, 600)
		SettingsRuntime.apply_window_preferences()
		await get_tree().create_timer(0.4).timeout
		check(window.size == current, "自定义偏好恢复保存尺寸")
		GameState.settings.fullscreen = true
		SettingsRuntime.mark_display_customized("fullscreen")
		SettingsRuntime.apply_window_preferences()
		await get_tree().create_timer(1.5).timeout
		check(window.mode == Window.MODE_FULLSCREEN, "显式全屏优先")
		GameState.settings.fullscreen = false
		SettingsRuntime.mark_display_customized("fullscreen")
		SettingsRuntime.apply_window_preferences()
		await get_tree().create_timer(1.5).timeout
		check(window.mode == Window.MODE_WINDOWED and window.size == current, "退出全屏恢复原自定义窗口偏好 mode=%d size=%s expected=%s policy=%s" % [window.mode, window.size, current, SettingsRuntime._display_policy.windowPolicy])
		GameState.settings.resolution = "1280x800"
		SettingsRuntime.mark_display_customized("resolution")
		SettingsRuntime.apply_window_preferences()
		await get_tree().create_timer(0.4).timeout
		check(window.size == Vector2i(1280, 800), "旧固定尺寸仍然优先")
	else:
		check(not DisplayEnvironment.can_control_window(get_window()), "无头跳过窗口操作")
	DirAccess.remove_absolute(SettingsRuntime.DISPLAY_PREFS_PATH)
	print("[WindowStartupTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

## 汇总断言，不因首个失败漏掉后续独立边界。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[WindowStartupTest] " + message)
