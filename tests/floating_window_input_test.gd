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

	# 铁匠系面板（裸 `CenterContainer` 宿主）与常驻浮窗并开：点谁谁到前面来（工程 74 §4 P1）。
	for panel in panels:
		panel.set_open(false)
	var fusion: Control = load("res://scenes/ui/EquipmentFusionPanel.tscn").instantiate()
	layer.add_child(fusion)
	fusion.set_open(true)
	var character: Control = panels[2]
	character.set_open(true)
	await get_tree().process_frame
	var character_window: FloatingWindow = character.get("_center")
	_check(character.get_index() > fusion.get_index(), "后开的人物面板先压住保星升级面板")
	# 人物面板连同遮罩整体挪出可视区，保证下面的点击点只可能落在保星升级面板本体上。
	character_window._user_moved = true
	character_window._layout()
	character_window.position = character_window.position + Vector2(2000, 2000)
	var fusion_box: Control = fusion.get("_box")
	var fusion_hits := {}
	fusion_box.gui_input.connect(_record_box_hit.bind(fusion.name, fusion_hits))
	var point := fusion_box.get_global_rect().position + Vector2(20, 4)
	_check(fusion_box.get_global_rect().has_point(point)
		and not character_window.panel_box.get_global_rect().has_point(point),
		"点击点落在保星升级面板上且未被人物面板覆盖")
	_mouse(point, true)
	_mouse(point, false)
	await get_tree().process_frame
	_check(fusion_hits.get(fusion.name, 0) == 1, "鼠标命中绕后那扇面板本体")
	_check(fusion.get_index() > character.get_index(), "点击后保星升级升到人物面板之前")
	_check(fusion.z_index > character.z_index, "点击后视觉层级同步升到人物面板之前")
	_check(FloatingWindow.is_top_panel(fusion) and not FloatingWindow.is_top_panel(character),
		"Esc 目标随点击同源切到保星升级")

	# 层级锚点（模态 / 覆盖层）不可被浮窗越过（工程 74 §5.1 / §5.2）。
	var modal := Control.new()
	modal.name = "SettingsPanel"
	modal.visible = true
	layer.add_child(modal)
	layer.move_child(modal, 1)
	FloatingWindow.raise_panel(fusion)
	_check(fusion.get_index() < modal.get_index(), "置前止步于打开中的模态面板之下")
	modal.queue_free()
	fusion.set_open(false)

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
