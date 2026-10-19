class_name FloatingWindow
extends CenterContainer
## 四个常驻面板共用的标题栏拖动、置顶和窗口边界约束。

const PEERS := ["inventory", "character", "skill", "mount"]

var owner_panel: Control
var panel_box: PanelContainer
var header: Control
## 内容区滚动容器（F-P2-3）：由面板在构建后注入；内容超出逻辑视口时由滚动条承载。
var content_scroll: ScrollContainer = null
var origin := Vector2(0.5, 0.5)
var _placed := false
var _user_moved := false
var _dragging := false
var _drag_offset := Vector2.ZERO
var _docked := false
var _dock_left := 0.0
var _dock_right := 1.0
var _dock_top := 0.0
var _dock_bottom := 1.0
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

## 注入内容区滚动容器（F-P2-3）并重算布局；未超出可见区时布局与不加滚动完全一致。
func set_content_scroll(scroll: ScrollContainer) -> void:
	content_scroll = scroll
	_layout.call_deferred()

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

func set_docked(active: bool, left: float = 0.0, right: float = 1.0,
		top: float = 0.0, bottom: float = 1.0) -> void:
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
	_dock_top = top
	_dock_bottom = bottom
	_layout()

func _layout() -> void:
	if owner_panel == null or panel_box == null:
		return
	if _docked:
		position = Vector2(owner_panel.size.x * _dock_left, owner_panel.size.y * _dock_top)
		size = Vector2(owner_panel.size.x * (_dock_right - _dock_left),
			owner_panel.size.y * (_dock_bottom - _dock_top))
		fit_content(size, panel_box, content_scroll)
		return
	fit_content(owner_panel.size, panel_box, content_scroll)
	size = panel_box.get_combined_minimum_size()
	if not _placed or not _user_moved:
		position = (owner_panel.size - size) * origin
		_placed = true
	else:
		position = _floating_position
	_clamp()

## F-P2-3：把内容区尺寸收敛到 `available` 之内（CenterContainer 会强制面板本体等于最小尺寸）。
##   未超出可用区时 `wanted` 恰为内容自然最小尺寸 ⇒ 布局与「不加滚动」逐像素一致；
##   超出时把最小尺寸压到可用空间，其余交给内容滚动条承载，保证含关闭键的标题行仍留在可见区。
## 迭代 4 次以收敛：首轮父容器最小尺寸里还含「内容滚动条占位 0」的旧值，一次算不准。
static func fit_content(available: Vector2, box: Control, scroll: ScrollContainer) -> void:
	if box == null or scroll == null or scroll.get_child_count() == 0:
		return
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var inner := scroll.get_child(0) as Control
	if inner == null:
		return
	var natural := inner.get_combined_minimum_size()
	var bar := scroll.get_v_scroll_bar().get_combined_minimum_size().x
	for _i in range(4):
		var overhead := box.get_combined_minimum_size() - scroll.custom_minimum_size
		var room := Vector2(maxf(0.0, available.x - overhead.x), maxf(0.0, available.y - overhead.y))
		var height := minf(natural.y, room.y)
		var width := minf(natural.x, room.x)
		# 纵向出现滚动条后会扣减内容宽度，预留同宽避免文字被挤到横向滚动。
		if height < natural.y - 0.5:
			width = minf(natural.x + bar, room.x)
		var wanted := Vector2(width, height)
		if scroll.custom_minimum_size.is_equal_approx(wanted):
			return
		scroll.custom_minimum_size = wanted

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
