extends Node
## 用真实四面板验证标题拖动、兄弟节点顺序与鼠标命中一致。

var _failures: Array[String] = []

func _ready() -> void:
	var layer := Control.new()
	layer.size = Vector2(1280, 800)
	add_child(layer)
	var panels: Array[Control] = []
	for path in ["res://scenes/ui/InventoryPanel.tscn", "res://scenes/ui/MountPanel.tscn",
			"res://scenes/ui/CharacterPanel.tscn", "res://scenes/ui/SkillPanel.tscn"]:
		var panel: Control = load(path).instantiate()
		layer.add_child(panel)
		panels.append(panel)
		panel.set_open(true)
	await get_tree().process_frame
	for panel in panels:
		var window: FloatingWindow = panel.get("_center")
		window._user_moved = true
		window._floating_position = Vector2(100, 100)
		window._layout()
	var hit_counts := {}
	for panel in panels:
		var window: FloatingWindow = panel.get("_center")
		window.panel_box.gui_input.connect(_record_box_hit.bind(panel.name, hit_counts))

	# 每个面板轮流成为前台，重叠处的真实 GUI 点击不能唤起场景树靠后的面板。
	for panel in panels:
		var window: FloatingWindow = panel.get("_center")
		window.bring_forward()
		_check(window.is_top_window(), "%s 的视觉层级置顶" % panel.name)
		var top_index := -1
		for peer in panels:
			top_index = maxi(top_index, peer.get_index())
		_check(panel.get_index() == top_index, "%s 的鼠标命中顺序置顶" % panel.name)
		hit_counts.clear()
		_mouse(Vector2(200, 110), true)
		_mouse(Vector2(200, 110), false)
		await get_tree().process_frame
		_check(hit_counts.get(panel.name, 0) == 1, "重叠上沿命中 %s" % panel.name)
		for peer in panels:
			if peer != panel:
				_check(hit_counts.get(peer.name, 0) == 0, "重叠上沿不误触 %s" % peer.name)
		_check(window.is_top_window(), "点击重叠区后 %s 仍在前台" % panel.name)

	# 用户截图中的背包/技能内容重叠区，也须按视觉前后归属事件。
	var inventory: Control = panels[0]
	var bag: FloatingWindow = inventory.get("_center")
	panels[1].visible = false
	panels[2].visible = false
	bag._floating_position = Vector2(320, 180)
	bag._layout()
	var skill_window: FloatingWindow = panels[3].get("_center")
	skill_window._floating_position = Vector2(40, 80)
	skill_window._layout()
	bag.bring_forward()
	hit_counts.clear()
	_mouse(Vector2(430, 325), true)
	_mouse(Vector2(430, 325), false)
	await get_tree().process_frame
	_check(hit_counts.get("InventoryPanel", 0) == 1 and hit_counts.get("SkillPanel", 0) == 0,
		"背包内容重叠区只命中前面的背包")

	# 上沿背景比标题 HBox 高；在该区域按下、移动、松开必须完整拖动。
	bag.bring_forward()
	var start := bag.panel_box.global_position + Vector2(100, 12)
	var original := bag.position
	_mouse(start, true)
	_check(bag._dragging, "标题上沿能够开始拖动")
	var motion := InputEventMouseMotion.new()
	motion.position = start + Vector2(40, 30)
	motion.global_position = motion.position
	motion.relative = Vector2(40, 30)
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	_check(bag.position.distance_to(original + Vector2(40, 30)) < 1.0, "拖动跟随鼠标移动")
	_mouse(motion.position, false)
	_check(not bag._dragging, "松开鼠标结束拖动")

	# 帮助与关闭按钮位于标题行，点击它们不得被背景拖动处理。
	var help: Button = bag.header.get_child(bag.header.get_child_count() - 2)
	var help_point := help.get_global_rect().get_center()
	_mouse(help_point, true)
	_check(not bag._dragging, "帮助按钮不会启动窗口拖动")
	_mouse(help_point, false)

	if _failures.is_empty():
		print("[FloatingWindowInputTest] 全部通过 ✅")
	else:
		for failure in _failures:
			push_error("[FloatingWindowInputTest] 失败：" + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	get_viewport().push_input(event, true)

func _record_box_hit(event: InputEvent, panel_name: String, counts: Dictionary) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		counts[panel_name] = counts.get(panel_name, 0) + 1

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
