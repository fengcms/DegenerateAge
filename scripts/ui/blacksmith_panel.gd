extends Control
## 铁匠对话与功能菜单。NPC 的自我介绍来自地图配置，菜单打开升星、重铸及四种合成服务。

const PANEL_ID := "blacksmith"
const COL_PANEL := Color(0.06, 0.07, 0.09, 0.97)
const COL_BORDER := Color(0.36, 0.31, 0.26)

var _title: Label
var _greeting: Label
var _continue: Button
var _leave: Button
var _upgrade: Button
var _reforge: Button
var _fusion_buttons: Array[Button] = []
var _service_grids: Array[GridContainer] = []
var _greeting_card: Control
var _service_card: Control
var _center: FloatingWindow
var _root: VBoxContainer
var _footer: HBoxContainer
var _service_scroll: ScrollContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.blacksmith_panel_requested.connect(_on_requested)
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
	EventBus.settings_changed.connect(_resize)
	get_viewport().size_changed.connect(_resize)
	_resize.call_deferred()

## 根据逻辑视口限制菜单尺寸；100% 下说明整体放得下，只在窄窗口保留滚动兜底。
## 窗口自身的尺寸与落点由 FloatingWindow 按内容与可见区结算，不再强制撑满逻辑视口。
func _resize() -> void:
	if _root == null:
		return
	var logical := get_viewport_rect().size / SettingsRuntime.ui_scale_value()
	_root.custom_minimum_size = Vector2(minf(500.0, logical.x * 0.84), 0.0)
	_service_scroll.custom_minimum_size.y = clampf(logical.y - 250.0, 54.0, 380.0)

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("pause")):
		set_open(false)
		get_viewport().set_input_as_handled()

func _on_requested(npc_name: String, greeting: String) -> void:
	_title.text = PanelChrome.title_text(npc_name if not npc_name.is_empty() else Localization.tr_key("ui.blacksmith_panel.p002"))
	_greeting.text = "「%s」" % greeting
	set_open(true)

func _on_panel_opened(panel_id: String) -> void:
	if panel_id != PANEL_ID and visible:
		set_open(false)

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open(PANEL_ID, open)
	if open:
		_continue.visible = true
		_upgrade.visible = false
		_reforge.visible = false
		for button in _fusion_buttons:
			button.visible = false
		_greeting_card.visible = true
		_service_card.visible = false
		EventBus.panel_opened.emit(PANEL_ID)
		_center.show_window()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.36)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_center = FloatingWindow.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	var panel := PanelChrome.new()
	_center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	_root = VBoxContainer.new()
	var root := _root
	root.custom_minimum_size = Vector2(500, 0)
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	_title = Label.new()
	_title.text = Localization.tr_key("ui.blacksmith_panel.p002")
	_title.add_theme_font_size_override("font_size", 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	PanelChrome.style_title(_title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)
	# 与其余浮窗同构：标题行拖动、点击置前、越界夹紧（工程 74 §7）。
	_center.setup(self, panel, head, Vector2(0.5, 0.5))
	root.add_child(PanelChrome.make_title_gap())
	_greeting_card = PanelContainer.new()
	PanelChrome.style_card(_greeting_card as PanelContainer)
	_greeting_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_greeting_card)
	var greeting_row := HBoxContainer.new()
	greeting_row.add_theme_constant_override("separation", 18)
	_greeting_card.add_child(greeting_row)
	var portrait := TextureRect.new()
	var portrait_atlas := AtlasTexture.new()
	portrait_atlas.atlas = preload("res://assets/sprites/npcs/blacksmith/idle_atlas.png")
	portrait_atlas.region = Rect2(0, 0, 64, 80)
	portrait.texture = portrait_atlas
	portrait.custom_minimum_size = Vector2(118, 150)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	greeting_row.add_child(portrait)
	var speech := VBoxContainer.new()
	speech.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	greeting_row.add_child(speech)
	var speaker := Label.new()
	speaker.text = Localization.tr_key("ui.blacksmith_panel.p002")
	PanelChrome.style_section(speaker)
	speech.add_child(speaker)
	_greeting = Label.new()
	_greeting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_greeting.add_theme_color_override("font_color", PanelChrome.TEXT)
	speech.add_child(_greeting)
	_service_card = PanelContainer.new()
	PanelChrome.style_card(_service_card as PanelContainer)
	_service_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_service_card.visible = false
	root.add_child(_service_card)
	_service_scroll = ScrollContainer.new()
	_service_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_service_card.add_child(_service_scroll)
	var service_content := VBoxContainer.new()
	service_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	service_content.add_theme_constant_override("separation", 10)
	_service_scroll.add_child(service_content)
	var service_title := Label.new()
	service_title.text = Localization.tr_key("ui.blacksmith_panel.p007")
	PanelChrome.style_section(service_title)
	service_content.add_child(service_title)
	# 强化组：升星与重铸都改单件装备，放在一起并共用一句说明。
	var enhance_grid := _build_group(service_content, "ui.blacksmith_panel.group_enhance",
		"ui.blacksmith_panel.hint_enhance")
	_upgrade = _make_service(enhance_grid, "ui.blacksmith_panel.p004", true)
	_upgrade.pressed.connect(_open_upgrade)
	_reforge = _make_service(enhance_grid, "ui.reforge_panel.p002", true)
	_reforge.pressed.connect(_open_reforge)
	# 合成组：原有两种服务并排；升档随机合成独占下一行，避免两列留下孤格。
	var forge_grid := _build_group(service_content, "ui.blacksmith_panel.group_forge",
		"ui.blacksmith_panel.hint_forge")
	for service in [
		{"mode": EquipmentFusion.GOLD_TO_PURPLE, "key": "ui.fusion.gold_title"},
		{"mode": EquipmentFusion.PURPLE_TARGET, "key": "ui.fusion.purple_title"},
	]:
		var button := _make_service(forge_grid, String(service.key), false)
		button.pressed.connect(_open_fusion.bind(String(service.mode)))
		_fusion_buttons.append(button)
	var purple_up_row := VBoxContainer.new()
	forge_grid.get_parent().add_child(purple_up_row)
	var purple_up := _make_service(purple_up_row, "ui.fusion.purple_up_title", false)
	purple_up.pressed.connect(_open_fusion.bind(EquipmentFusion.PURPLE_UP_TIER))
	_fusion_buttons.append(purple_up)
	# 保星升级有跨档扣费规则，独占整行才放得下说明。
	var transfer_row := VBoxContainer.new()
	transfer_row.add_theme_constant_override("separation", 4)
	service_content.add_child(transfer_row)
	var transfer := _make_service(transfer_row, "ui.fusion.star_title", true)
	transfer.pressed.connect(_open_fusion.bind(EquipmentFusion.STAR_TRANSFER))
	_fusion_buttons.append(transfer)
	transfer_row.add_child(_make_hint("ui.blacksmith_panel.hint_transfer"))
	# 离开与继续固定在底部操作行，不再混进服务网格。
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 8)
	root.add_child(_footer)
	_leave = _make_footer_action("ui.blacksmith_panel.p008", false)
	_leave.pressed.connect(func() -> void: set_open(false))
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(footer_spacer)
	_continue = _make_footer_action("ui.blacksmith_panel.p003", true)
	_continue.pressed.connect(_show_menu)

## 服务分组：小标题 + 一句话说明 + 两列按钮，替代原来挤在滚动区里的三段长文。
func _build_group(parent: VBoxContainer, title_key: String, hint_key: String) -> GridContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 4)
	parent.add_child(group)
	var title := Label.new()
	title.text = Localization.tr_key(title_key)
	PanelChrome.style_section(title)
	group.add_child(title)
	group.add_child(_make_hint(hint_key))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	group.add_child(grid)
	_service_grids.append(grid)
	return grid

## 12px 灰字一句话说明；允许折行，避免窄面板被长句撑宽。
func _make_hint(key: String) -> Label:
	var hint := Label.new()
	hint.text = Localization.tr_key(key)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", PanelChrome.MUTED)
	return hint

## 服务按钮填满所在列，保证同一横排宽度一致。
func _make_service(parent: Control, key: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = Localization.tr_key(key)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	PanelChrome.style_action(button, primary)
	return button

## 底部固定行按钮：等宽，避免贴两端显得单薄。
func _make_footer_action(key: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = Localization.tr_key(key)
	button.custom_minimum_size.x = 140.0
	_footer.add_child(button)
	PanelChrome.style_action(button, primary)
	return button

func _show_menu() -> void:
	_continue.visible = false
	_upgrade.visible = true
	_reforge.visible = true
	for button in _fusion_buttons:
		button.visible = true
	_greeting_card.visible = false
	_service_card.visible = true
	_upgrade.grab_focus()

func _open_upgrade() -> void:
	set_open(false)
	EventBus.upgrade_panel_requested.emit()

## M10-8：铁匠服务菜单第二项。与升星同构 —— 先关铁匠再开重铸面板。
func _open_reforge() -> void:
	set_open(false)
	EventBus.reforge_panel_requested.emit()

## 铁匠菜单进入对应合成服务；对话窗口先关闭，避免层叠遮挡。
func _open_fusion(mode: String) -> void:
	set_open(false)
	EventBus.equipment_fusion_panel_requested.emit(mode)
