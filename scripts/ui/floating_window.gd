class_name FloatingWindow
extends CenterContainer
## 四个常驻面板共用的标题栏拖动、置顶和窗口边界约束。

const PEERS := ["inventory", "character", "skill", "mount"]

var owner_panel: Control
var panel_box: PanelContainer
var header: Control
var origin := Vector2(0.5, 0.5)
var _placed := false
var _user_moved := false
var _dragging := false
var _drag_offset := Vector2.ZERO
var _docked := false
var _dock_left := 0.0
var _dock_right := 1.0
var _floating_position := Vector2.ZERO

func setup(host: Control, box: PanelContainer, bar: Control, start: Vector2) -> void:
	owner_panel = host
	panel_box = box
	header = bar
	origin = start
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in header.get_children():
		if child is Control and not child is Button:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.gui_input.connect(_on_header_input)
	panel_box.gui_input.connect(_on_box_input)
	# 动态列表刷新会先排入旧行的 queue_free；待最小尺寸稳定后重新夹紧浮窗。
	panel_box.minimum_size_changed.connect(func() -> void: _layout.call_deferred())
	owner_panel.resized.connect(_layout)
	_layout.call_deferred()

func show_window() -> void:
	_layout()
	bring_forward()

func bring_forward() -> void:
	var others: Array[Control] = []
	for sibling in owner_panel.get_parent().get_children():
		if sibling is Control and sibling != owner_panel and sibling.visible \
				and String(sibling.name).to_lower().replace("panel", "") in PEERS:
			others.append(sibling)
	others.sort_custom(func(a: Control, b: Control) -> bool: return a.z_index < b.z_index)
	for i in range(others.size()):
		others[i].z_index = i + 1
	owner_panel.z_index = others.size() + 1

func is_top_window() -> bool:
	for sibling in owner_panel.get_parent().get_children():
		if sibling is Control and sibling != owner_panel and sibling.visible \
				and String(sibling.name).to_lower().replace("panel", "") in PEERS \
				and sibling.z_index > owner_panel.z_index:
			return false
	return true

func set_docked(active: bool, left: float = 0.0, right: float = 1.0) -> void:
	if active and not _docked:
		_floating_position = position
	elif not active and _docked:
		# 离开并列布局时，以玩家实际看到的面板位置继续显示。
		_floating_position = position + panel_box.position
		_user_moved = true
	_docked = active
	_dock_left = left
	_dock_right = right
	_layout()

func _layout() -> void:
	if owner_panel == null or panel_box == null:
		return
	if _docked:
		position = Vector2(owner_panel.size.x * _dock_left, 0.0)
		size = Vector2(owner_panel.size.x * (_dock_right - _dock_left), owner_panel.size.y)
		return
	size = panel_box.get_combined_minimum_size()
	if not _placed or not _user_moved:
		position = (owner_panel.size - size) * origin
		_placed = true
	else:
		position = _floating_position
	_clamp()

func _clamp() -> void:
	position = Vector2(clampf(position.x, 0.0, maxf(0.0, owner_panel.size.x - size.x)),
		clampf(position.y, 0.0, maxf(0.0, owner_panel.size.y - size.y)))
	_floating_position = position

func _on_box_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		bring_forward()

func _on_header_input(event: InputEvent) -> void:
	if _docked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			bring_forward()
			_dragging = true
			_user_moved = true
			_drag_offset = owner_panel.get_local_mouse_position() - position
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		position = owner_panel.get_local_mouse_position() - _drag_offset
		_clamp()
