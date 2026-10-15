extends Control
## 独立人物面板：装备槽和十二项战斗属性，数值统一读取 GameState。
## 展示形象随当前武器的阶段形象更换（CharacterLook）；头像固定一张，不由本面板维护。

var _slots: Dictionary = {}
var _stats: Label
var _portrait: TextureRect
var _look_id := ""
var _title: Label
var _identity: Label
var _center: FloatingWindow
var _last_slot_id := ""
var _last_slot_click_ms := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
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

## 并开集合统一由 `GameState.panels_coexist`（F-P3-1）判定，本面板不再自带名单。
func _on_panel_opened(panel_id: String) -> void:
	if panel_id == "inventory" and visible:
		_refresh()
	if visible and not GameState.panels_coexist(panel_id, "character"):
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
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 20)
	head.add_child(_title)
	PanelChrome.style_title(_title)
	var help := PanelHelpButton.new()
	help.tooltip_text = Localization.tr_key("ui.character_panel.p002")
	head.add_child(help)
	PanelChrome.style_help(help)
	var close := Button.new()
	close.text = Localization.tr_key("ui.character_panel.p001")
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)
	_center.setup(self, panel, head, Vector2(0.98, 0.18))
	root.add_child(PanelChrome.make_title_gap())

	# F-P2-3：标题行留在外框渐变带内，属性与装备区整体可滚动。
	var content_scroll := ScrollContainer.new()
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content_scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 670
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(content)
	_center.set_content_scroll(content_scroll)

	_identity = Label.new()
	PanelChrome.style_section(_identity)
	content.add_child(_identity)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	content.add_child(body)
	var equipment_card := PanelContainer.new()
	PanelChrome.style_card(equipment_card)
	body.add_child(equipment_card)
	var equip := VBoxContainer.new()
	# 七槽列 52 + 间距 8 + 展示框 258 + 间距 8 + 七槽列 52 = 378，随展示框同步放大。
	equip.custom_minimum_size.x = 378
	equipment_card.add_child(equip)
	var equipment_title := Label.new()
	equipment_title.text = "穿戴装备"
	PanelChrome.style_section(equipment_title)
	equip.add_child(equipment_title)
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
	portrait_style.bg_color = Color("10191e")
	portrait_style.border_color = Color("485b5f")
	portrait_style.set_border_width_all(1)
	portrait_style.set_corner_radius_all(6)
	portrait_frame.add_theme_stylebox_override("panel", portrait_style)
	# 展示盒内宽 258 - 2（边框）= 256 = 64 × 4，固定 ×4 整数倍放大，避免像素粗细不均。
	portrait_frame.custom_minimum_size = Vector2(258, 410)
	figure.add_child(portrait_frame)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait_frame.add_child(_portrait)
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
	var stats_card := PanelContainer.new()
	PanelChrome.style_card(stats_card)
	body.add_child(stats_card)
	_stats = Label.new()
	_stats.custom_minimum_size.x = 245
	_stats.add_theme_font_size_override("font_size", 15)
	_stats.add_theme_constant_override("line_spacing", 5)
	_stats.add_theme_color_override("font_color", PanelChrome.TEXT)
	stats_card.add_child(_stats)

func _refresh() -> void:
	if _title == null:
		return
	var player_name := String(GameState.player.get("name", Localization.tr_key("ui.character_panel.p003")))
	_title.text = PanelChrome.title_text("人物 · %s" % player_name)
	_identity.text = "%s      Lv %d" % [player_name, int(GameState.player.get("level", 1))]
	_apply_look()
	for def in Equipment.SLOT_DEFS:
		var sid := String(def.id)
		var button: EquipmentSlot = _slots[sid]
		var item: Variant = GameState.equipment.get(sid)
		button.item = item if item is Dictionary else {}
		button.draggable = item is Dictionary and _bag_visible()
		button.text = ItemUtil.template_name(item).substr(0, 2) if item is Dictionary else String(def.label)
		button.tooltip_text = "%s\n%s" % [String(def.label), _equipment_tooltip(item)] if item is Dictionary else Localization.tr_key("ui.character_panel.p004") % String(def.label)
		SampleArt.decorate(button, SampleArt.icon_for(item))
		_style_equipment_slot(button, item)
		button.queue_redraw()
	# 冷却缩减（cdr）已接线（D7：基础 + 装备，加法累加后截断上限），显示值取结算口径；
	# 其余战斗词条（暴击/攻速/闪避/格挡/移速）执行链尚未接线，装备不参与结算，故仍显示基础值。
	var p := GameState.player
	_stats.text = Localization.tr_key("ui.character_panel.p005") % [
		int(p.hp), GameState.max_hp(), int(p.mp), GameState.max_mp(),
		GameState.total_attack(), GameState.total_defense(), int(p.level),
		float(p.movementSpeed),
		100.0 * float(p.criticalChance),
		float(p.criticalMultiplier),
		maxf(0.1, float(p.attackInterval)),
		100.0 * float(p.dodge),
		100.0 * float(p.block),
		100.0 * GameState.total_cdr()]

## 展示形象随当前武器形象更换；形象 id 未变化时不重建纹理。
func _apply_look() -> void:
	var next := CharacterLook.look_id_for(GameState.equipment)
	if next == _look_id:
		return
	_look_id = next
	_portrait.texture = CharacterLook.panel_texture(next)

func _style_equipment_slot(button: EquipmentSlot, item: Variant) -> void:
	var empty := not item is Dictionary
	var border := Color("737b83") if empty else ItemUtil.quality_color(String(item.get("quality", "common")))
	if button._quality_frame != null and button._quality_frame.visible:
		border = Color.TRANSPARENT
	var style := StyleBoxFlat.new()
	style.bg_color = Color("162329")
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_color_override("font_color", Color("8d959d") if empty else Color.WHITE)
	button.add_theme_font_size_override("font_size", 12)

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
