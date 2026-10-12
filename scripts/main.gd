extends Node2D
## 启动引导：校验数据配置。世界由子场景 Game 承载，HUD 由 UI/Hud 承载（M1 起）。

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

func _on_viewport_size_changed() -> void:
	SettingsRuntime._apply_ui_scale()
