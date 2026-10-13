extends Control
## 独立人物面板：装备槽和十二项战斗属性，数值统一读取 GameState。

var _slots: Dictionary = {}
var _stats: Label
var _title: Label
var _center: FloatingWindow

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.equipment_changed.connect(_refresh)
	EventBus.player_leveled.connect(func(_level: int) -> void: _refresh())
	EventBus.player_hp_changed.connect(func(_hp: int, _max: int) -> void: _refresh())
	EventBus.player_mp_changed.connect(func(_mp: int, _max: int) -> void: _refresh())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("panel_character") and not event.is_echo():
		set_open(not visible)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		if not _center.is_top_window():
			return
		set_open(false)
		get_viewport().set_input_as_handled()

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open("character", open)
	if open:
		_refresh()
		EventBus.panel_opened.emit("character")
		_center.show_window()

func _on_panel_opened(panel_id: String) -> void:
	if panel_id not in ["character", "inventory", "skill", "mount"] and visible:
		set_open(false)

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
	root.custom_minimum_size.x = 670
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 20)
	head.add_child(_title)
	var close := Button.new()
	close.text = "关闭 · Esc"
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	_center.setup(self, panel, head, Vector2(0.34, 0.18))
	root.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	root.add_child(body)
	var equip := VBoxContainer.new()
	equip.custom_minimum_size.x = 320
	body.add_child(equip)
	var avatar := Label.new()
	avatar.text = "◉  灵刃战士"
	avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar.add_theme_font_size_override("font_size", 17)
	equip.add_child(avatar)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	equip.add_child(grid)
	for def in Equipment.SLOT_DEFS:
		var sid := String(def.id)
		var button := Button.new()
		button.custom_minimum_size = Vector2(155, 36)
		button.clip_text = true
		button.pressed.connect(_unequip.bind(sid))
		grid.add_child(button)
		_slots[sid] = button
	var hint := Label.new()
	hint.text = "点击已穿戴装备可卸下；背包满时无法卸下"
	hint.add_theme_font_size_override("font_size", 12)
	equip.add_child(hint)
	body.add_child(VSeparator.new())
	_stats = Label.new()
	_stats.custom_minimum_size.x = 285
	_stats.add_theme_font_size_override("font_size", 15)
	body.add_child(_stats)

func _refresh() -> void:
	if _title == null:
		return
	_title.text = "%s · Lv%d" % [GameState.player.get("name", "守护者"), int(GameState.player.get("level", 1))]
	for def in Equipment.SLOT_DEFS:
		var sid := String(def.id)
		var button: Button = _slots[sid]
		var item: Variant = GameState.equipment.get(sid)
		button.text = "%s：%s" % [String(def.label), ItemUtil.display_name(item) if item is Dictionary else "空"]
		button.tooltip_text = _equipment_tooltip(item) if item is Dictionary else "空槽"
		button.icon = SampleArt.icon_for(item)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 32)
		button.disabled = not item is Dictionary
	var p := GameState.player
	var bonus := GameState.equip_bonus()
	_stats.text = "战斗属性\n\n生命  %d / %d\n法力  %d / %d\n攻击  %d\n防御  %d\n等级  %d\n移动速度  %.2f\n暴击率  %.1f%%\n暴击伤害  %.2f×\n攻击间隔  %.2f 秒\n闪避  %.1f%%\n格挡  %.1f%%\n冷却缩减  %.1f%%" % [
		int(p.hp), GameState.max_hp(), int(p.mp), GameState.max_mp(),
		GameState.total_attack(), GameState.total_defense(), int(p.level),
		float(p.movementSpeed) + float(bonus.get("movementSpeed", 0.0)),
		100.0 * (float(p.criticalChance) + float(bonus.get("criticalChance", 0.0))),
		float(p.criticalMultiplier) + float(bonus.get("criticalMultiplier", 0.0)),
		maxf(0.1, float(p.attackInterval) + float(bonus.get("attackInterval", 0.0))),
		100.0 * (float(p.dodge) + float(bonus.get("dodge", 0.0))),
		100.0 * (float(p.block) + float(bonus.get("block", 0.0))),
		100.0 * (float(p.cdr) + float(bonus.get("cdr", 0.0)))]

func _unequip(slot_id: String) -> void:
	var result := GameState.unequip_slot(slot_id)
	if not bool(result.get("ok", false)):
		EventBus.toast_requested.emit(String(result.get("reason", "卸下失败")), "danger")
	_refresh()

func _equipment_tooltip(item: Dictionary) -> String:
	var lines: Array[String] = [ItemUtil.display_name(item)]
	lines.append_array(ItemUtil.attr_lines(item))
	return "\n".join(PackedStringArray(lines))
