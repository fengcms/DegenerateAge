extends Node
## 屏幕密度、来源优先级与三轴补偿回归，合成屏幕不冒充实际多显示器硬件验证。
var failures: Array[String] = []

## 覆盖 2K/4K 合成环境、重复缩放防护、旧系数组合和跨屏只更新自动轴。
func _ready() -> void:
	if not DiagnosticProbeGuard.require_isolated(self):
		return
	GameState.reset_to_defaults()
	SettingsRuntime.load_display_policy({})
	var snapshot := {"platform": "macOS", "hidpi": true, "contentMode": Window.CONTENT_SCALE_MODE_DISABLED,
		"contentFactor": 1.0, "size": Vector2i(2560, 1440), "scale": 1.0, "screen": 0}
	check(DisplayEnvironment.recommended_scale(snapshot) == 1.0, "2K与100%系统密度不额外放大")
	snapshot.size = Vector2i(3840, 2160)
	for density in [1.0, 1.5, 2.0]:
		snapshot.scale = density
		check(DisplayEnvironment.recommended_scale(snapshot) == density, "4K不覆盖系统密度：" + str(density))
	for density in [NAN, INF, 0, -1, 99]:
		snapshot.scale = density
		check(DisplayEnvironment.recommended_scale(snapshot) == 1.0, "无效密度安全回退")
	snapshot.scale = 2.0
	snapshot.platform = "Windows"
	check(DisplayEnvironment.recommended_scale(snapshot) == 1.0, "未校准后端保守回退")
	snapshot.platform = "macOS"
	snapshot.contentMode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	check(DisplayEnvironment.recommended_scale(snapshot) == 1.0, "已由内容缩放处理时不重复补偿")
	snapshot.contentMode = Window.CONTENT_SCALE_MODE_DISABLED
	SettingsRuntime._screen_snapshot = snapshot.duplicate(true)
	check(SettingsRuntime.ui_scale_value() == 2.0 and SettingsRuntime.map_scale_value() == 2.0 and SettingsRuntime.text_scale_value() == 2.0, "新偏好三轴自动200%")
	var ui := CanvasLayer.new()
	add_child(ui)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 20)
	ui.add_child(label)
	SettingsRuntime.apply_ui_scale_to(ui)
	SettingsRuntime.apply_text_scale_to(ui)
	check(ui.transform.get_scale() == Vector2(2, 2) and label.get_theme_font_size("font_size") == 20, "UI与文字200%最终字形为200%而非400%")
	GameState.settings.uiScale = 1.0
	SettingsRuntime.mark_display_customized("uiScale")
	GameState.settings.displayScale = 1.5
	GameState.settings.displayScaleMode = "manual"
	check(SettingsRuntime.ui_scale_value() == 1.0 and SettingsRuntime.text_scale_value() == 2.0, "手动100%优先，未变更轴仍自动，不叠全局系数")
	SettingsRuntime._screen_snapshot.scale = 1.5
	check(SettingsRuntime.ui_scale_value() == 1.0 and SettingsRuntime.map_scale_value() == 1.5, "跨屏只更新自动轴")
	var resized := snapshot.duplicate(true)
	resized.client = Vector2i(900, 600)
	snapshot.client = Vector2i(5120, 2756)
	check(DisplayEnvironment.screen_signature(resized) == DisplayEnvironment.screen_signature(snapshot), "同屏拖动窗口不改变适配签名")
	GameState.settings.uiScale = 2.0
	SettingsRuntime.mark_display_customized("displayScale")
	check(SettingsRuntime.ui_scale_value() == 3.0, "旧手动200%×150%仍保留300%")
	SettingsRuntime.restore_automatic_scale("textScale")
	check(SettingsRuntime.text_scale_value() == 1.5 and SettingsRuntime.ui_scale_value() == 3.0, "单轴恢复自动不受统一系数且不更改其他轴")
	check(SettingsRuntime.save_display_preferences(true), "保存偏好成功")
	var bytes := FileAccess.get_file_as_bytes(SettingsRuntime.DISPLAY_PREFS_PATH)
	SettingsRuntime._screen_snapshot.scale = 2.0
	SettingsRuntime.refresh_display_scales()
	check(FileAccess.get_file_as_bytes(SettingsRuntime.DISPLAY_PREFS_PATH) == bytes, "屏幕变化不会把推荐值写入磁盘")
	check(GameState.settings.textScale == 1.0, "自动推荐不会改写保留手动原值")
	for key in SettingsRuntime.SCALE_KEYS:
		GameState.settings[key] = NAN
		SettingsRuntime.mark_display_customized(key)
		check(is_finite(SettingsRuntime.effective_scale(key)), "三轴均拦截非有限值：" + key)
	DirAccess.remove_absolute(SettingsRuntime.DISPLAY_PREFS_PATH)
	ui.queue_free()
	print("[DisplayScalingTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

## 聚合失败并保留完整的独立场景覆盖。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[DisplayScalingTest] " + message)
