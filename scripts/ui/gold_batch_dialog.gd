class_name GoldBatchDialog
extends Control
var _token := 0
var _frozen: Array = []
var _excluded: Array = []
var _busy := false
var _include: CheckBox
var _summary: Label
var _status: Label
var _tree: Tree
var _confirm: Button
var _reload: Button
var _root: VBoxContainer
var _window: FloatingWindow

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_window = FloatingWindow.new()
	add_child(_window)
	var panel := PanelChrome.new()
	_window.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 10)
	margin.add_child(_root)
	var head := HBoxContainer.new()
	_root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	var title := Label.new()
	title.text = Localization.tr_key("ui.batch.title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PanelChrome.style_title(title)
	head.add_child(title)
	var close_button := Button.new()
	PanelChrome.style_close(close_button)
	close_button.pressed.connect(close)
	head.add_child(close_button)
	_window.setup(self, panel, head, Vector2(0.5, 0.5))
	_root.add_child(PanelChrome.make_title_gap())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	_window.set_content_scroll(scroll)
	_include = CheckBox.new()
	_include.text = Localization.tr_key("ui.batch.include")
	_include.toggled.connect(func(_on: bool) -> void:
		if not _busy:
			_refresh())
	body.add_child(_include)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_color_override("font_color", PanelChrome.TEXT)
	body.add_child(_summary)
	_tree = Tree.new()
	_tree.columns = 1
	_tree.hide_root = true
	_tree.custom_minimum_size.y = 210
	_tree.add_theme_color_override("font_color", PanelChrome.TEXT)
	_tree.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_tree.item_edited.connect(_on_item_edited)
	body.add_child(_tree)
	var hint := Label.new()
	hint.text = Localization.tr_key("ui.batch.hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", PanelChrome.MUTED)
	body.add_child(hint)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", PanelChrome.DANGER)
	body.add_child(_status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	body.add_child(actions)
	_reload = Button.new()
	_reload.text = Localization.tr_key("ui.batch.reload")
	_reload.pressed.connect(_read_inventory)
	PanelChrome.style_action(_reload)
	actions.add_child(_reload)
	_confirm = Button.new()
	_confirm.pressed.connect(_submit)
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PanelChrome.style_action(_confirm, true)
	actions.add_child(_confirm)
	var cancel := Button.new()
	cancel.text = Localization.tr_key("ui.batch.cancel")
	cancel.pressed.connect(close)
	PanelChrome.style_action(cancel)
	actions.add_child(cancel)
	visible = false
	EventBus.inventory_changed.connect(func() -> void:
		if visible and not _busy:
			_refresh(false))
	EventBus.equipment_changed.connect(func() -> void:
		if visible and not _busy:
			_refresh(false))
	EventBus.panels_close_requested.connect(close)
	get_viewport().size_changed.connect(_resize)
	EventBus.settings_changed.connect(_resize)

func open() -> void:
	visible = true
	_include.set_pressed_no_signal(false)
	_read_inventory()
	_resize()
	_window.show_window()
	_confirm.grab_focus()

func close() -> void:
	if not visible:
		return
	visible = false
	_busy = false
	GameState.cancel_gold_batch()
	_frozen = []
	_excluded = []
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()

func _resize() -> void:
	var logical := get_viewport_rect().size / SettingsRuntime.ui_scale_value()
	_root.custom_minimum_size.x = minf(610.0, logical.x * 0.86)
	_tree.custom_minimum_size.y = clampf(logical.y - 380.0, 70.0, 280.0)

func _read_inventory() -> void:
	if _busy:
		return
	var session := GameState.begin_gold_batch()
	_token = int(session.token)
	_frozen = session.items
	_excluded = []
	_include.disabled = false
	_reload.disabled = false
	_tree.mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh()

func _refresh(rebuild_tree: bool = true) -> void:
	if not visible:
		return
	var plan := GameState.preview_gold_batch(_token, _include.button_pressed, _excluded)
	var ok := bool(plan.get("ok", false))
	var count := (plan.get("groups", []) as Array).size()
	_confirm.disabled = not ok or count == 0
	_confirm.text = Localization.tr_key("ui.batch.confirm", [count])
	_status.text = String(plan.get("reason", "")) if not ok else (Localization.tr_key("ui.batch.empty") if count == 0 else "")
	if not ok:
		return
	var output_lines: Array[String] = []
	var tiers: Array = plan.outputs.keys()
	tiers.sort()
	for tier in tiers:
		output_lines.append(Localization.tr_key("ui.batch.output", [tier, plan.outputs[tier]]))
	_summary.text = Localization.tr_key("ui.batch.summary", [count * 4, count, plan.remaining, plan.protected]) + "\n" + Localization.tr_key("ui.batch.protected", [plan.favorites, _excluded.size()]) + "\n" + "，".join(output_lines)
	if int(plan.mixed) > 0:
		_summary.text += "\n" + Localization.tr_key("ui.batch.downgrade", [plan.mixed, plan.downgraded])
	if int(plan.starred) > 0:
		_summary.text += "\n" + Localization.tr_key("ui.batch.starred", [plan.starred])
	if rebuild_tree:
		_tree.clear()
		var root := _tree.create_item()
		var used := {}
		for i in range(count):
			var group: Array = plan.groups[i]
			var parent := _tree.create_item(root)
			parent.set_text(0, Localization.tr_key("ui.batch.group", [i + 1, EquipmentFusion.tier_start(group[0])]))
			parent.collapsed = true
			for item in group:
				_add_material(parent, item)
				used[item.instanceId] = true
		var other := _tree.create_item(root)
		other.set_text(0, Localization.tr_key("ui.batch.other"))
		other.collapsed = true
		for item in _frozen:
			if not used.has(item.instanceId):
				_add_material(other, item)

func _add_material(parent: TreeItem, item: Dictionary) -> void:
	var row := _tree.create_item(parent)
	row.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	row.set_text(0, ItemUtil.display_name(item))
	row.set_metadata(0, String(item.instanceId))
	row.set_checked(0, not _excluded.has(String(item.instanceId)))
	row.set_editable(0, true)
	row.set_tooltip_text(0, "\n".join(ItemUtil.attr_lines(item)))

func _on_item_edited() -> void:
	if _busy:
		return
	var row := _tree.get_edited()
	if row == null:
		return
	var id := String(row.get_metadata(0))
	if row.is_checked(0):
		_excluded.erase(id)
	elif not _excluded.has(id):
		_excluded.append(id)
	_refresh.call_deferred()

func _submit() -> void:
	if _busy or not visible:
		return
	var token := _token
	var started := GameState.start_gold_batch(token, _include.button_pressed, _excluded)
	if not bool(started.get("ok", false)):
		_status.text = String(started.get("reason", ""))
		_refresh(false)
		return
	_busy = true
	_include.disabled = true
	_reload.disabled = true
	_confirm.disabled = true
	_tree.mouse_filter = Control.MOUSE_FILTER_IGNORE
	while visible and _token == token:
		var step := GameState.advance_gold_batch(token)
		if not bool(step.get("ok", false)):
			_busy = false
			_status.text = String(step.get("reason", ""))
			_reload.disabled = false
			return
		if bool(step.get("done", false)):
			var text := Localization.tr_key("ui.batch.done", [step.count, step.consumed, step.count, step.remaining])
			close()
			EventBus.toast_requested.emit(text, "pickup")
			return
		_status.text = Localization.tr_key("ui.batch.progress", [step.generated, step.count])
		await get_tree().process_frame

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey:
		get_viewport().set_input_as_handled()
