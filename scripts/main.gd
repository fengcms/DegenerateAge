extends Node2D
## 启动引导：校验数据配置。世界由子场景 Game 承载，HUD 由 UI/Hud 承载（M1 起）。

## M5-9c：同帧合并窗口尺寸变化（见 `_on_viewport_size_changed`）。
var _resize_queued := false

func _ready() -> void:
	# 工程 116：闪退取证。崩溃是引擎 C++ 层 SIGSEGV，GDScript 不报错，
	# 只能靠「崩溃前最后一条埋点」定位，见 `scripts/systems/crash_trace.gd`。
	CrashTrace.mark("main.ready.begin", "mode=" + GameState.menu_mode)
	# M5-9a：渲染策略先于一切显示相关计算落地（窗口放大 = 看到更多，元素像素尺寸不变）。
	SettingsRuntime.apply_display_strategy()
	_apply_settings_after_scene_ready.call_deferred()
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
## 工程 115：`reload_current_scene()` 期间 `current_scene` 可能仍指向正在释放的旧场景，
## 此时 `UI.get_viewport()` 的可见尺寸是非法值（inf / nan）。原先直接 `apply_all` 会把
## 非法尺寸铺满整棵 UI 树、最终在绘制层算出 NaN 而导致引擎 C++ 层闪退（审阅报告 §5）。
## 处置：延后一帧等新场景完全接管，再由 `apply_ui_scale_to` 的有限性守卫兜底 —— 即便
## 一帧后仍非法也只会「本次不重排」，绝不再把 inf/nan 写进控件尺寸。
func _apply_settings_after_scene_ready() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	SettingsRuntime.apply_all()
	CrashTrace.mark("main.settings.applied")
func _on_viewport_size_changed() -> void:
	if _resize_queued:
		return
	_resize_queued = true
	_reapply_for_viewport.call_deferred()

func _reapply_for_viewport() -> void:
	_resize_queued = false
	SettingsRuntime.reapply_for_viewport()
