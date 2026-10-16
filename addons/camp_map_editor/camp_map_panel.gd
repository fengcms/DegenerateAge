@tool
extends Control
## 营地地图编辑页：提供地面笔刷、整体物件、碰撞轮廓和道路编辑，
## 统一使用撤销重做、草稿保存与显式应用；右侧列出既有整体实体。

const DOCUMENT_SCRIPT := preload("res://addons/camp_map_editor/camp_map_document.gd")
const CANVAS_SCRIPT := preload("res://addons/camp_map_editor/camp_map_canvas.gd")

var document: RefCounted
var canvas: Control
var status_label: Label
var selected_label: Label
var palette_panel: VBoxContainer

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
	_add_button(toolbar, "编辑碰撞", _set_collision_mode)
	_add_button(toolbar, "绘制地面", _set_ground_mode)
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
	sidebar.custom_minimum_size.x = 220
	split.add_child(sidebar)
	palette_panel = VBoxContainer.new()
	palette_panel.visible = false
	sidebar.add_child(palette_panel)
	var palette_label := Label.new()
	palette_label.text = "地面笔刷 · 128×128 格"
	palette_panel.add_child(palette_label)
	var palette_picker := OptionButton.new()
	palette_picker.add_item("擦除覆盖 / 原地面")
	for tile: Dictionary in document.palette.get("tiles", []):
		palette_picker.add_item(String(tile["label"]))
		var texture := load(String(tile["path"])) as Texture2D
		if texture != null:
			var preview := texture.get_image()
			preview.resize(32, 32, Image.INTERPOLATE_NEAREST)
			palette_picker.set_item_icon(palette_picker.item_count - 1, ImageTexture.create_from_image(preview))
	palette_picker.selected = 1
	palette_picker.item_selected.connect(_select_ground_brush)
	palette_panel.add_child(palette_picker)
	var palette_hint := Label.new()
	palette_hint.text = "左键点涂或拖涂；选择擦除可恢复原地纹。\n笔刷仅改外观，不修改通行。"
	palette_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	palette_panel.add_child(palette_hint)
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
	hint.text = "左键拖动；滚轮缩放；中键平移。\n碰撞模式：拖顶点，Shift 点边加顶点，右键顶点删除。\n保存草稿不会修改游戏；应用前检查 NPC 与通路。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(hint)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)
	_set_status(issue if not issue.is_empty() else "已载入营地。可绘制地面、移动整体物件或编辑碰撞，再保存草稿。")

## 创建一个可复用的编辑器按钮并绑定单一动作。
func _add_button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)

## 切到整体物件模式，所有平移同时修改该对象的脚底碰撞。
func _set_object_mode() -> void:
	canvas.mode = "object"
	palette_panel.visible = false
	canvas.queue_redraw()
	_set_status("整体物件模式：拖动美术、碰撞和前沿锚点。")

## 切到碰撞模式；顶点调整只改变实际阻挡轮廓，不改变贴图矩形。
func _set_collision_mode() -> void:
	canvas.mode = "collision"
	palette_panel.visible = false
	canvas.queue_redraw()
	_set_status("碰撞模式：先选房屋等整体物件，再拖动橙色顶点；Shift 点边加点，右键点删点。")

## 切到地面模式；按当前笔刷在画布格上点涂或连续拖涂。
func _set_ground_mode() -> void:
	canvas.mode = "ground"
	canvas.selected_id = ""
	_selection_changed("")
	palette_panel.visible = true
	canvas.queue_redraw()
	_set_status("地面模式：在右侧选择笔刷，左键点涂或拖涂；擦除会恢复原地纹。")

## 将侧栏选中的笔刷 ID 交给画布；索引 0 是擦除覆盖层。
func _select_ground_brush(index: int) -> void:
	canvas.brush_id = "" if index == 0 else String(document.palette["tiles"][index - 1]["id"])
	_set_status("当前地面笔刷：%s" % ("擦除覆盖" if index == 0 else document.palette["tiles"][index - 1]["label"]))

## 切到道路模式；青色节点可拖，真实道路贴图在应用后重建。
func _set_road_mode() -> void:
	canvas.mode = "road"
	canvas.selected_id = ""
	_selection_changed("")
	palette_panel.visible = false
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
	if canvas.mode != "collision":
		canvas.mode = "object"
		palette_panel.visible = false
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
