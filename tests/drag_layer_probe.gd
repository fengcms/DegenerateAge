extends Node
## 拖拽预览层级诊断与验收（开发期，M5 移除）。
##
## 复现并验证「拖动背包装备时，跟随鼠标的元素被货郎面板遮挡」的问题。
## 做法：真实模拟鼠标「按下 → 分步移动」（触发引擎拖放），然后
##   ① 打印 Viewport 根下新增的 Control（即引擎拖拽预览挂在哪一层）；
##   ② 截图，直观确认拖动中的元素是否被面板遮挡。
##
## 运行：/Applications/Godot.app/Contents/MacOS/Godot --path . res://tests/DragLayerProbe.tscn

func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(20):
		await get_tree().process_frame

	GameState.reset_to_defaults()
	GameState.player.level = 5
	GameState.add_item(_equip("helmet_cloth", "drag_helm", "rare", {"def": 2}))
	GameState.add_item(_equip("shoes_cloth", "drag_shoes", "uncommon", {"def": 1}))
	EventBus.inventory_changed.emit()

	# 走近货郎 → 按 E 打开交易会话（双面板并列）
	var game: Node = main.get_node("Game")
	var npc = game.get_node("Npcs").get_child(0)
	var player = game.get_node("Entities/Player")
	player.global_position = npc.global_position + Vector2(40.0, 0.0)
	await get_tree().process_frame
	game._try_interact()
	for _i in range(12):
		await get_tree().process_frame

	var inv: Control = main.get_node("UI/InventoryPanel")
	var panel: Control = main.get_node("UI/ShopPanel")
	panel._tabs.current_tab = 1
	for _i in range(6):
		await get_tree().process_frame

	var from: Vector2 = inv._bag_buttons[0].get_global_rect().get_center()
	var to: Vector2 = panel._tray_slots[0].get_global_rect().get_center()
	print("[DragProbe] 起点(背包格 0)=%s　终点(出售托盘格 0)=%s" % [str(from), str(to)])

	# 真实鼠标输入：按下 → 8 步移动到托盘上（超过引擎拖拽阈值），
	# 最后两步都停在货郎面板区域内，便于观察层级。
	var known := _all_controls()
	_send_move(from, Vector2.ZERO)
	await get_tree().process_frame
	_send_press(from)
	await get_tree().process_frame
	var steps := [0.15, 0.35, 0.55, 0.72, 0.86, 0.94, 1.0, 1.0]
	var prev := from
	for t in steps:
		var cur: Vector2 = from.lerp(to, float(t))
		_send_move(cur, cur - prev)
		prev = cur
		await get_tree().process_frame
	for _i in range(6):
		await get_tree().process_frame

	print("[DragProbe] 引擎拖拽中 gui_is_dragging=%s" % str(get_viewport().gui_is_dragging()))
	_report_root_controls(known)
	_report_new_nodes(known)
	_report_ui_layer(main)
	print("[DragProbe] 真实鼠标位置=%s" % str(get_viewport().get_mouse_position()))

	# 幽灵跟随「真实光标」；注入事件只改动引擎内部指针位置，不移动真实光标，
	# 故显式把光标 warp 到终点，让幽灵出现在货郎面板区域上。
	Input.warp_mouse(to)
	for _i in range(8):
		await get_tree().process_frame
	var shop: Control = main.get_node("UI/ShopPanel")
	var ghost := _find_ghost(main)
	print("[DragProbe] warp 后鼠标=%s" % str(get_viewport().get_mouse_position()))
	if ghost != null:
		print("[DragProbe] 幽灵 path=%s z_index=%d pos=%s" % [
			ghost.get_path(), ghost.z_index, str(ghost.global_position)])
		print("[DragProbe] 层级断言：幽灵 z_index=%d > 货郎面板 z_index=%d → %s" % [
			ghost.z_index, shop.z_index,
			"✅ 恒定绘制在面板之上" if ghost.z_index > shop.z_index else "❌ 仍会被遮挡"])
		var vp := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		if not vp.has_point(ghost.global_position):
			ghost.set_process(false)
			ghost.global_position = shop.get_global_rect().get_center() - Vector2(60.0, 40.0)
			print("[DragProbe] （光标在视口外：已冻结跟随并摆到货郎面板上方便于截图，层级仍为真实）")
	else:
		print("[DragProbe] ❌ 未找到拖拽幽灵")

	for _i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_drag_probe.png")

	# 松手落在托盘上（确认拖放本身正常工作）
	_send_release(to)
	for _i in range(4):
		await get_tree().process_frame
	print("[DragProbe] 松手后托盘件数=%d（拖放判定本身应正常）" % panel._tray.size())
	print("[DragProbe] 截图：/tmp/degenerateage_drag_probe.png")
	get_tree().quit()

# ---- 证据收集 ----

## 当前挂在 Viewport 根下的 Control（引擎的拖拽预览会被 add_child 到这里）。
func _root_controls() -> Dictionary:
	var d := {}
	for c in get_viewport().get_children():
		if c is Control:
			d[c.get_instance_id()] = c
	return d

func _report_root_controls(known: Dictionary) -> void:
	var found := 0
	for c in get_viewport().get_children():
		if not (c is Control):
			continue
		if known.has(c.get_instance_id()):
			continue
		found += 1
		print("[DragProbe] ⚠ Viewport 根下新增 Control：name=%s class=%s pos=%s size=%s" % [
			c.name, c.get_class(), str(c.global_position), str(c.size)])
	print("[DragProbe] Viewport 根下新增 Control 数=%d" % found)

## 全树 Control 集合（用于找出引擎预览节点究竟挂在哪一层）。
func _all_controls() -> Dictionary:
	var d := {}
	_collect(get_tree().root, d)
	return d

func _collect(n: Node, d: Dictionary) -> void:
	if n is Control and n.is_inside_tree():
		d[n.get_instance_id()] = n
	for c in n.get_children():
		_collect(c, d)

func _report_new_nodes(known: Dictionary) -> void:
	var found := 0
	for id in _all_controls():
		if known.has(id):
			continue
		var fresh := _find_by_id(get_tree().root, id)
		if fresh == null:
			continue
		found += 1
		print("[DragProbe] ⚠ 新增 Control：path=%s class=%s pos=%s size=%s top_level=%s" % [
			fresh.get_path(), fresh.get_class(), str(fresh.global_position), str(fresh.size),
			str(fresh.top_level)])
	print("[DragProbe] 全树新增 Control 数=%d" % found)

func _find_by_id(n: Node, id: int) -> Control:
	if n.get_instance_id() == id:
		return n as Control
	for c in n.get_children():
		var r := _find_by_id(c, id)
		if r != null:
			return r
	return null

## 取当前拖拽幽灵（挂在 UI/DragLayer 下）。
func _find_ghost(main: Node) -> Control:
	var layer := main.get_node_or_null("UI/DragLayer")
	if layer == null:
		return null
	return layer.get_node_or_null("DragGhost") as Control

## 打印 UI 层（CanvasLayer）与货郎面板的层级信息，作为对照。
func _report_ui_layer(main: Node) -> void:
	var ui: CanvasLayer = main.get_node("UI")
	print("[DragProbe] UI 层：CanvasLayer layer=%d 子节点=%s" % [
		ui.layer, str(ui.get_children().map(func(n): return n.name))])
	var shop: Control = main.get_node("UI/ShopPanel")
	print("[DragProbe] 货郎面板：visible=%s z_index=%d 根 mouse_filter=%d" % [
		str(shop.visible), shop.z_index, shop.mouse_filter])

# ---- 鼠标输入注入 ----

func _send_move(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)

func _send_press(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = MOUSE_BUTTON_LEFT
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.pressed = true
	Input.parse_input_event(e)

func _send_release(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	Input.parse_input_event(e)

func _equip(item_id: String, inst_id: String, quality: String, base: Dictionary) -> Dictionary:
	return {
		"kind": "equip", "itemId": item_id, "instanceId": inst_id,
		"quality": quality, "level": 1,
		"baseAttrs": base, "affixes": [], "pctAttrs": [],
		"star": 0, "count": 1,
	}
