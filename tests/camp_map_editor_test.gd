extends Node
## 营地可视化编辑器契约测试：只读加载、整体平移、道路节点和撤销重做。
## 不保存草稿、不写正式地图，也不触碰玩家存档。

const DOCUMENT := preload("res://addons/camp_map_editor/camp_map_document.gd")
const PANEL := preload("res://addons/camp_map_editor/camp_map_panel.gd")

## 在隔离场景内实例化真实编辑页并验证数据模型与当前营地一致。
func _ready() -> void:
	var editor := PANEL.new()
	add_child(editor)
	await get_tree().process_frame
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
	assert(doc.save_draft().is_empty(), "编辑草稿无法保存")
	var envelope: Variant = JSON.parse_string(FileAccess.get_file_as_string(doc.DRAFT_PATH))
	assert(envelope is Dictionary and String(envelope.get("base_hash", "")).length() == 64,
		"草稿必须记录正式布局的 SHA-256 版本")
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(doc.DRAFT_PATH)) == OK,
		"隔离测试草稿清理失败")
	if DisplayServer.get_name() != "headless":
		for _frame in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("/tmp/camp_map_editor_ui.png") == OK,
			"编辑器实际窗口截图失败")
	print("[CampMapEditorTest] PASS · 当前营地加载、整体美术与碰撞联动、道路编辑和撤销重做")
	get_tree().quit()
