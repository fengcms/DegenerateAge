extends Control
## 技能图鉴。战斗系统当前只接通普攻，因此其余技能展示解锁要求但不提供无效拖放。

var _center: FloatingWindow

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.player_leveled.connect(func(_level: int) -> void: _refresh())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("panel_skill") and not event.is_echo():
		set_open(not visible)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		if not _center.is_top_window():
			return
		set_open(false)
		get_viewport().set_input_as_handled()

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open("skill", open)
	var hud := get_node_or_null("../Hud")
	if hud != null:
		hud.set_hotbar_drop_mode(open)
	if open:
		_refresh()
		EventBus.panel_opened.emit("skill")
		_center.show_window()

func _on_panel_opened(panel_id: String) -> void:
	if panel_id not in ["skill", "inventory", "character", "mount"] and visible:
		set_open(false)

var _list: VBoxContainer

func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.42)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_center = FloatingWindow.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("11171d")
	style.border_color = Color("74818a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	_center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.custom_minimum_size.x = 600
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "技能"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "关闭 · Esc"
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	_center.setup(self, panel, head, Vector2(0.42, 0.26))
	root.add_child(HSeparator.new())
	_list = VBoxContainer.new()
	root.add_child(_list)
	var hint := Label.new()
	hint.text = "已接通的技能可拖到下方快捷栏；其余技能待战斗系统接线"
	hint.add_theme_font_size_override("font_size", 12)
	root.add_child(hint)

func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var skills: Variant = DataLoader.get_table("skills")
	if not skills is Array:
		return
	for raw in skills:
		if not raw is Dictionary:
			continue
		var skill: Dictionary = raw
		var unlocked := int(GameState.player.level) >= int(skill.get("unlockLevel", 1))
		var wired := String(skill.get("id", "")) == "basic_slash"
		var row := HBoxContainer.new()
		_list.add_child(row)
		var icon := SkillDragButton.new()
		icon.custom_minimum_size = Vector2(72, 48)
		icon.text = String(skill.get("name", "技能")).substr(0, 2)
		icon.skill_id = String(skill.get("id", ""))
		icon.disabled = not unlocked or not wired
		icon.tooltip_text = "拖动到快捷栏" if not icon.disabled else "暂不可配置"
		row.add_child(icon)
		var desc := Label.new()
		desc.text = "%s　Lv%d · %s\n%s" % [String(skill.get("name", "")), int(skill.get("unlockLevel", 1)),
			"可用" if unlocked and wired else ("未解锁" if not unlocked else "战斗接线待完成"),
			String(skill.get("desc", ""))]
		desc.custom_minimum_size.x = 500
		row.add_child(desc)
