extends Node2D
## 启动引导：校验数据配置。世界由子场景 Game 承载，HUD 由 UI/Hud 承载（M1 起）。

## M5-9c：同帧合并窗口尺寸变化（见 `_on_viewport_size_changed`）。
var _resize_queued := false

## 初始化显示策略、主菜单及配置反馈，并挂载诊断心跳。
func _ready() -> void:
	# 工程 116：闪退取证。崩溃是引擎 C++ 层 SIGSEGV，GDScript 不报错，
	# 只能靠「崩溃前最后一条埋点」定位，见 `scripts/systems/crash_trace.gd`。
	CrashTrace.mark("main.ready.begin", "mode=" + GameState.menu_mode)
	# M5-9a：渲染策略先于一切显示相关计算落地（窗口放大 = 看到更多，元素像素尺寸不变）。
	SettingsRuntime.apply_display_strategy()
	SettingsRuntime.initialize_startup_display()
	_apply_settings_after_scene_ready.call_deferred()
	var display_watch := Timer.new()
	display_watch.wait_time = 0.75
	display_watch.process_mode = Node.PROCESS_MODE_ALWAYS
	display_watch.timeout.connect(_check_display_environment)
	add_child(display_watch)
	display_watch.start()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	$UI/MenuPanel.initialize_if_current.call_deferred()
	print("========================================")
	print("[Main] 《末法纪元：最后的守护者》启动")

	var report: Array[String] = DataLoader.validate_all()
	if report.is_empty():
		print("[Main] 配置校验通过 ✅")
	else:
		push_warning("[Main] 配置校验存在问题（%d 项）:\n%s" % [report.size(), "\n".join(PackedStringArray(report))])
		$UI/FlowFeedback.show_config_errors(report)

	print("========================================")
	CrashTrace.mark("main.ready.end", "report=" + str(report.size()))
	# 🔴 必须延后一帧：`_ready` 期间 root 正在装配子节点，直接 add_child 会报
	# 「Parent node is busy setting up children」。心跳节点挂在 root 下，
	# 切场景重载不会把它带走，所以只需挂一次。
	CrashTrace.attach_heartbeat.call_deferred(get_tree())

## M5-9c（09-A §4）：disabled 策略下「逻辑视口尺寸 = 窗口逻辑尺寸」，拖窗口会**每帧**改变视口，
## 于是本回调从"几乎不触发"变为"高频触发"；重排 UI 根控件会牵连 15 个面板的布局失效。
## 处置：同一帧内的多次触发只重算一次（call_deferred 合并），不做时间去抖 ——
## 时间去抖会让拖动过程中面板尺寸滞后于窗口，属可见的劣化。
## 场景装配完成后再应用设置，有限性守卫作为独立边界防御。
## 原NaN根因假设已被第三轮布局自激取证替代，不能据此断言重载必然产生NaN。
func _apply_settings_after_scene_ready() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	SettingsRuntime.apply_all()
	CrashTrace.mark("main.settings.applied")
## 合并同轮视口变化，避免重复重排整棵界面。
func _on_viewport_size_changed() -> void:
	if _resize_queued:
		return
	_resize_queued = true
	_reapply_for_viewport.call_deferred()

## 清除排队标记并按当前视口重新应用显示策略。
func _reapply_for_viewport() -> void:
	_resize_queued = false
	SettingsRuntime.reapply_for_viewport()

## 暂停菜单下也低频检测跨屏/DPI/工作区变化；不因窗口拖动重新计算人物大小。
func _check_display_environment() -> void:
	if SettingsRuntime.refresh_screen_environment():
		SettingsRuntime.refresh_display_scales()
		$UI/SettingsPanel.refresh_display_status()
