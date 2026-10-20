extends Control
## M10-8：装备重铸面板。选装备 → 看当前词条与费用 → 重铸。
## 与升星面板同构（选装备 → 看现状 → 看价格 → 按按钮 → 看结果），但**不消耗如意**、
## 只有一掷：词条全换，品质 / 星级 / 基底 / 实例 id 一律不动。

const PANEL_ID := "reforge"
const WIDTH := 520.0
const COL_WARN := Color(0.88, 0.42, 0.36)
## 无词条（普通品质）时的占位符：与「×」同类，属界面符号不属文案。
const EMPTY_AFFIX_TEXT := "—"

var _picker: OptionButton
var _hint: Label
var _affix_title: Label
var _affixes: Label
var _price: Label
var _feedback: Label
var _button: Button
var _center: FloatingWindow
var _choices: Array[Dictionary] = []
var _selected_id := ""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
	EventBus.inventory_changed.connect(_on_items_changed)
	EventBus.equipment_changed.connect(_on_items_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.reforge_panel_requested.connect(_on_requested)

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("pause")):
		set_open(false)
		get_viewport().set_input_as_handled()

func _on_requested() -> void:
	set_open(true)

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open(PANEL_ID, open)
	if open:
		_feedback.text = ""
		_refresh_choices()
		EventBus.panel_opened.emit(PANEL_ID)
		_center.show_window()

func _on_panel_opened(panel_id: String) -> void:
	if panel_id != PANEL_ID and visible:
		set_open(false)

func _on_items_changed() -> void:
	if visible:
		_refresh_choices()

func _on_gold_changed(_amount: int) -> void:
	if visible:
		_refresh_details()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.42)
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
	root.custom_minimum_size = Vector2(WIDTH, 0)
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	var title := Label.new()
	title.text = Localization.tr_key("ui.reforge_panel.p002")
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	PanelChrome.style_title(title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)
	# 与其余浮窗同构：标题行拖动、点击置前、越界夹紧（工程 74 §7）。
	_center.setup(self, panel, head, Vector2(0.5, 0.5))
	root.add_child(PanelChrome.make_title_gap())
	_hint = Label.new()
	_hint.text = Localization.tr_key("ui.reforge_panel.p001")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", PanelChrome.MUTED)
	root.add_child(_hint)
	_picker = OptionButton.new()
	_picker.custom_minimum_size.y = 36
	_picker.item_selected.connect(_on_selected)
	root.add_child(_picker)
	PanelChrome.style_option_button(_picker)
	_affix_title = Label.new()
	_affix_title.text = Localization.tr_key("ui.reforge_panel.p003")
	PanelChrome.style_section(_affix_title)
	root.add_child(_affix_title)
	_affixes = Label.new()
	_affixes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_affixes.add_theme_color_override("font_color", PanelChrome.TEXT)
	root.add_child(_affixes)
	_price = Label.new()
	_price.add_theme_color_override("font_color", PanelChrome.GOLD_LIGHT)
	root.add_child(_price)
	_button = Button.new()
	_button.text = Localization.tr_key("ui.reforge_panel.p004")
	_button.custom_minimum_size.y = 38
	_button.pressed.connect(_on_reforge)
	root.add_child(_button)
	PanelChrome.style_action(_button, true)
	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_feedback)

## 候选＝已穿戴（按槽位定义序）+ 背包（按格序），与升星面板同一范式。
## 刻意**不过滤「不能重铸的装备」**：普通品质的装备也要能选中，玩家才看得到
## 按钮为什么是灰的（tooltip 给出原因），而不是「我的装备消失了」。
func _refresh_choices() -> void:
	_choices.clear()
	_picker.clear()
	for slot in Equipment.SLOT_DEFS:
		var sid := String(slot.id)
		var item = GameState.equipment.get(sid)
		if item is Dictionary:
			_add_choice("worn", sid, item, Localization.tr_key("ui.upgrade.worn_slot") % String(slot.label))
	for index in range(GameState.inventory.size()):
		var item = GameState.inventory[index]
		if item is Dictionary and String(item.get("kind", "")) == "equip":
			_add_choice("bag", index, item, Localization.tr_key("ui.upgrade.bag_slot") % (index + 1))
	if _choices.is_empty():
		_picker.add_item(Localization.tr_key("ui.reforge_panel.p005"))
		_picker.disabled = true
		_selected_id = ""
	else:
		_picker.disabled = false
		var choice_index := 0
		for i in range(_choices.size()):
			if String(_choices[i].id) == _selected_id:
				choice_index = i
				break
		_picker.select(choice_index)
		_selected_id = String(_choices[choice_index].id)
	_refresh_details()

func _add_choice(source: String, key: Variant, item: Dictionary, prefix: String) -> void:
	var id := String(item.get("instanceId", ""))
	if id.is_empty():
		return
	_choices.append({"source": source, "key": key, "id": id})
	_picker.add_item("%s　%s" % [prefix, ItemUtil.display_name(item)])

func _on_selected(index: int) -> void:
	if index >= 0 and index < _choices.size():
		_selected_id = String(_choices[index].id)
		_feedback.text = ""
		_refresh_details()

func _selected_item() -> Dictionary:
	var index := _picker.selected
	if index < 0 or index >= _choices.size():
		return {}
	var choice := _choices[index]
	var candidate = GameState.inventory[choice.key] if choice.source == "bag" \
		else GameState.equipment.get(choice.key)
	if candidate is Dictionary and String(candidate.get("instanceId", "")) == String(choice.id):
		return candidate
	return {}

func _refresh_details() -> void:
	var item := _selected_item()
	if item.is_empty():
		_affixes.text = Localization.tr_key("ui.reforge_panel.p010")
		_price.text = ""
		_button.disabled = true
		_button.tooltip_text = ""
		return
	var lines := ItemUtil.affix_lines(item)
	_affixes.text = "\n".join(lines) if not lines.is_empty() else EMPTY_AFFIX_TEXT
	var price := Reforge.cost(Equipment.level_req(item))
	var guard := Reforge.can_reforge(item)
	_price.text = "" if price <= 0 else Localization.tr_key("ui.reforge_panel.p006") % [price, GameState.gold]
	_button.disabled = not bool(guard.get("ok", false)) or price <= 0 or GameState.gold < price
	if not bool(guard.get("ok", false)):
		_button.tooltip_text = String(guard.get("reason", ""))
	elif price <= 0:
		_button.tooltip_text = Localization.tr_key("msg.reforge.p004")
	elif GameState.gold < price:
		_button.tooltip_text = Localization.tr_key("ui.reforge_panel.p007")
	else:
		_button.tooltip_text = ""

func _on_reforge() -> void:
	var index := _picker.selected
	if index < 0 or index >= _choices.size():
		return
	var choice := _choices[index]
	var before := _selected_item()
	var old_lines := ItemUtil.affix_lines(before)
	var result := GameState.reforge_equipment(String(choice.source), choice.key, String(choice.id))
	if not bool(result.get("ok", false)):
		_feedback.text = String(result.get("reason", ""))
		_feedback.add_theme_color_override("font_color", COL_WARN)
		_refresh_details()
		return
	var new_lines: Array = ItemUtil.affix_lines({
		"affixes": result.get("affixes", []), "pctAttrs": result.get("pctAttrs", []),
	})
	# R-2：重掷有可能掷出与原来完全相同的词条 —— 静默会让玩家以为按钮坏了。
	_feedback.text = Localization.tr_key("ui.reforge_panel.p009") if bool(result.get("unchanged", false)) \
		else Localization.tr_key("ui.reforge_panel.p008") % [", ".join(old_lines), ", ".join(new_lines)]
	_feedback.add_theme_color_override("font_color", PanelChrome.GOLD_LIGHT)
	_refresh_choices()
