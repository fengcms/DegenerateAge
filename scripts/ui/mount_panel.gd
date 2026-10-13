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

func _on_panel_opened(panel_id: String) -> void:
	if panel_id not in [PANEL_ID, "inventory", "character", "skill"] and visible:
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
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.10, 0.98)
	style.border_color = Color(0.48, 0.37, 0.60)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	_center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.custom_minimum_size.x = 620
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	_title = Label.new()
	_title.text = "坐骑收藏"
	_title.add_theme_font_size_override("font_size", 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "关闭 · Esc"
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	_center.setup(self, panel, head, Vector2(0.52, 0.34))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)
	_list = VBoxContainer.new()
	_list.custom_minimum_size.x = 190
	body.add_child(_list)
	var preview := VBoxContainer.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.add_theme_constant_override("separation", 8)
	body.add_child(preview)
	_image = TextureRect.new()
	_image.custom_minimum_size = Vector2(240, 230)
	_image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.add_child(_image)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 18)
	preview.add_child(_name)
	_details = Label.new()
	_details.custom_minimum_size.y = 78
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_child(_details)
	_action = Button.new()
	_action.pressed.connect(_on_action)
	preview.add_child(_action)
	var hint := Label.new()
	hint.text = "N 打开 / 关闭 · 20 级可骑乘 · 坐骑掉落进入收藏"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.7, 0.72, 0.76)
	root.add_child(hint)

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
		button.text = "%s%s" % [String(template.get("name", mount_id)), " ✓" if owned else " · 未获得"]
		button.tooltip_text = "查看坐骑详情"
		button.pressed.connect(_select.bind(mount_id))
		_list.add_child(button)
	var selected = DataLoader.get_entry("mounts", _selected_mount)
	if not selected is Dictionary:
		_image.texture = null
		_name.text = "暂无坐骑"
		_details.text = "击败指定 Boss 后有机会获得坐骑。"
		_action.disabled = true
		_action.text = "不可骑乘"
		return
	var icon := String(selected.get("icon", ""))
	_image.texture = load(icon) as Texture2D if not icon.is_empty() and ResourceLoader.exists(icon) else null
	_name.text = String(selected.get("name", _selected_mount))
	var required := int(selected.get("levelReq", 20))
	var bonus := float(selected.get("speedBonus", 0.0)) * 100.0
	var boss = DataLoader.get_entry("monsters", String(selected.get("dropBossId", "")))
	var boss_name := String(boss.get("name", "指定 Boss")) if boss is Dictionary else "指定 Boss"
	var owned := GameState.owned_mounts.has(_selected_mount)
	_details.text = "移动速度 +%.0f%% · 需要 Lv%d\n来源：%s\n%s" % [bonus, required, boss_name,
		"已收藏" if owned else "尚未获得，击败 Boss 后有机会掉落"]
	_action.disabled = not owned or int(GameState.player.get("level", 1)) < required
	if not owned:
		_action.text = "尚未获得"
	elif int(GameState.player.get("level", 1)) < required:
		_action.text = "Lv%d 解锁骑乘" % required
	else:
		_action.text = "下骑" if GameState.active_mount == _selected_mount else "骑乘"

func _select(mount_id: String) -> void:
	_selected_mount = mount_id
	_refresh()

func _on_action() -> void:
	if GameState.active_mount == _selected_mount:
		GameState.dismount()
	else:
		var result := GameState.ride_mount(_selected_mount)
		if not result.get("ok", false):
			EventBus.toast_requested.emit(String(result.get("reason", "无法骑乘")), "danger")
	_refresh()
