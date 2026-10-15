extends Node
## 统一面板标题按钮的真实容器布局回归：标题变高或字体变化时，按钮仍须保持正圆。

var _failures: Array[String] = []


## 在与正式面板相同的 HBox 标题行中验证最终尺寸，而非只检查最小尺寸设置。
func _ready() -> void:
	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(420, 64)
	add_child(head)
	var title := Label.new()
	title.text = "人物标题"
	title.add_theme_font_size_override("font_size", 42)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var help := PanelHelpButton.new()
	head.add_child(help)
	PanelChrome.style_help(help)
	var close := Button.new()
	head.add_child(close)
	PanelChrome.style_close(close)
	await get_tree().process_frame
	_check(is_equal_approx(help.size.x, help.size.y), "帮助按钮在高标题行里保持圆形")
	_check(is_equal_approx(close.size.x, close.size.y), "关闭按钮在高标题行里保持圆形")
	_check(help.get_theme_stylebox("normal") is StyleBoxTexture, "帮助按钮加载运行素材")
	_check(close.get_theme_stylebox("normal") is StyleBoxTexture, "关闭按钮加载运行素材")
	# 模拟设置面板增大文字倍率：圆钮符号已烘入纹理，轮廓不应被字体撑高。
	help.add_theme_font_size_override("font_size", 48)
	close.add_theme_font_size_override("font_size", 48)
	await get_tree().process_frame
	_check(is_equal_approx(help.size.x, help.size.y), "文字放大后帮助按钮仍为圆形")
	_check(is_equal_approx(close.size.x, close.size.y), "文字放大后关闭按钮仍为圆形")
	await _check_real_headers()
	if _failures.is_empty():
		print("[PanelChromeLayoutTest] 全部通过 ✅")
	else:
		for failure in _failures:
			push_error("[PanelChromeLayoutTest] 失败：" + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


## 逐个实例化四个常驻浮窗，检查标题行与分隔线的实际相对位置。
func _check_real_headers() -> void:
	var layer := Control.new()
	layer.size = Vector2(1280, 800)
	add_child(layer)
	for path in ["res://scenes/ui/InventoryPanel.tscn", "res://scenes/ui/CharacterPanel.tscn",
			"res://scenes/ui/SkillPanel.tscn", "res://scenes/ui/MountPanel.tscn"]:
		var panel: Control = load(path).instantiate()
		layer.add_child(panel)
		panel.set_open(true)
		await get_tree().process_frame
		var window: FloatingWindow = panel.get("_center")
		var header_top := window.header.global_position.y - window.panel_box.global_position.y
		var header_bottom := header_top + window.header.size.y
		_check(is_equal_approx(header_top, PanelChrome.FRAME_CONTENT_INSET + PanelChrome.HEADER_MARGIN_TOP),
			"%s 标题行使用统一上边距" % panel.name)
		_check(header_bottom <= PanelChrome.HEADER_BAND_BOTTOM + 0.1,
			"%s 标题行位于渐变带内且不压分隔线" % panel.name)
		var help_button: Button = window.header.get_child(window.header.get_child_count() - 2)
		var close_button: Button = window.header.get_child(window.header.get_child_count() - 1)
		_check(is_equal_approx(help_button.position.y, close_button.position.y)
			and is_equal_approx(help_button.size.y, close_button.size.y),
			"%s 帮助与关闭圆钮上下对齐" % panel.name)
		panel.queue_free()
		await get_tree().process_frame


## 汇总各项真实布局条件，失败时使隔离测试返回非零状态。
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
