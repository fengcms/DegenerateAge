extends Control
## 主菜单与暂停菜单，通过 GameState、SaveManager 和 MapService 协调进入/退出游戏。
## 菜单打开时暂停世界；UI CanvasLayer 持续处理输入。主菜单插画由同级 MainMenuBackground 管理。

const MAIN := "main"
const PAUSE := "pause"

var _mode := ""
var _root: VBoxContainer
var _title: Label
var _continue: Button
var _dim: ColorRect

## 构建菜单并监听面板互斥事件，初始显隐由启动初始化决定。
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(_on_panels_close_requested)

## 只初始化当前主场景，按菜单/世界模式恢复暂停状态。
func initialize_if_current() -> void:
	if get_tree().current_scene != get_parent().get_parent():
		return
	if GameState.menu_mode == "world":
		get_tree().paused = false
		return
	GameState.menu_mode = "menu"
	SaveManager.active_slot = -1
	open_main()

## 处理世界内的暂停快捷键，遵循现有面板输入互斥规则。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or event.is_echo() or GameState.menu_mode != "world":
		return
	if visible and _mode == PAUSE:
		resume_game()
		get_viewport().set_input_as_handled()
	elif not GameState.panel_open:
		open_pause()
		get_viewport().set_input_as_handled()

## 从设置或存档返回时恢复原菜单，不重新抽取背景。
func _process(_delta: float) -> void:
	# 从设置或存档面板返回时恢复原菜单；子面板之间仍按既有互斥规则运作。
	if not visible and not GameState.panel_open and _mode != "":
		if _mode == MAIN and GameState.menu_mode == "menu":
			_show(MAIN)
		elif _mode == PAUSE and GameState.menu_mode == "world":
			_show(PAUSE)

## 进入主菜单模式并显示入口按钮。
func open_main() -> void:
	GameState.menu_mode = "menu"
	_show(MAIN)

## 只允许在世界模式中打开暂停菜单。
func open_pause() -> void:
	if GameState.menu_mode != "world":
		return
	_show(PAUSE)

## 收起暂停菜单并恢复世界模拟，确保插画不会覆盖游戏。
func resume_game() -> void:
	_set_main_background(false)
	visible = false
	_mode = ""
	GameState.set_panel_open("menu", false)
	get_tree().paused = false

## 显示指定菜单及对应遮罩，主菜单使用插画、暂停菜单保留世界画面。
func _show(mode: String) -> void:
	_mode = mode
	_set_main_background(mode == MAIN)
	_dim.color.a = 0.16 if mode == MAIN else 0.84
	get_tree().paused = true
	visible = true
	GameState.set_panel_open("menu", true)
	for child in _root.get_children():
		child.queue_free()
	_title.text = PanelChrome.title_text(Localization.tr_key("ui.menu_panel.p001") if mode == MAIN else Localization.tr_key("ui.menu_panel.p002"))
	if mode == MAIN:
		_continue = _button(Localization.tr_key("ui.menu_panel.p003"), _continue_game)
		_continue.disabled = SaveManager.continue_slot() < 0
		_button(Localization.tr_key("ui.menu_panel.p004"), _open_new_slots)
		_button(Localization.tr_key("ui.menu_panel.p005"), _open_load_slots)
		_button(Localization.tr_key("ui.menu_panel.p006"), _open_settings)
		_button(Localization.tr_key("ui.menu_panel.p007"), _quit_game)
	else:
		_button(Localization.tr_key("ui.menu_panel.p003"), resume_game)
		_button(Localization.tr_key("ui.menu_panel.p006"), _open_settings)
		_button(Localization.tr_key("ui.menu_panel.p008"), _open_manage_slots)
		_button(Localization.tr_key("ui.menu_panel.p009"), _return_to_main)
	EventBus.panel_opened.emit("menu")

## 其他面板打开时隐藏菜单按钮，主菜单背景保留在同级下层。
func _on_panel_opened(panel_id: String) -> void:
	if panel_id != "menu" and visible:
		visible = false
		GameState.set_panel_open("menu", false)

## F-P3-2：统一关闭事件。仅收起菜单并清空流程态；暂停状态由发起方（读档 / 重载）自行管理。
func _on_panels_close_requested() -> void:
	if not visible:
		return
	visible = false
	_mode = ""
	GameState.set_panel_open("menu", false)

## 创建沿用统一面板样式的菜单按钮并绑定入口动作。
func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 44)
	button.pressed.connect(action)
	_root.add_child(button)
	PanelChrome.style_action(button)
	return button

## 创建遮罩和居中按钮面板，背景图片由同级节点承担。
func _build() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.03, 0.05, 0.84)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelChrome.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	var head := HBoxContainer.new()
	content.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	PanelChrome.style_title(_title)
	content.add_child(PanelChrome.make_title_gap())
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 9)
	content.add_child(_root)

## 读取最近活动存档，失败时保留菜单并提示原因。
func _continue_game() -> void:
	if not SaveManager.resume_last():
		_continue.disabled = true
		EventBus.toast_requested.emit(Localization.tr_key("ui.menu_panel.p010"), "danger")
		return
	_start_world()

## 打开新游戏存档槽选择。
func _open_new_slots() -> void:
	_open_slots("new")

## 打开只读的存档加载界面。
func _open_load_slots() -> void:
	_open_slots("load")

## 在暂停状态打开存档管理界面。
func _open_manage_slots() -> void:
	_open_slots("manage")

## 复用存档面板并传入新建、读取或管理模式。
func _open_slots(mode: String) -> void:
	var panel := get_node("../SavePanel")
	panel.set_mode(mode)
	panel.set_open(true)

## 打开设置面板，返回时由既有菜单恢复流程接管。
func _open_settings() -> void:
	get_node("../SettingsPanel").set_open(true)

## 从主菜单进入世界，释放背景纹理并重新加载场景。
func _start_world() -> void:
	_set_main_background(false)
	GameState.menu_mode = "world"
	get_tree().paused = false
	MapService.reload_world()

## 保存当前进度并返回主菜单，本次启动的背景选择不随重载改变。
func _return_to_main() -> void:
	SaveManager.save_on_quit()
	SaveManager.active_slot = -1  # 保留 last_slot，供主菜单「继续」使用。
	GameState.reset_to_defaults()
	GameState.menu_mode = "menu"
	get_tree().paused = false
	MapService.reload_world()

## 退出程序，由既有退出流程处理资源清理。
func _quit_game() -> void:
	get_tree().quit()


## 通知同级背景切换显示；兼容只实例化菜单的测试与预览场景。
func _set_main_background(active: bool) -> void:
	var background := get_node_or_null("../MainMenuBackground")
	if background != null:
		background.set_active(active)
