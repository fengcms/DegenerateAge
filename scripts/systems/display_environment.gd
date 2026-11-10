class_name DisplayEnvironment
extends RefCounted
## 桌面窗口环境适配：只在启动或玩家明确选择窗口模式时调整窗口。
## 使用当前显示器工作区及实际装饰尺寸，不负责偏好存储、UI 倍率或游戏世界规则。

static var _startup_applied := false
static var _request_serial := 0

## 嵌入宿主拥有窗口尺寸；无头和 --wid 启动不向操作系统发窗口指令。
static func can_control_window(window: Window) -> bool:
	if DisplayServer.get_name() == "headless" or window.is_embedded():
		return false
	return not has_parent_window(OS.get_cmdline_args())

## 纯解析编辑器嵌入参数，兼容分离和等号两种命令行写法。
static func has_parent_window(args: PackedStringArray) -> bool:
	for arg in args:
		if arg == "--wid" or arg.begins_with("--wid="):
			return true
	return false

## 一个进程只应用一次启动偏好；主菜单和角色切换不会重新最大化。
static func initialize(window: Window, policy: Dictionary, resolution: String) -> void:
	if _startup_applied:
		return
	_startup_applied = true
	apply_window(window, policy, resolution)

## 将客户区尺寸限制到工作区，装饰以同一显示坐标的像素计；支持左侧负坐标显示器。
static func fitted_rect(requested: Vector2i, usable: Rect2i, decoration: Vector2i) -> Rect2i:
	var available := (usable.size - decoration.max(Vector2i.ZERO)).max(Vector2i.ONE)
	var size := requested.clamp(Vector2i.ONE, available)
	return Rect2i(usable.position + (available - size) / 2, size)

## 应用明确的窗口请求；最大化后延迟校验，避免窗口管理器尚未完成异步调整。
static func apply_window(window: Window, policy: Dictionary, resolution: String) -> void:
	if not can_control_window(window):
		return
	_request_serial += 1
	var serial := _request_serial
	var mode: String = policy.get("windowPolicy", "auto_maximized")
	if mode == "fullscreen":
		window.mode = Window.MODE_FULLSCREEN
		return
	if mode == "auto_maximized":
		window.mode = Window.MODE_MAXIMIZED
		await window.get_tree().create_timer(0.25).timeout
		if serial != _request_serial or not is_instance_valid(window):
			return
		if window.mode not in [Window.MODE_MAXIMIZED, Window.MODE_WINDOWED]:
			return
		var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
		var outer := Rect2i(DisplayServer.window_get_position_with_decorations(), DisplayServer.window_get_size_with_decorations())
		if usable.has_area() and (not usable.grow(2).encloses(outer) or window.mode != Window.MODE_MAXIMIZED):
			_fit_window(window, usable.size, usable)
		return
	var requested: Vector2i = policy.get("customWindowSize", Vector2i(1280, 800))
	if mode != "custom":
		var parts := resolution.split("x")
		requested = Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(1280, 800)
	window.mode = Window.MODE_WINDOWED
	_fit_window(window, requested, DisplayServer.screen_get_usable_rect(window.current_screen))

## 按当前原生装饰差值居中客户区，避免标题栏或边框越过任务栏和 Dock。
static func _fit_window(window: Window, requested: Vector2i, usable: Rect2i) -> void:
	if not usable.has_area():
		return
	window.mode = Window.MODE_WINDOWED
	var decoration := DisplayServer.window_get_size_with_decorations() - window.size
	var inset := window.position - DisplayServer.window_get_position_with_decorations()
	var fitted := fitted_rect(requested, usable, decoration)
	window.size = fitted.size
	window.position = fitted.position + inset
