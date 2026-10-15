extends Control
## 死亡选择；运行在 UI 的 ALWAYS CanvasLayer 下，世界暂停时仍可操作。

var _revive_here: Button
var _hint: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false
	EventBus.player_died.connect(func() -> void: _show_after_death.call_deferred())

func _build() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.05, 0.82)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelChrome.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	var title := Label.new()
	title.text = Localization.tr_key("ui.death_panel.p001")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	PanelChrome.style_title(title)
	box.add_child(PanelChrome.make_title_gap())
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", PanelChrome.MUTED)
	box.add_child(_hint)
	_revive_here = Button.new()
	_revive_here.pressed.connect(revive_here)
	box.add_child(_revive_here)
	PanelChrome.style_action(_revive_here, true)
	var camp := Button.new()
	camp.text = Localization.tr_key("ui.death_panel.p002")
	camp.pressed.connect(revive_camp)
	box.add_child(camp)
	PanelChrome.style_action(camp)

func _show_after_death() -> void:
	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	if player == null or not player.is_dead:
		return
	visible = true
	GameState.set_panel_open("death", true)
	_refresh()
	get_tree().paused = true

func _refresh() -> void:
	var count := 0
	for item in GameState.inventory:
		if item is Dictionary and String(item.get("itemId", "")) == "misc_revive_scroll":
			count += int(item.get("count", 1))
	_revive_here.text = Localization.tr_key("ui.death_panel.p003") % count
	_revive_here.disabled = count <= 0
	_hint.text = Localization.tr_key("ui.death_panel.p004")

func revive_here() -> bool:
	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	if player == null or not player.is_dead:
		return false
	for i in range(GameState.inventory.size()):
		var item = GameState.inventory[i]
		if not item is Dictionary or String(item.get("itemId", "")) != "misc_revive_scroll":
			continue
		if int(item.get("count", 1)) > 1:
			item.count = int(item.get("count", 1)) - 1
			EventBus.inventory_changed.emit()
		else:
			GameState.remove_item_at(i)
		player._revive()
		_close()
		SaveManager.request_autosave()
		return true
	_refresh()
	return false

func revive_camp() -> bool:
	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	if player == null or not player.is_dead or not MapService.exists("camp"):
		return false
	if GameState.current_map != "camp" and (get_tree().current_scene == null or not get_tree().current_scene.has_node("Game")):
		return false
	if GameState.current_map == "camp":
		player.global_position = MapService.entry_point("camp")
		player._revive()
		_close()
		SaveManager.request_autosave()
		return true
	var result := MapService._prepare_travel("camp", "revive", 0, MapService.entry_point("camp"))
	if not bool(result.get("ok", false)):
		return false
	player._revive()
	_close()
	MapService.reload_world()
	return true

func _close() -> void:
	visible = false
	GameState.set_panel_open("death", false)
	get_tree().paused = false
