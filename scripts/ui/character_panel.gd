extends Control
## 独立人物面板：装备槽和十二项战斗属性，数值统一读取 GameState。

var _slots: Dictionary = {}
var _stats: Label
var _title: Label
var _center: FloatingWindow
var _last_slot_id := ""
var _last_slot_click_ms := 0

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
	_last_slot_id = ""
	if open:
		_refresh()
		EventBus.panel_opened.emit("character")
		_center.show_window()
	var bag := get_node_or_null("../InventoryPanel")
	if bag != null and bag.visible:
		bag._refresh()

func _on_panel_opened(panel_id: String) -> void:
	if panel_id == "inventory" and visible:
		_refresh()
	if panel_id not in ["character", "inventory", "skill", "mount"] and visible:
		set_open(false)

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
	close.text = Localization.tr_key("ui.character_panel.p001")
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	_center.setup(self, panel, head, Vector2(0.34, 0.18))
	root.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	root.add_child(body)
	var equip := VBoxContainer.new()
	equip.custom_minimum_size.x = 350
	body.add_child(equip)
	var figure := HBoxContainer.new()
	figure.add_theme_constant_override("separation", 8)
	equip.add_child(figure)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	left.add_theme_constant_override("separation", 5)
	right.add_theme_constant_override("separation", 5)
	figure.add_child(left)
	var portrait_frame := PanelContainer.new()
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = Color("1a2530")
	portrait_style.border_color = Color("63828f")
	portrait_style.set_border_width_all(1)
	portrait_style.set_corner_radius_all(6)
	portrait_frame.add_theme_stylebox_override("panel", portrait_style)
	portrait_frame.custom_minimum_size = Vector2(172, 410)
	figure.add_child(portrait_frame)
	var portrait := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = preload("res://assets/sprites/player/guardian/guardian_atlas.png")
	atlas.region = Rect2(0, 0, 64, 80)
	portrait.texture = atlas
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait_frame.add_child(portrait)
	figure.add_child(right)
	var left_ids := ["helmet", "necklace", "armor", "bracer_1", "bracelet_1", "ring_1", "knee_1"]
	var right_ids := ["weapon", "shield", "shoes", "bracer_2", "bracelet_2", "ring_2", "knee_2"]
	for side in [left, right]:
		for sid in (left_ids if side == left else right_ids):
			var def := Equipment.slot_def(sid)
			var button := EquipmentSlot.new()
			button.role = ItemSlot.ROLE_EQUIP
			button.slot_id = sid
			button.slot_kind = String(def.get("kind", ""))
			button.custom_minimum_size = Vector2(52, 52)
			button.tooltip_text = String(def.get("label", sid))
			button.pressed.connect(_on_slot_pressed.bind(sid))
			button.item_dropped.connect(_on_equipment_dropped.bind(sid))
			side.add_child(button)
			_slots[sid] = button
	var hint := Label.new()
	hint.text = Localization.tr_key("ui.character_panel.p002")
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
	_title.text = "%s · Lv%d" % [GameState.player.get("name", Localization.tr_key("ui.character_panel.p003")), int(GameState.player.get("level", 1))]
	for def in Equipment.SLOT_DEFS:
		var sid := String(def.id)
		var button: EquipmentSlot = _slots[sid]
		var item: Variant = GameState.equipment.get(sid)
		button.item = item if item is Dictionary else {}
		button.draggable = item is Dictionary and _bag_visible()
		button.text = ItemUtil.template_name(item).substr(0, 2) if item is Dictionary else ""
		button.tooltip_text = "%s\n%s" % [String(def.label), _equipment_tooltip(item)] if item is Dictionary else Localization.tr_key("ui.character_panel.p004") % String(def.label)
		SampleArt.decorate(button, SampleArt.icon_for(item))
		button.queue_redraw()
	var p := GameState.player
	var bonus := GameState.equip_bonus()
	_stats.text = Localization.tr_key("ui.character_panel.p005") % [
		int(p.hp), GameState.max_hp(), int(p.mp), GameState.max_mp(),
		GameState.total_attack(), GameState.total_defense(), int(p.level),
		float(p.movementSpeed) + float(bonus.get("movementSpeed", 0.0)),
		100.0 * (float(p.criticalChance) + float(bonus.get("criticalChance", 0.0))),
		float(p.criticalMultiplier) + float(bonus.get("criticalMultiplier", 0.0)),
		maxf(0.1, float(p.attackInterval) + float(bonus.get("attackInterval", 0.0))),
		100.0 * (float(p.dodge) + float(bonus.get("dodge", 0.0))),
		100.0 * (float(p.block) + float(bonus.get("block", 0.0))),
		100.0 * (float(p.cdr) + float(bonus.get("cdr", 0.0)))]

func _bag_visible() -> bool:
	var bag := get_node_or_null("../InventoryPanel")
	return bag != null and bag.visible

func _on_slot_pressed(slot_id: String) -> void:
	var now := Time.get_ticks_msec()
	if slot_id == _last_slot_id and now - _last_slot_click_ms <= 400:
		_last_slot_id = ""
		_last_slot_click_ms = 0
		if _bag_visible() and GameState.equipment.get(slot_id) is Dictionary:
			GameState.unequip_slot(slot_id)
	else:
		_last_slot_id = slot_id
		_last_slot_click_ms = now

func _on_equipment_dropped(_index: int, payload: Dictionary, slot_id: String) -> void:
	if not visible or not _bag_visible() or int(payload.get("from", -1)) != ItemSlot.ROLE_BAG:
		return
	var index := int(payload.get("index", -1))
	if index < 0 or index >= GameState.inventory.size():
		return
	var current: Variant = GameState.inventory[index]
	if not current is Dictionary or not Warehouse.token_matches(current, String(payload.get("token", ""))):
		EventBus.toast_requested.emit(Localization.tr_key("ui.character_panel.p006"), "danger")
		return
	GameState.equip_from_inventory(index, slot_id)

func _equipment_tooltip(item: Dictionary) -> String:
	var lines: Array[String] = [ItemUtil.display_name(item)]
	lines.append_array(ItemUtil.attr_lines(item))
	return "\n".join(PackedStringArray(lines))
