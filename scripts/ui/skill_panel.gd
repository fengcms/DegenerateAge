extends Control
## 技能图鉴。仅已接通且达到等级的技能可拖入快捷栏；未接线技能保留资料展示。

var _center: FloatingWindow

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
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

## 并开集合统一由 `GameState.panels_coexist`（F-P3-1）判定，本面板不再自带名单。
func _on_panel_opened(panel_id: String) -> void:
	if visible and not GameState.panels_coexist(panel_id, "skill"):
		set_open(false)

var _list: VBoxContainer

func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.42)
	dim.visible = false
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
	var title := Label.new()
	title.text = Localization.tr_key("ui.skill_panel.p001")
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	PanelChrome.style_title(title)
	var help := PanelHelpButton.new()
	help.tooltip_text = Localization.tr_key("ui.skill_panel.p003")
	head.add_child(help)
	PanelChrome.style_help(help)
	var close := Button.new()
	close.text = Localization.tr_key("ui.skill_panel.p002")
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)
	_center.setup(self, panel, head, Vector2(0.02, 0.18))
	root.add_child(PanelChrome.make_title_gap())

	# F-P2-3：标题行留在外框渐变带内，技能列表整体可滚动。
	var content_scroll := ScrollContainer.new()
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content_scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 540
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(content)
	_center.set_content_scroll(content_scroll)

	var section := Label.new()
	section.text = "可用技能"
	PanelChrome.style_section(section)
	content.add_child(section)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	content.add_child(_list)

## 每项技能沿用同一张低对比内容卡，保留原拖动按钮作为交互源。
func _new_skill_row() -> HBoxContainer:
	var row := PanelSkillRow.new()
	_list.add_child(row)
	return row

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
		var wired := HotbarConfig.ACTIVE_SKILLS.has(String(skill.get("id", "")))
		var row := _new_skill_row()
		var icon := SkillDragButton.new()
		icon.custom_minimum_size = Vector2(52, 52)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.text = String(skill.get("name", Localization.tr_key("ui.skill_panel.p001"))).substr(0, 2)
		icon.skill_id = String(skill.get("id", ""))
		icon.drag_label = String(skill.get("name", ""))
		SampleArt.decorate(icon, SampleArt.skill_icon(icon.skill_id))
		icon.add_theme_constant_override("icon_max_width", 42)
		icon.disabled = not unlocked or not wired
		icon.tooltip_text = Localization.tr_key("ui.skill_panel.p004") if not icon.disabled else Localization.tr_key("ui.skill_panel.p005")
		row.add_child(icon)
		var desc := Label.new()
		desc.text = "%s　Lv%d · %s\n%s" % [String(skill.get("name", "")), int(skill.get("unlockLevel", 1)),
			Localization.tr_key("ui.skill.available") if unlocked and wired else (Localization.tr_key("ui.skill.locked") if not unlocked else Localization.tr_key("ui.skill.unwired")),
			String(skill.get("desc", ""))]
		desc.custom_minimum_size.x = 380
		desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		desc.add_theme_color_override("font_color", PanelChrome.TEXT)
		row.add_child(desc)
	for kind in ["red", "blue"]:
		var row := _new_skill_row()
		var button := SkillDragButton.new()
		button.custom_minimum_size = Vector2(52, 52)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.text = Localization.tr_key("ui.skill_panel.p006") if kind == "red" else Localization.tr_key("ui.skill_panel.p007")
		button.binding = {"kind": "auto_potion", "id": kind}
		SampleArt.decorate(button, SampleArt.binding_icon(button.binding))
		button.add_theme_constant_override("icon_max_width", 42)
		button.tooltip_text = Localization.tr_key("ui.skill_panel.p008")
		row.add_child(button)
		var desc := Label.new()
		desc.text = Localization.tr_key("ui.skill_panel.p009") % (Localization.tr_key("ui.skill_panel.p010") if kind == "red" else Localization.tr_key("ui.skill_panel.p011"))
		desc.custom_minimum_size.x = 380
		desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		desc.add_theme_color_override("font_color", PanelChrome.TEXT)
		row.add_child(desc)
