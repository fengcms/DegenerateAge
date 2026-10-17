class_name HudStatusBar
extends Control
## HUD 血蓝条：逐行绘制进度，并让悬停中的数值提示随已有 HP/MP 事件实时刷新。
## 只负责显示；数值结算仍由 GameState 完成，HUD 负责把事件写入本控件。

var _live_tooltip_label: WeakRef

@export_enum("HP", "MP") var bar_kind := 0:
	set(next_kind):
		bar_kind = next_kind
		queue_redraw()
		_refresh_live_tooltip()

var max_value := 100.0:
	set(next_max):
		max_value = maxf(1.0, next_max)
		queue_redraw()
		_refresh_live_tooltip()

var value := 100.0:
	set(next_value):
		value = next_value
		queue_redraw()
		_refresh_live_tooltip()

## 原生提示弹出时创建显示节点；弱引用避免关闭提示后仍持有弹窗内容。
func _make_custom_tooltip(_for_text: String) -> Object:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111820")
	style.border_color = Color("74818a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", maxi(9, roundi(16.0 * SettingsRuntime.text_scale_value())))
	label.add_theme_color_override("font_color", Color("e1e7ee"))
	panel.add_child(label)
	_live_tooltip_label = weakref(label)
	_refresh_live_tooltip()
	return panel

## HUD 写入血量或法力后立即刷新当前悬停提示；弹窗关闭时弱引用自然失效。
func _refresh_live_tooltip() -> void:
	var label := _live_tooltip_label.get_ref() as Label if _live_tooltip_label != null else null
	if label == null:
		return
	var key := "ui.hud.hp" if bar_kind == 0 else "ui.hud.mp"
	label.text = "%s  %d / %d" % [Localization.tr_key(key), int(value), int(max_value)]

## 按当前血蓝比例逐行绘制资源条，不生成额外贴图或逐帧重建节点。
func _draw() -> void:
	var w := floorf(size.x)
	var h := floorf(size.y)
	if w < 12.0 or h < 7.0:
		return
	# Both bars use the same half-pixel-per-row slope. Their scene widths account
	# for the vertical gap, so the two right edges form one continuous line.
	var top_right := w - 1.0
	var bottom_right := top_right - (h - 1.0) * 0.5
	var track := PackedVector2Array([Vector2(0, 0), Vector2(top_right, 0), Vector2(bottom_right, h - 1.0), Vector2(0, h - 1.0)])
	draw_colored_polygon(track, Color("11151a"))
	var ratio := clampf(value / max_value, 0.0, 1.0)
	if ratio > 0.0:
		var light := Color("f47b74") if bar_kind == 0 else Color("8bd6f6")
		var mid := Color("cf4a4a") if bar_kind == 0 else Color("4aa3e0")
		var dark := Color("762b34") if bar_kind == 0 else Color("1e527f")
		for row in range(2, int(h) - 2):
			var t := float(row - 2) / maxf(1.0, h - 5.0)
			var color := light.lerp(mid, t / 0.42) if t < 0.42 else mid.lerp(dark, (t - 0.42) / 0.58)
			var row_limit := top_right - float(row) * 0.5 - 2.0
			var right := 2.0 + (row_limit - 2.0) * ratio
			if right > 2.0:
				draw_line(Vector2(2, row + 0.5), Vector2(right, row + 0.5), color, 1.0)
		var shine_right := 3.0 + (top_right - 6.0) * ratio
		if shine_right > 4.0:
			draw_line(Vector2(3, 2.5), Vector2(shine_right, 2.5), light.lightened(0.22), 1.0)
	draw_polyline(PackedVector2Array([Vector2(0, h - 1), Vector2(0, 0), Vector2(top_right, 0), Vector2(bottom_right, h - 1), Vector2(0, h - 1)]), Color("716d65"), 1.0)
