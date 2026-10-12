extends Node2D
## 启动引导：校验数据配置。世界由子场景 Game 承载，HUD 由 UI/Hud 承载（M1 起）。

## M5-9c：同帧合并窗口尺寸变化（见 `_on_viewport_size_changed`）。
var _resize_queued := false

func _ready() -> void:
	# M5-9a：渲染策略先于一切显示相关计算落地（窗口放大 = 看到更多，元素像素尺寸不变）。
	SettingsRuntime.apply_display_strategy()
	SettingsRuntime.apply_all.call_deferred()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	$UI/MenuPanel.initialize_if_current.call_deferred()
	print("========================================")
	print("[Main] 《末法纪元：最后的守护者》启动")

	var report: Array[String] = DataLoader.validate_all()
	if report.is_empty():
		print("[Main] 配置校验通过 ✅")
	else:
		push_warning("[Main] 配置校验存在问题（%d 项）:\n%s" % [report.size(), "\n".join(PackedStringArray(report))])

	print("========================================")

## M5-9c（09-A §4）：disabled 策略下「逻辑视口尺寸 = 窗口逻辑尺寸」，拖窗口会**每帧**改变视口，
## 于是本回调从"几乎不触发"变为"高频触发"；重排 UI 根控件会牵连 15 个面板的布局失效。
## 处置：同一帧内的多次触发只重算一次（call_deferred 合并），不做时间去抖 ——
## 时间去抖会让拖动过程中面板尺寸滞后于窗口，属可见的劣化。
func _on_viewport_size_changed() -> void:
	if _resize_queued:
		return
	_resize_queued = true
	_reapply_for_viewport.call_deferred()

func _reapply_for_viewport() -> void:
	_resize_queued = false
	SettingsRuntime.reapply_for_viewport()
