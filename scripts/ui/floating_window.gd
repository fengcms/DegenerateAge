class_name FloatingWindow
extends CenterContainer
## 浮窗共用的标题栏拖动、窗口边界约束，以及**统一浮窗层级服务**（工程 74 §4 P1）。
##
## 层级服务的唯一事实源是「分组自登记」，不再把面板名写死成一份名单：
##   - `GROUP`：可被点击置前的浮窗面板；`setup()` 会为宿主自动登记，新面板零成本纳入；
##   - `TOP_LAYER`：必须始终位于浮窗之上的层级锚点（Toast / 拖拽幽灵 / 模态确认罩 / 模态面板），
##     与 `scenes/Main.tscn` 的 UI 子节点名一一对应，只当天花板，本身不参与置前。
## 置前 = `move_child` 改兄弟节点顺序（Godot 的 GUI 命中看树序，不看 z_index），
## 并把可见浮窗的 z_index 按树序重排为 1..N，保证视觉序与鼠标命中序同源。

const GROUP := "floating_window"
const TOP_LAYER := ["FlowFeedback", "DragLayer", "EquipmentConfirmation",
	"SettingsPanel", "MenuPanel", "SavePanel", "DeathPanel"]

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
var _pinned := false
var _pinned_rect := Rect2()
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
	owner_panel.add_to_group(GROUP)
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
	raise_panel(owner_panel)

func is_top_window() -> bool:
	return is_top_panel(owner_panel)

# ---- 统一浮窗层级服务（工程 74 §4 P1）----

## 把 `panel` 抬到「层级锚点之下、其余可见浮窗之上」；未登记的面板在此自动纳入浮窗组。
static func raise_panel(panel: Control) -> void:
	if panel == null or not is_instance_valid(panel) or panel.get_parent() == null:
		return
	var parent := panel.get_parent()
	panel.add_to_group(GROUP)
	var ceiling := _ceiling_index(panel)
	# 锚点不存在时退化为「浮窗层末尾」；存在时移到锚点之前（自身已越过锚点则贴到锚点前一位）。
	var target := parent.get_child_count() - 1 if ceiling < 0 \
		else (ceiling - 1 if panel.get_index() < ceiling else ceiling)
	if panel.get_index() != target:
		parent.move_child(panel, target)
	_sync_z_order(parent)

## `panel` 是否已是可见浮窗里最靠前的那扇（Esc 关闭目标与视觉 / 鼠标命中同源）。
static func is_top_panel(panel: Control) -> bool:
	if panel == null or not is_instance_valid(panel) or panel.get_parent() == null:
		return true
	for sibling in panel.get_parent().get_children():
		if sibling is Control and sibling != panel and sibling.visible \
				and sibling.is_in_group(GROUP) and sibling.z_index > panel.z_index:
			return false
	return true

## 给非 `FloatingWindow` 宿主的面板挂上点击置前（铁匠系 / 货郎等裸 `CenterContainer` 面板）。
static func enable_click_to_front(panel: Control, box: Control) -> void:
	panel.add_to_group(GROUP)
	box.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			raise_panel(panel))

## 层级锚点里最靠前的那个下标（改树序**前**的位置）；无锚点时为 -1。
static func _ceiling_index(panel: Control) -> int:
	var ceiling := -1
	for sibling in panel.get_parent().get_children():
		if not sibling is Control or sibling == panel or not sibling.visible:
			continue
		if String(sibling.name) in TOP_LAYER:
			ceiling = sibling.get_index() if ceiling < 0 else mini(ceiling, sibling.get_index())
	return ceiling

## 可见浮窗按树序重排 z_index，保证「看到的」与「点到的」是同一扇窗。
static func _sync_z_order(parent: Node) -> void:
	var rank := 0
	for sibling in parent.get_children():
		if sibling is Control and sibling.visible and sibling.is_in_group(GROUP):
			rank += 1
			sibling.z_index = rank

## 指定「未被玩家拖动过」时的默认落点（按可用空间比例 0..1）。并排会话用它把窗口放到
## 伙伴旁边；玩家拖过之后（`_user_moved`）以实际位置为准，不再回落到默认落点。
## `reset` 为真时把「玩家拖动过」一并清掉（窄屏分区钉住 → 宽屏并排这类重排必须回到默认落点，
## 否则会停在分区时代的旧坐标上）。
func set_origin(start: Vector2, reset := false) -> void:
	origin = start
	if reset:
		_user_moved = false
	_layout()

## 按**逻辑视口绝对坐标**把浮窗钉在固定分区（窄屏分裂布局）：位置与尺寸由调用方给定，
## 不参与拖动、不随内容最小尺寸浮动。与 `set_docked` 的差别：后者的比例是「占父容器多少」，
## 而这里直接吃绝对矩形，便于调用方按逻辑视口一次性算准。
func set_pinned(active: bool, rect := Rect2()) -> void:
	_pinned = active
	if active:
		_docked = false
		_dragging = false
		_pinned_rect = rect
	_user_moved = false
	_layout()

func set_docked(active: bool, left: float = 0.0, right: float = 1.0,
		top: float = 0.0, bottom: float = 1.0) -> void:
	if active:
		_pinned = false
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

## 浮窗的可用空间：常态下就是宿主面板自身的矩形（游戏内面板根控件由界面倍率撑成逻辑视口）。
## 宿主尺寸为 0 时（独立测试里的根控件没有那份尺寸）退回逻辑视口，避免落点与分区被夹成 0 而失真。
func layout_space() -> Vector2:
	if owner_panel == null:
		return Vector2.ZERO
	if owner_panel.size.x > 0.0 and owner_panel.size.y > 0.0:
		return owner_panel.size
	return owner_panel.get_viewport_rect().size / SettingsRuntime.ui_scale_value()

func _layout() -> void:
	if owner_panel == null or panel_box == null:
		return
	var area := layout_space()
	if _pinned:
		position = _pinned_rect.position
		size = _pinned_rect.size
		fit_content(size, panel_box, content_scroll)
		return
	if _docked:
		position = Vector2(area.x * _dock_left, area.y * _dock_top)
		size = Vector2(area.x * (_dock_right - _dock_left),
			area.y * (_dock_bottom - _dock_top))
		fit_content(size, panel_box, content_scroll)
		return
	fit_content(area, panel_box, content_scroll)
	size = panel_box.get_combined_minimum_size()
	if not _placed or not _user_moved:
		position = (area - size) * origin
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
	var area := layout_space()
	position = Vector2(clampf(position.x, 0.0, maxf(0.0, area.x - size.x)),
		clampf(position.y, 0.0, maxf(0.0, area.y - size.y)))
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
