class_name BossStatusRow
extends Control
## Boss单行表现：真实头像、等级徽章、名称/阶段/生命独立排版；状态与过期由BossHealthBar持有。
## 只复用纹理与样式，不加载怪物场景，不参与战斗或实例排序。
var _name_label: Label
var _phase: Label
var _numbers: Label
var _percent: Label
var _gap: Label
var _portrait: TextureRect
var _badge: Control
var _level: Label
var _entry: Dictionary = {}
var _expanded := true
var _selected := false
var _plate := StyleBoxFlat.new()
var _track := StyleBoxFlat.new()
var _fill := StyleBoxFlat.new()

## 创建固定子节点，控制名与数值字号，所有主题/纹理资源随行实例释放。
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_plate.bg_color = Color("19191e")
	_plate.border_color = Color("a68a51")
	_plate.set_border_width_all(1)
	_plate.set_corner_radius_all(8)
	_track.bg_color = Color("35242a")
	_track.set_corner_radius_all(3)
	_fill.bg_color = Color("ae3f43")
	_fill.set_corner_radius_all(3)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mask := ShaderMaterial.new()
	mask.shader = preload("res://assets/ui/monster_portrait_circle.gdshader")
	_portrait.material = mask
	add_child(_portrait)
	_name_label = _label(17, Color("e9dcc0"))
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_phase = _label(11, Color("c8a96b"))
	_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_numbers = _label(11, Color("d0c6b7"))
	_percent = _label(11, Color("efdfc0"))
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gap = _label(11, Color("d2ae73"))
	_gap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_badge = Control.new()
	_badge.set_script(preload("res://scripts/ui/hud_level_badge.gd"))
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.position = Vector2(39, 48)
	_badge.size = Vector2(35, 35)
	_level = Label.new()
	_level.name = "LevelLabel"
	_level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level.add_theme_font_size_override("font_size", 13)
	_level.add_theme_color_override("font_color", Color("faf2d4"))
	_level.add_theme_color_override("font_outline_color", Color("171109"))
	_level.add_theme_constant_override("outline_size", 3)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.add_child(_level)
	add_child(_badge)

## 共用标签创建入口，文字描边隔离深色场景背景，子标签不拦截悬停提示。
func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("121116"))
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

## 按对应实例快照更新文字；最多3行，调用者保证每行自身实例id不串台。
func present(entry: Dictionary, expanded: bool, selected: bool) -> void:
	_entry = entry
	_expanded = expanded
	_selected = selected
	_name_label.text = String(entry.name)
	_phase.text = String(entry.get("phase_text", ""))
	_numbers.text = "%d / %d" % [int(entry.hp), int(entry.max_hp)]
	_percent.text = "%.1f%%" % (100.0 * float(entry.hp) / maxf(1.0, float(entry.max_hp)))
	_gap.text = String(entry.get("gap_text", ""))
	_portrait.texture = entry.get("portrait")
	_level.text = str(entry.get("level", "?"))
	_level.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_level.offset_left = 8
	_level.offset_right = -8
	_level.offset_top = 3
	_level.offset_bottom = -3
	tooltip_text = _name_label.text + "\n" + _numbers.text + "\n" + _gap.text
	modulate.a = float(entry.alpha)
	_layout()
	queue_redraw()

## 固定信息行，名称和阶段各有独立区域；大生命数值使用完整独立文字行。
func _layout() -> void:
	var slim := size.y < 60
	var p := 64.0 if _expanded else minf(52.0, size.y-8)
	_portrait.position = Vector2(8, 10 if _expanded else 4)
	_portrait.size = Vector2(p, p)
	_portrait.material.set_shader_parameter("portrait_size", _portrait.size)
	_badge.size.y = 35 if _expanded else 30
	_badge.position = Vector2(74 - _badge.size.x, size.y - _badge.size.y - 3)
	var left := 84.0
	var width := maxf(1.0, size.x - left - 12.0)
	_name_label.position = Vector2(left, 3)
	_name_label.size = Vector2(maxf(1, width - 112), 24)
	_phase.position = Vector2(size.x - 120, 5)
	_phase.size = Vector2(108, 20)
	_numbers.position = Vector2(left, 48)
	_numbers.size = Vector2(maxf(1, width - 64), 18)
	_numbers.visible = _expanded
	_percent.position = Vector2(size.x - 72, 48 if _expanded else 32 if slim else 39)
	_percent.size = Vector2(60, 18)
	_gap.position = Vector2(left, 66)
	_gap.size = Vector2(width, 18)
	_gap.visible = _expanded

## 绘制铜金卡片、冠饰、血量及真实阶段阈值；头像缺失才显示统一轮廓回退。
func _draw() -> void:
	if _entry.is_empty():
		return
	_plate.border_color = Color("e2c581") if _selected else Color("a68a51")
	draw_style_box(_plate, Rect2(Vector2.ZERO, size))
	var center := _portrait.position + _portrait.size * 0.5
	var radius := _portrait.size.x * 0.5
	draw_circle(center, radius + 2, Color("ac915a"))
	draw_circle(center, radius, Color("29252a"))
	if _portrait.texture == null:
		draw_colored_polygon(PackedVector2Array([center+Vector2(-14,14),center+Vector2(0,-15),center+Vector2(14,14),center]), Color("766b60"))
	var crown := PackedVector2Array([Vector2(center.x-22,8),Vector2(center.x-26,0),Vector2(center.x-10,4),Vector2(center.x,-5),Vector2(center.x+10,4),Vector2(center.x+26,0),Vector2(center.x+22,8)])
	draw_colored_polygon(crown, Color("8e7547"))
	var bar := Rect2(84, 24 if size.y < 60 else 29, maxf(1, size.x - 96), 15 if _expanded else 10)
	draw_style_box(_track, bar)
	var ratio := clampf(float(_entry.hp) / maxf(1, float(_entry.max_hp)), 0, 1)
	if ratio > 0:
		draw_style_box(_fill, Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)))
	for threshold in _entry.get("thresholds", []):
		var x := bar.position.x + bar.size.x * float(threshold)
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color("dec68c"), 1)
