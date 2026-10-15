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
	owner_panel.visibility_changed.connect(func() -> void:
		if not owner_panel.visible:
			_dragging = false)
	_layout.call_deferred()

func show_window() -> void:
	_layout()
	bring_forward()

func bring_forward() -> void:
	var peers: Array[Control] = []
	var last_peer_index := -1
	for sibling in owner_panel.get_parent().get_children():
		if sibling is Control and sibling.visible \
				and String(sibling.name).to_lower().replace("panel", "") in PEERS:
			peers.append(sibling)
			last_peer_index = sibling.get_index()
	# Godot 的 GUI 命中看兄弟节点顺序，不能只提高 z_index。
	# 仅移到最后一个常驻浮窗的位置，避免越过后面的设置/模态层。
	if owner_panel.get_index() != last_peer_index:
		owner_panel.get_parent().move_child(owner_panel, last_peer_index)
	peers.clear()
	for sibling in owner_panel.get_parent().get_children():
		if sibling is Control and sibling.visible \
				and String(sibling.name).to_lower().replace("panel", "") in PEERS:
			peers.append(sibling)
	for i in range(peers.size()):
		peers[i].z_index = i + 1

func is_top_window() -> bool:
	for sibling in owner_panel.get_parent().get_children():
		if sibling is Control and sibling != owner_panel and sibling.visible \
				and String(sibling.name).to_lower().replace("panel", "") in PEERS \
				and sibling.z_index > owner_panel.z_index:
			return false
	return true

func set_docked(active: bool, left: float = 0.0, right: float = 1.0) -> void:
	if active:
		_dragging = false
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
	if event is InputEventMouseButton:
		if event.pressed:
			bring_forward()
		if _docked or event.button_index != MOUSE_BUTTON_LEFT:
			return
		# 标题上沿由外框绘制，但标题 HBox 从内边距之后才开始。
		# 只接管它上方的可见标题带；按钮所在的标题行仍由自身处理。
		var header_top := header.global_position.y - panel_box.global_position.y
		if event.pressed and event.position.y < header_top:
			_start_drag(event)
		elif not event.pressed:
			_dragging = false

func _on_header_input(event: InputEvent) -> void:
	if _docked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			bring_forward()
			_start_drag(event)
		else:
			_dragging = false

func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		_move_drag(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false

func _start_drag(event: InputEventMouse) -> void:
	_dragging = true
	_user_moved = true
	_drag_offset = _owner_mouse_position(event) - position

func _move_drag(event: InputEventMouse) -> void:
	position = _owner_mouse_position(event) - _drag_offset
	_clamp()

func _owner_mouse_position(event: InputEventMouse) -> Vector2:
	return owner_panel.get_global_transform_with_canvas().affine_inverse() * event.global_position
