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
	if _failures.is_empty():
		print("[PanelChromeLayoutTest] 全部通过 ✅")
	else:
		for failure in _failures:
			push_error("[PanelChromeLayoutTest] 失败：" + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


## 汇总各项真实布局条件，失败时使隔离测试返回非零状态。
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
