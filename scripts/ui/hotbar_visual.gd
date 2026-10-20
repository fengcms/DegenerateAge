class_name HotbarVisual
extends RefCounted
## 用户确认的无底座快捷栏造型。图标与键位角标独立于底图，保留实时状态和改键能力。

const SLOT_FRAME := preload("res://assets/ui/hotbar_slot_frame.svg")
const EXP_BACKGROUND := preload("res://assets/ui/hotbar_exp_bg.svg")
const EXP_FILL := preload("res://assets/ui/hotbar_exp_fill.svg")
const EXP_FRAME := preload("res://assets/ui/hotbar_exp_frame.svg")
const EXP_MARKER := preload("res://assets/ui/hotbar_exp_marker.svg")
const GROUP_SEPARATOR := preload("res://assets/ui/hotbar_group_separator.svg")
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
		if binding.get("kind") == "skill" and binding.get("id") == "basic_slash":
			return BASIC_SLASH
	return SampleArt.binding_icon(binding)

## 工程 80：格内**短标签**（无图标时的显示文字）。空串表示沿用「名称首字」。
## 三件随身工具都没有图标资源，`decorate` 拿不到图就会显示名称首字 ——
## 「随身车夫」与「随身商队」两个字都是「随」，格子根本分不清（Q2 选 a：简称）。
## 键名与物品 id 一一对应，加新工具时顺手加一条；查不到就回退首字，不会显示空白。
const SHORT_LABEL_KEYS := {
	"tool_portable_carter": "ui.hud.tool_carter_short",
	"tool_portable_shop": "ui.hud.tool_shop_short",
	"tool_boss_token": "ui.hud.tool_token_short",
}

static func short_label(binding: Variant) -> String:
	if not binding is Dictionary:
		return ""
	var key := String((SHORT_LABEL_KEYS as Dictionary).get(String(binding.get("id", "")), ""))
	if key.is_empty():
		return ""
	var text := Localization.tr_key(key)
	# 本地化缺键时 `tr_key` 会回退成键名本身，那种「ui.hud.xxx」不是给人看的。
	return "" if text == key else text

## 工程 80：该绑定要不要显示数量角标。随身工具（`useType: panel`）开面板不消耗，
## 显示「1」既无意义又像消耗品；技能没有数量概念，同样不显示。
static func shows_count(binding: Variant) -> bool:
	if not binding is Dictionary:
		return false
	if String(binding.get("kind", "")) == "skill":
		return false
	if String(binding.get("kind", "")) != "item":
		return true
	var template: Variant = DataLoader.get_entry("miscItems", String(binding.get("id", "")))
	return not (template is Dictionary and String((template as Dictionary).get("useType", "")) == "panel")

## 工程 80：物品不在背包时的提示文案。`_activate_hotbar` 只搜背包，
## 工具被玩家放进仓库后点格子会失败 —— 不说清「在哪儿」会被当成功能坏了（Q3 选 a）。
static func missing_item_hint(binding: Variant, in_warehouse: bool) -> String:
	var name := short_label(binding)
	if name.is_empty():
		name = _name_of(binding)
	return Localization.tr_key("ui.hud.p020") % name if in_warehouse \
		else Localization.tr_key("ui.hud.p017") % _name_of(binding)

static func _name_of(binding: Variant) -> String:
	if not binding is Dictionary:
		return Localization.tr_key("ui.hud.p016")
	var id := String(binding.get("id", ""))
	var table := "potions" if String(binding.get("kind", "")) == "potion" else "miscItems"
	var template: Variant = DataLoader.get_entry(table, id)
	return String((template as Dictionary).get("name", id)) if template is Dictionary else id

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
