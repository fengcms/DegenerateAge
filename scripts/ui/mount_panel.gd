extends Control
## 坐骑收藏：预览、20 级门槛与骑乘切换。收藏不占背包格。

const PANEL_ID := "mount"

var _title: Label
var _list: VBoxContainer
var _image: TextureRect
var _name: Label
var _details: Label
var _action: Button
var _selected_mount := ""
var _center: FloatingWindow

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.mount_panel_requested.connect(func() -> void: set_open(true))
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
	EventBus.mount_changed.connect(_refresh)
	EventBus.player_leveled.connect(func(_level: int) -> void: _refresh())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("panel_mount") and not event.is_echo():
		set_open(not visible)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		if not _center.is_top_window():
			return
		set_open(false)
		get_viewport().set_input_as_handled()

## 并开集合统一由 `GameState.panels_coexist`（F-P3-1）判定，本面板不再自带名单。
func _on_panel_opened(panel_id: String) -> void:
	if visible and not GameState.panels_coexist(panel_id, PANEL_ID):
		set_open(false)

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open(PANEL_ID, open)
	if open:
		if not GameState.active_mount.is_empty():
			_selected_mount = GameState.active_mount
		_refresh()
		EventBus.panel_opened.emit(PANEL_ID)
		_center.show_window()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.42)
	dim.visible = false
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
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	_title = Label.new()
	_title.text = "坐骑"
	_title.add_theme_font_size_override("font_size", 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	PanelChrome.style_title(_title)
	var help := PanelHelpButton.new()
	help.tooltip_text = Localization.tr_key("ui.mount_panel.p003")
	head.add_child(help)
	PanelChrome.style_help(help)
	var close := Button.new()
	close.text = Localization.tr_key("ui.mount_panel.p002")
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)
	_center.setup(self, panel, head, Vector2(0.98, 0.18))
	root.add_child(PanelChrome.make_title_gap())

	# F-P2-3：标题行留在外框渐变带内，收藏列表与预览整体可滚动。
	var content_scroll := ScrollContainer.new()
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content_scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 560
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(content)
	_center.set_content_scroll(content_scroll)

	var section := Label.new()
	section.text = Localization.tr_key("ui.mount_panel.p001")
	PanelChrome.style_section(section)
	content.add_child(section)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	content.add_child(body)
	var list_card := PanelContainer.new()
	PanelChrome.style_card(list_card)
	body.add_child(list_card)
	_list = VBoxContainer.new()
	_list.custom_minimum_size.x = 170
	_list.add_theme_constant_override("separation", 6)
	list_card.add_child(_list)
	var preview_card := PanelContainer.new()
	PanelChrome.style_card(preview_card)
	preview_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(preview_card)
	var preview := VBoxContainer.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.add_theme_constant_override("separation", 8)
	preview_card.add_child(preview)
	_image = TextureRect.new()
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_image.custom_minimum_size = Vector2(210, 200)
	_image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.add_child(_image)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 18)
	_name.add_theme_color_override("font_color", PanelChrome.TEXT)
	preview.add_child(_name)
	preview.move_child(_name, 0)
	_details = Label.new()
	_details.custom_minimum_size.y = 78
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_child(_details)
	_action = Button.new()
	_action.pressed.connect(_on_action)
	preview.add_child(_action)
	PanelChrome.style_action(_action, true)

func _refresh() -> void:
	if not visible:
		return
	var templates = DataLoader.get_table("mounts")
	if not templates is Array:
		return
	if _selected_mount.is_empty() and not templates.is_empty():
		_selected_mount = String(templates[0].get("id", ""))
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for template in templates:
		if not template is Dictionary:
			continue
		var mount_id := String(template.get("id", ""))
		var button := Button.new()
		var owned := GameState.owned_mounts.has(mount_id)
		button.text = "%s%s" % [String(template.get("name", mount_id)), " ✓" if owned else Localization.tr_key("ui.mount_panel.p004")]
		button.tooltip_text = Localization.tr_key("ui.mount_panel.p005")
		button.pressed.connect(_select.bind(mount_id))
		_list.add_child(button)
		PanelChrome.style_action(button, mount_id == _selected_mount)
	var selected = DataLoader.get_entry("mounts", _selected_mount)
	if not selected is Dictionary:
		_image.texture = null
		_name.text = Localization.tr_key("ui.mount_panel.p006")
		_details.text = Localization.tr_key("ui.mount_panel.p007")
		_action.disabled = true
		_action.text = Localization.tr_key("ui.mount_panel.p008")
		return
	var icon := String(selected.get("icon", ""))
	_image.texture = load(icon) as Texture2D if not icon.is_empty() and ResourceLoader.exists(icon) else null
	_name.text = String(selected.get("name", _selected_mount))
	var required := int(selected.get("levelReq", 20))
	var bonus := float(selected.get("speedBonus", 0.0)) * 100.0
	var boss = DataLoader.get_entry("monsters", String(selected.get("dropBossId", "")))
	var boss_name := String(boss.get("name", Localization.tr_key("ui.mount.designated_boss"))) if boss is Dictionary else Localization.tr_key("ui.mount.designated_boss")
	var owned := GameState.owned_mounts.has(_selected_mount)
	_details.text = Localization.tr_key("ui.mount_panel.p009") % [bonus, required, boss_name,
		Localization.tr_key("ui.mount.collected") if owned else Localization.tr_key("ui.mount.not_collected")]
	_action.disabled = not owned or int(GameState.player.get("level", 1)) < required
	if not owned:
		_action.text = Localization.tr_key("ui.mount_panel.p010")
	elif int(GameState.player.get("level", 1)) < required:
		_action.text = Localization.tr_key("ui.mount_panel.p011") % required
	else:
		_action.text = Localization.tr_key("ui.mount_panel.p012") if GameState.active_mount == _selected_mount else Localization.tr_key("ui.mount_panel.p013")

func _select(mount_id: String) -> void:
	_selected_mount = mount_id
	_refresh()

func _on_action() -> void:
	if GameState.active_mount == _selected_mount:
		GameState.dismount()
	else:
		var result := GameState.ride_mount(_selected_mount)
		if not result.get("ok", false):
			EventBus.toast_requested.emit(String(result.get("reason", Localization.tr_key("ui.mount_panel.p014"))), "danger")
	_refresh()
