extends Control
## 升星十字面板：中心装备、四周可选如意，预览与结算共用 Upgrade 概率公式。

const PANEL_ID := "upgrade"
const WIDTH := 560.0
const COL_PANEL := Color(0.06, 0.07, 0.09, 0.97)
const COL_BORDER := Color(0.35, 0.33, 0.30)
const COL_GOLD := Color(0.94, 0.78, 0.38)
const COL_WARN := Color(0.88, 0.42, 0.36)

var _picker: OptionButton
var _center: Label
var _preview: Label
var _price: Label
var _feedback: Label
var _upgrade_button: Button
var _choices: Array[Dictionary] = []
var _selected_id := ""
var _rune_pickers: Array[OptionButton] = []
var _rune_choices: Array[String] = ["", "", "", ""]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.inventory_changed.connect(_on_items_changed)
	EventBus.equipment_changed.connect(_on_items_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.upgrade_panel_requested.connect(_on_requested)

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
		_feedback.text = "如意可选填四格；结算后成功或失败都会消耗金币与已选如意。"
		_refresh_choices()
		EventBus.panel_opened.emit(PANEL_ID)

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
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = COL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(WIDTH, 0)
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "装备升星"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	_picker = OptionButton.new()
	_picker.custom_minimum_size.y = 36
	_picker.item_selected.connect(_on_selected)
	root.add_child(_picker)
	var cross := GridContainer.new()
	cross.columns = 3
	cross.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(cross)
	for index in range(9):
		var cell: Control
		if index == 4:
			_center = Label.new()
			_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cell = _center
		elif [1, 3, 5, 7].has(index):
			var rune_cell := VBoxContainer.new()
			var title_label := Label.new()
			title_label.text = "如意 %d" % (_rune_pickers.size() + 1)
			title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rune_cell.add_child(title_label)
			var picker := OptionButton.new()
			picker.custom_minimum_size.y = 34
			picker.item_selected.connect(_on_rune_selected.bind(_rune_pickers.size()))
			rune_cell.add_child(picker)
			_rune_pickers.append(picker)
			cell = rune_cell
		else:
			cell = Control.new()
		cell.custom_minimum_size = Vector2(145, 68)
		cross.add_child(cell)
	_preview = Label.new()
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_preview)
	_price = Label.new()
	_price.add_theme_color_override("font_color", COL_GOLD)
	root.add_child(_price)
	_upgrade_button = Button.new()
	_upgrade_button.text = "升星"
	_upgrade_button.custom_minimum_size.y = 38
	_upgrade_button.pressed.connect(_on_upgrade)
	root.add_child(_upgrade_button)
	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_feedback)

func _refresh_choices() -> void:
	_choices.clear()
	_picker.clear()
	for slot in Equipment.SLOT_DEFS:
		var sid := String(slot.id)
		var item = GameState.equipment.get(sid)
		if item is Dictionary:
			_add_choice("worn", sid, item, "已穿戴 · %s" % String(slot.label))
	for index in range(GameState.inventory.size()):
		var item = GameState.inventory[index]
		if item is Dictionary and String(item.get("kind", "")) == "equip":
			_add_choice("bag", index, item, "背包 · 第 %d 格" % (index + 1))
	if _choices.is_empty():
		_picker.add_item("暂无可升星装备")
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
	_refresh_runes()
	_refresh_details()

func _refresh_runes() -> void:
	var counts := {}
	for item in GameState.inventory:
		if item is Dictionary and String(item.get("kind", "")) == "rune":
			var rune_id := String(item.get("itemId", ""))
			counts[rune_id] = int(counts.get(rune_id, 0)) + int(item.get("count", 1))
	var templates = DataLoader.get_table("runes")
	for slot in range(_rune_pickers.size()):
		var picker := _rune_pickers[slot]
		picker.clear()
		picker.add_item("空")
		var selected_index := 0
		if templates is Array:
			for template in templates:
				if not template is Dictionary:
					continue
				var rune_id := String(template.get("id", ""))
				var choice_index := picker.item_count
				picker.add_item("%s ×%d" % [String(template.get("name", rune_id)), int(counts.get(rune_id, 0))])
				picker.set_item_metadata(choice_index, rune_id)
				picker.set_item_disabled(choice_index, int(counts.get(rune_id, 0)) <= 0)
				if _rune_choices[slot] == rune_id:
					selected_index = choice_index
		picker.select(selected_index)

func _on_rune_selected(choice_index: int, slot: int) -> void:
	var picker := _rune_pickers[slot]
	_rune_choices[slot] = String(picker.get_item_metadata(choice_index)) if choice_index > 0 else ""
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
		_center.text = "选择装备"
		_preview.text = ""
		_price.text = ""
		_upgrade_button.disabled = true
		return
	var star := int(item.get("star", 0))
	_center.text = "%s\n+%d" % [ItemUtil.template_name(item), star]
	if star >= Upgrade.max_star():
		_preview.text = "已达到最高星级。"
		_price.text = "当前金币：%d" % GameState.gold
		_upgrade_button.disabled = true
		return
	var next_item := item.duplicate(true)
	next_item["star"] = star + 1
	_preview.text = "固定属性：%s\n升星后：%s" % [", ".join(ItemUtil.attr_lines(item).slice(0, Upgrade.base_attrs(item).size())),
		", ".join(ItemUtil.attr_lines(next_item).slice(0, Upgrade.base_attrs(item).size()))]
	var price := Upgrade.cost(star)
	var plan := Upgrade.rune_plan(GameState.inventory, _rune_choices)
	var rune_bonus := float(plan.get("bonus", 0.0))
	_price.text = "+%d → +%d　成功率 %.0f%% + 如意 %.0f%% = %.0f%%\n费用 %d 金币　持有 %d" % [
		star, star + 1, Upgrade.success_rate(star), rune_bonus,
		Upgrade.final_rate(star, rune_bonus), price, GameState.gold]
	_upgrade_button.disabled = GameState.gold < price or not plan.get("ok", false)
	_upgrade_button.tooltip_text = "金币不足" if GameState.gold < price else String(plan.get("reason", ""))

func _on_upgrade() -> void:
	var index := _picker.selected
	if index < 0 or index >= _choices.size():
		return
	var choice := _choices[index]
	var result := GameState.upgrade_equipment(String(choice.source), choice.key, String(choice.id), null, _rune_choices.duplicate())
	_feedback.text = String(result.get("reason", ""))
	_feedback.add_theme_color_override("font_color", COL_WARN if not result.get("success", false) else COL_GOLD)
	_refresh_choices()
