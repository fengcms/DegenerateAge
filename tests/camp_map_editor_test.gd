extends Node
## 营地可视化编辑器契约测试：加载、整体平移、道路、地面笔刷、碰撞顶点和撤销重做。
## 不保存草稿、不写正式地图，也不触碰玩家存档。

const DOCUMENT := preload("res://addons/camp_map_editor/camp_map_document.gd")
const PANEL := preload("res://addons/camp_map_editor/camp_map_panel.gd")

## 在隔离场景内实例化真实编辑页并验证数据模型与当前营地一致。
func _ready() -> void:
	var editor := PANEL.new()
	add_child(editor)
	await get_tree().process_frame
	editor._set_ground_mode()
	var edit_canvas: Control = editor.canvas
	assert(edit_canvas.clip_contents, "画布绘制未裁切，平移后会覆盖顶部工具栏")
	var paint_screen: Vector2 = edit_canvas._origin() + Vector2(1 * 128 + 64, 5 * 128 + 64) * edit_canvas._scale_value()
	_send_mouse_button(edit_canvas, paint_screen, true)
	_send_mouse_button(edit_canvas, paint_screen, false)
	assert(editor.document.ground_patch_at(Vector2i(1, 5)) == "grass",
		"画布左键点涂没有写入地面格")
	editor._select_object("blacksmith")
	editor._set_collision_mode()
	var before_canvas_vertex: Vector2 = editor.document.footprint("blacksmith")[0]
	var handle_screen: Vector2 = edit_canvas._origin() + before_canvas_vertex * edit_canvas._scale_value()
	_send_mouse_button(edit_canvas, handle_screen, true)
	var move_event := InputEventMouseMotion.new()
	move_event.position = handle_screen + Vector2(8, 4) * edit_canvas._scale_value()
	move_event.relative = move_event.position - handle_screen
	edit_canvas._gui_input(move_event)
	_send_mouse_button(edit_canvas, move_event.position, false)
	assert(editor.document.footprint("blacksmith")[0] == before_canvas_vertex + Vector2(8, 4),
		"画布碰撞顶点拖拽没有更新真实轮廓")
	# 点击贴近蓝色美术边框的碰撞线时，应先命中碰撞，再允许直接加点。
	edit_canvas.selected_id = ""
	var house_points: PackedVector2Array = editor.document.footprint("blacksmith")
	var edge_midpoint := (house_points[1] + house_points[2]) * 0.5
	var edge_screen: Vector2 = edit_canvas._origin() + edge_midpoint * edit_canvas._scale_value()
	_send_mouse_button(edit_canvas, edge_screen, true, true)
	_send_mouse_button(edit_canvas, edge_screen, false, true)
	assert(edit_canvas.selected_id == "blacksmith"
		and editor.document.footprint("blacksmith").size() == house_points.size() + 1,
		"未选中物件时，Shift 点击贴近美术边框的碰撞线没有添加顶点")
	# 靠近旧顶点的 Shift 点击也要优先落在线段上，不被普通顶点拖拽抢走。
	var point_count: int = editor.document.footprint("blacksmith").size()
	var near_vertex := house_points[0].lerp(house_points[1], 0.03)
	var near_screen: Vector2 = edit_canvas._origin() + near_vertex * edit_canvas._scale_value()
	_send_mouse_button(edit_canvas, near_screen, true, true)
	_send_mouse_button(edit_canvas, near_screen, false, true)
	assert(editor.document.footprint("blacksmith").size() == point_count + 1,
		"Shift 点击顶点附近线段时仍被顶点命中抢占")
	# 空格加左键平移应只改变画布位移，不能改动当前碰撞文档。
	var before_pan: Vector2 = edit_canvas.pan
	var before_pan_polygon: PackedVector2Array = editor.document.footprint("blacksmith")
	var space_down := InputEventKey.new()
	space_down.keycode = KEY_SPACE
	space_down.pressed = true
	edit_canvas._input(space_down)
	_send_mouse_button(edit_canvas, edge_screen, true)
	var pan_motion := InputEventMouseMotion.new()
	pan_motion.position = edge_screen + Vector2(70, 35)
	pan_motion.relative = Vector2(70, 35)
	edit_canvas._gui_input(pan_motion)
	_send_mouse_button(edit_canvas, pan_motion.position, false)
	var space_up := InputEventKey.new()
	space_up.keycode = KEY_SPACE
	space_up.pressed = false
	edit_canvas._input(space_up)
	assert(edit_canvas.pan == before_pan + Vector2(70, 35), "空格＋左键拖动没有平移画布")
	assert(editor.document.footprint("blacksmith") == before_pan_polygon,
		"平移画布时错误修改了碰撞顶点")
	var doc := DOCUMENT.new()
	var issue: String = doc.open()
	assert(issue.is_empty(), "营地正式数据不能在编辑器打开：%s" % issue)
	assert(doc.manifest["objects"].size() == 11, "编辑器整体物件清单不完整")
	var old_rect: Rect2 = doc.art_rect("blacksmith")
	var old_footprint: PackedVector2Array = doc.footprint("blacksmith")
	doc.begin_change()
	doc.move_object("blacksmith", Vector2i(8, 4))
	doc.finish_change()
	assert(doc.art_rect("blacksmith").position == old_rect.position + Vector2(8, 4),
		"整体美术没有随拖动移动")
	assert(doc.footprint("blacksmith")[0] == old_footprint[0] + Vector2(8, 4),
		"整体碰撞没有随拖动移动")
	assert(doc.validate().is_empty(), "合法平移被错误拒绝")
	assert(doc.undo() and doc.art_rect("blacksmith") == old_rect, "撤销没有恢复美术位置")
	assert(doc.redo() and doc.art_rect("blacksmith").position == old_rect.position + Vector2(8, 4),
		"重做没有恢复平移")
	var fence_rect: Rect2 = doc.art_rect("training_north")
	var fence_polygon: PackedVector2Array = doc.footprint("training_north")
	doc.begin_change()
	doc.move_object("training_north", Vector2i(5, 3))
	doc.finish_change()
	assert(doc.art_rect("training_north").position == fence_rect.position + Vector2(5, 3)
		and doc.footprint("training_north")[0] == fence_polygon[0] + Vector2(5, 3),
		"围栏美术与整体碰撞未同步")
	assert(doc.undo(), "围栏平移无法撤销")
	doc.begin_change()
	var old_point: Array = doc.layout["main_road"][1].duplicate()
	doc.move_road_point(-1, 1, Vector2i(140, 430))
	doc.finish_change()
	assert(doc.layout["main_road"][1] == [140, 430], "道路控制点没有更新")
	assert(doc.undo() and doc.layout["main_road"][1] == old_point, "道路撤销失败")
	var original_house: PackedVector2Array = doc.footprint("blacksmith")
	var house_art: Rect2 = doc.art_rect("blacksmith")
	doc.begin_change()
	doc.move_collision_vertex("blacksmith", 0, Vector2i(original_house[0]) + Vector2i(8, 4))
	doc.finish_change()
	assert(doc.footprint("blacksmith")[0] == original_house[0] + Vector2(8, 4),
		"房屋碰撞顶点未移动")
	assert(doc.art_rect("blacksmith") == house_art, "编辑碰撞不应拉伸房屋美术")
	assert(doc.validate().is_empty(), "合法的房屋碰撞编辑被拒绝")
	assert(doc.undo() and doc.footprint("blacksmith") == original_house, "碰撞编辑无法撤销")
	doc.begin_change()
	var midpoint := Vector2i((original_house[0] + original_house[1]) * 0.5)
	var added: int = doc.insert_collision_vertex("blacksmith", 0, midpoint)
	doc.finish_change()
	assert(added == 1 and doc.footprint("blacksmith").size() == original_house.size() + 1,
		"无法在房屋碰撞边插入顶点")
	doc.begin_change()
	assert(doc.remove_collision_vertex("blacksmith", added), "无法删除房屋碰撞顶点")
	doc.finish_change()
	assert(doc.footprint("blacksmith") == original_house, "删除顶点后轮廓没有复原")
	var fence_art := doc.art_rect("training_north")
	var fence_origin: Vector2 = doc.footprint("training_north")[0]
	doc.begin_change()
	## 目标点从当前轮廓推导，不写死坐标：围栏位置会随美术调整整体平移（`46fbd6c2` 就把
	## `training_north` 从 444,529 挪到 450,519），写死会让「合法编辑」变成「与西栅栏交叉」。
	doc.move_collision_vertex("training_north", 0, Vector2i(fence_origin) + Vector2i(0, -4))
	doc.finish_change()
	assert(doc.art_rect("training_north") == fence_art, "围栏碰撞编辑不应移动围栏美术")
	assert(doc.validate().is_empty(), "合法的围栏碰撞编辑被拒绝")
	assert(doc.undo(), "围栏碰撞编辑无法撤销")
	doc.begin_change()
	doc.set_ground_patch(Vector2i(3, 2), "grass")
	doc.set_ground_patch(Vector2i(4, 2), "pebbles")
	doc.finish_change()
	assert(doc.ground_patch_at(Vector2i(3, 2)) == "grass"
		and doc.ground_patch_at(Vector2i(4, 2)) == "pebbles", "地面笔刷未按格保存")
	assert(doc.undo() and doc.ground_patch_at(Vector2i(3, 2)).is_empty(), "地面笔刷无法撤销")
	assert(doc.redo() and doc.ground_patch_at(Vector2i(4, 2)) == "pebbles", "地面笔刷无法重做")
	doc.begin_change()
	doc.set_ground_patch(Vector2i(4, 2), "")
	doc.finish_change()
	assert(doc.ground_patch_at(Vector2i(4, 2)).is_empty(), "擦除地面覆盖后没有恢复原纹理")
	assert(doc.validate().is_empty(), "合法的地面笔刷布局被拒绝")
	assert(doc.save_draft().is_empty(), "编辑草稿无法保存")
	var envelope: Variant = JSON.parse_string(FileAccess.get_file_as_string(doc.DRAFT_PATH))
	assert(envelope is Dictionary and String(envelope.get("base_hash", "")).length() == 64,
		"草稿必须记录正式布局的 SHA-256 版本")
	assert(envelope["layout"].get("ground_patches", []).size() == 1,
		"地面笔刷没有进入独立草稿")
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(doc.DRAFT_PATH)) == OK,
		"隔离测试草稿清理失败")
	if DisplayServer.get_name() != "headless":
		for _frame in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("/tmp/camp_map_editor_ui.png") == OK,
			"编辑器实际窗口截图失败")
		editor._set_ground_mode()
		for _frame in range(2):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("/tmp/camp_map_editor_ground_ui.png") == OK,
			"地面笔刷界面截图失败")
		editor._select_object("blacksmith")
		editor._set_collision_mode()
		for _frame in range(2):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("/tmp/camp_map_editor_collision_ui.png") == OK,
			"碰撞顶点界面截图失败")
		edit_canvas.pan = Vector2(0, -500)
		edit_canvas.queue_redraw()
		for _frame in range(2):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("/tmp/camp_map_editor_pan_ui.png") == OK,
			"大幅平移后界面截图失败")
	## 成功标记必须**独占行尾**：`run_isolated_tests.py` 只认行尾形态（防「正文裸含 PASS」误判），
	## 写成 `PASS · 说明` 会被判成「未输出完成标记」。
	print("[CampMapEditorTest] PASS")
	print("[CampMapEditorTest] 覆盖：营地整体物件、道路、地面笔刷和碰撞顶点编辑及撤销重做")
	get_tree().quit()

## 向画布投递本地鼠标按放事件，验证实际 `_gui_input` 模式分发。
func _send_mouse_button(target: Control, position: Vector2, pressed: bool, shift_pressed: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	target._gui_input(event)
