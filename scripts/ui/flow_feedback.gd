extends Control
## 加载、配置错误与首章轻提示；主世界停下时仍可显示。

var _loading: Control
var _loading_title: Label
var _tip: Label
var _warning: PanelContainer
var _warning_text: Label
var _guide: PanelContainer
var _guide_text: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	EventBus.loading_changed.connect(_on_loading)
	EventBus.quest_accepted.connect(_on_quest_accepted)
	_on_loading(MapService.loading_active, MapService.loading_message)
	_maybe_first_guide.call_deferred()

func _build() -> void:
	_loading = Control.new()
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_loading)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.05, 0.94)
	_loading.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 420
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	_loading_title = Label.new()
	_loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_title.add_theme_font_size_override("font_size", 22)
	box.add_child(_loading_title)
	var bar := ProgressBar.new()
	bar.indeterminate = true
	bar.custom_minimum_size.y = 16
	box.add_child(bar)
	_tip = Label.new()
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_tip)
	_loading.visible = false

	_warning = PanelContainer.new()
	_warning.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_warning.offset_left = 20
	_warning.offset_top = 16
	_warning.offset_right = -20
	_warning.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_warning)
	var warning_row := HBoxContainer.new()
	_warning.add_child(warning_row)
	_warning_text = Label.new()
	_warning_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_warning_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_text.add_theme_color_override("font_color", Color("ffad8c"))
	warning_row.add_child(_warning_text)
	var dismiss := Button.new()
	dismiss.text = Localization.tr_key("ui.flow_feedback.p001")
	dismiss.pressed.connect(func() -> void: _warning.visible = false)
	warning_row.add_child(dismiss)
	_warning.visible = false

	_guide = PanelContainer.new()
	_guide.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_guide.offset_left = -300
	_guide.offset_top = -155
	_guide.offset_right = 300
	_guide.offset_bottom = -55
	_guide.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_guide)
	var guide_box := VBoxContainer.new()
	_guide.add_child(guide_box)
	_guide_text = Label.new()
	_guide_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guide_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_box.add_child(_guide_text)
	var close_guide := Button.new()
	close_guide.text = Localization.tr_key("ui.flow_feedback.p002")
	close_guide.pressed.connect(_dismiss_guide)
	guide_box.add_child(close_guide)
	_guide.visible = false

func _on_loading(active: bool, message: String) -> void:
	_loading.visible = active
	if active:
		_loading_title.text = message if not message.is_empty() else Localization.tr_key("ui.flow_feedback.p003")
		_tip.text = Localization.tr_key("loading.tip.%d" % randi_range(1, 3))

func show_config_errors(report: Array[String]) -> void:
	if report.is_empty():
		return
	_warning_text.text = Localization.tr_key("ui.flow_feedback.p004") % [report.size(), "\n".join(PackedStringArray(report.slice(0, 3)))]
	_warning.visible = true

func _maybe_first_guide() -> void:
	if GameState.menu_mode != "world" or bool(GameState.settings.get("tutorialSeen", false)):
		return
	var state: Variant = GameState.quest_states.get("Q001", null)
	if state is Dictionary and String(state.get("state", "")) == "rewarded":
		return
	_guide_text.text = Localization.tr_key("ui.flow_feedback.p005")
	_guide.visible = true
	_guide.set_meta("guide_key", "tutorialSeen")

func _on_quest_accepted(quest_id: String) -> void:
	if quest_id != "Q002" or bool(GameState.settings.get("firstBattleHintSeen", false)):
		return
	_guide_text.text = Localization.tr_key("ui.flow_feedback.p006")
	_guide.visible = true
	_guide.set_meta("guide_key", "firstBattleHintSeen")

func _dismiss_guide() -> void:
	_guide.visible = false
	GameState.settings[String(_guide.get_meta("guide_key", "tutorialSeen"))] = true
	EventBus.settings_changed.emit()
