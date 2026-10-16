@tool
extends Control
## 营地地图编辑页：提供拖放模式、撤销重做、草稿保存与显式应用。
## 左侧画布复用正式运行贴图；右侧只列可编辑的既有整体实体。

const DOCUMENT_SCRIPT := preload("res://addons/camp_map_editor/camp_map_document.gd")
const CANVAS_SCRIPT := preload("res://addons/camp_map_editor/camp_map_canvas.gd")

var document: RefCounted
var canvas: Control
var status_label: Label
var selected_label: Label

## 装配主界面并加载当前营地；若草稿与正式源一致则继续草稿。
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	document = DOCUMENT_SCRIPT.new()
	var issue: String = document.open()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)
	_add_button(toolbar, "移动整体物件", _set_object_mode)
	_add_button(toolbar, "调整道路节点", _set_road_mode)
	_add_button(toolbar, "撤销", _undo)
	_add_button(toolbar, "重做", _redo)
	_add_button(toolbar, "保存草稿", _save_draft)
	_add_button(toolbar, "应用到游戏", _apply_to_game)
	_add_button(toolbar, "重新载入", _reload)
	var collision := CheckButton.new()
	collision.text = "碰撞轮廓"
	collision.button_pressed = true
	collision.toggled.connect(_toggle_collision)
	toolbar.add_child(collision)
	var npc := CheckButton.new()
	npc.text = "NPC 落点"
	npc.button_pressed = true
	npc.toggled.connect(_toggle_targets)
	toolbar.add_child(npc)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	canvas = CANVAS_SCRIPT.new()
	canvas.custom_minimum_size = Vector2(680, 470)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.document = document
	canvas.selection_changed.connect(_selection_changed)
	canvas.document_changed.connect(_document_changed)
	split.add_child(canvas)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 180
	split.add_child(sidebar)
	var heading := Label.new()
	heading.text = "现有整体物件"
	sidebar.add_child(heading)
	for item: Dictionary in document.layout.get("entities", []):
		var id := String(item["id"])
		_add_button(sidebar, "%s · %s" % [String(item.get("label", id)), id],
			func() -> void: _select_object(id))
	for item: Dictionary in document.layout.get("fences", []):
		var id := String(item["id"])
		_add_button(sidebar, id, func() -> void: _select_object(id))
	selected_label = Label.new()
	selected_label.text = "点选画面中的物件或道路节点"
	selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(selected_label)
	var hint := Label.new()
	hint.text = "左键拖动；滚轮缩放；中键平移。\n保存草稿不会修改游戏。\n应用前自动检查 NPC 与通路。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(hint)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)
	_set_status(issue if not issue.is_empty() else "已载入营地。先拖动整体物件或道路节点，再保存草稿。")

## 创建一个可复用的编辑器按钮并绑定单一动作。
func _add_button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)

## 切到整体物件模式，所有平移同时修改该对象的脚底碰撞。
func _set_object_mode() -> void:
	canvas.mode = "object"
	canvas.queue_redraw()
	_set_status("整体物件模式：拖动美术、碰撞和前沿锚点。")

## 切到道路模式；青色节点可拖，真实道路贴图在应用后重建。
func _set_road_mode() -> void:
	canvas.mode = "road"
	canvas.queue_redraw()
	_set_status("道路模式：拖动青色控制点；正式道路贴图在应用后重建。")

## 撤销最近一次完整拖动，刷新画面而不自动保存。
func _undo() -> void:
	if document.undo():
		canvas.queue_redraw()
		_set_status("已撤销一次编辑。")

## 恢复最近一次被撤销的拖动，刷新画面而不自动保存。
func _redo() -> void:
	if document.redo():
		canvas.queue_redraw()
		_set_status("已重做一次编辑。")

## 保存项目内独立草稿；不更新正式营地运行数据。
func _save_draft() -> void:
	var issue: String = document.save_draft()
	_set_status(issue if not issue.is_empty() else "草稿已保存。游戏地图尚未修改。")

## 经 Python 审核后应用草稿并重建白盒与贴图；失败保留现有游戏地图。
func _apply_to_game() -> void:
	var issue: String = document.save_draft()
	if not issue.is_empty():
		_set_status(issue)
		return
	var script := ProjectSettings.globalize_path("res://tools/apply_camp_map_editor.py")
	var draft := ProjectSettings.globalize_path(document.DRAFT_PATH)
	var output: Array = []
	var code := OS.execute("python3", [script, draft], output, true)
	if code != 0:
		_set_status("应用失败，正式地图未更新：\n" + "\n".join(output))
		return
	EditorInterface.get_resource_filesystem().scan()
	var reopen: String = document.open()
	canvas.reload_textures()
	_set_status(reopen if not reopen.is_empty() else "已应用到游戏。重新进入营地即可看到改动；请实走检查。")

## 放弃内存中尚未保存的编辑并重新打开正式地图或兼容草稿。
func _reload() -> void:
	var issue: String = document.open()
	canvas.queue_redraw()
	_set_status(issue if not issue.is_empty() else "已重新载入营地及兼容草稿。")

## 显示或隐藏画布上的整体碰撞多边形，不改变实际通行。
func _toggle_collision(visible: bool) -> void:
	canvas.show_collision = visible
	canvas.queue_redraw()

## 显示或隐藏正式地图中的 NPC 位置标记，不改变 NPC 数据。
func _toggle_targets(visible: bool) -> void:
	canvas.show_targets = visible
	canvas.queue_redraw()

## 从侧栏选中一个既有对象；随后可在画布中直接拖动。
func _select_object(id: String) -> void:
	canvas.mode = "object"
	canvas.selected_id = id
	canvas.queue_redraw()
	_selection_changed(id)

## 呈现当前选中对象，提醒用户道路和整体物件分别操作。
func _selection_changed(id: String) -> void:
	selected_label.text = "当前选择：%s" % id if not id.is_empty() else "未选中对象"

## 在拖动结束后显示草稿待保存状态和几何校验结果。
func _document_changed() -> void:
	var issue: String = document.validate()
	_set_status(issue if not issue.is_empty() else "有未保存的编辑。保存草稿后可应用到游戏。")

## 用状态栏报告操作与失败原因，不依赖弹窗中断编辑。
func _set_status(message: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = message
