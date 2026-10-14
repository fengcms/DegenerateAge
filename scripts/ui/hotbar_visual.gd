class_name HotbarVisual
extends RefCounted
## 用户确认的无底座快捷栏造型。图标与键位角标独立于底图，保留实时状态和改键能力。

const SLOT_FRAME := preload("res://assets/ui/hotbar_slot_frame.svg")
const EXP_BACKGROUND := preload("res://assets/ui/hotbar_exp_bg.svg")
const EXP_FILL := preload("res://assets/ui/hotbar_exp_fill.svg")
const EXP_FRAME := preload("res://assets/ui/hotbar_exp_frame.svg")
const EXP_MARKER := preload("res://assets/ui/hotbar_exp_marker.svg")
const GROUP_SEPARATOR := preload("res://assets/ui/hotbar_group_separator.svg")
const RED_POTION := preload("res://assets/ui/hotbar_potion_red.svg")
const BLUE_POTION := preload("res://assets/ui/hotbar_potion_blue.svg")
const BASIC_SLASH := preload("res://assets/ui/hotbar_slash.svg")
const PANEL_ICONS := [
	preload("res://assets/ui/hotbar_character.svg"),
	preload("res://assets/ui/hotbar_inventory.svg"),
	preload("res://assets/ui/hotbar_skill.svg"),
	preload("res://assets/ui/hotbar_mount.svg"),
]

static func style_slot(button: Button) -> void:
	button.custom_minimum_size = Vector2(42, 42)
	button.focus_mode = Control.FOCUS_NONE
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 30)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("d8c89f"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var frame := StyleBoxTexture.new()
		frame.texture = SLOT_FRAME
		match state:
			"hover": frame.modulate_color = Color("fff3cd")
			"pressed": frame.modulate_color = Color("ad9368")
			"disabled": frame.modulate_color = Color("777777")
		button.add_theme_stylebox_override(state, frame)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var badge := Panel.new()
	badge.name = "KeyBadge"
	badge.position = Vector2(3, 3)
	badge.size = Vector2(16, 13)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var label := Label.new()
	label.name = "KeyText"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("f4e4b9"))
	label.add_theme_color_override("font_outline_color", Color("080d10e6"))
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	button.add_child(badge)

static func binding_icon(binding: Variant) -> Texture2D:
	if binding is Dictionary:
		if binding.get("kind") == "auto_potion":
			return RED_POTION if binding.get("id") == "red" else BLUE_POTION
		if binding.get("kind") == "skill" and binding.get("id") == "basic_slash":
			return BASIC_SLASH
	return SampleArt.binding_icon(binding)

static func key_name(action: String) -> String:
	var code := SettingsRuntime.key_for(action)
	return OS.get_keycode_string(code) if code > 0 else ""

static func refresh_key(button: Button, action: String) -> void:
	var badge := button.get_node("KeyBadge") as Panel
	var label := badge.get_node("KeyText") as Label
	var full_name := key_name(action)
	var short_name := full_name
	match full_name:
		"Backspace": short_name = "Bksp"
		"Escape": short_name = "Esc"
		"Minus": short_name = "−"
		"Equal": short_name = "="
		"Page Up": short_name = "PgUp"
		"Page Down": short_name = "PgDn"
		"Space": short_name = "Spc"
	if short_name.length() > 5:
		short_name = short_name.left(4) + "…"
	label.text = short_name
	badge.size.x = clampf(7.0 + short_name.length() * 6.0, 16.0, 36.0)
	badge.tooltip_text = full_name

static func style_experience(bar: ProgressBar) -> void:
	var bg := StyleBoxTexture.new()
	bg.texture = EXP_BACKGROUND
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	bar.show_percentage = false
	var fill := TextureRect.new()
	fill.name = "ExperienceFill"
	fill.texture = EXP_FILL
	fill.position = Vector2(10, 4)
	fill.size = Vector2(0, 9)
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	var frame := TextureRect.new()
	frame.name = "ExperienceFrame"
	frame.texture = EXP_FRAME
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(frame)
	var marker := TextureRect.new()
	marker.name = "ProgressTip"
	marker.texture = EXP_MARKER
	marker.size = Vector2(10, 10)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(marker)
	update_experience_marker(bar)

static func update_experience_marker(bar: ProgressBar) -> void:
	var fill := bar.get_node("ExperienceFill") as TextureRect
	fill.size.x = maxf(0.0, (bar.size.x - 20.0) * bar.ratio)
	var marker := bar.get_node("ProgressTip") as TextureRect
	marker.visible = bar.value > 0
	marker.position = Vector2(8.0 + (bar.size.x - 16.0) * bar.ratio - 5.0, 3.5)
