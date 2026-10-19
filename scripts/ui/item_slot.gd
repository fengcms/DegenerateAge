class_name ItemSlot
extends Button
## 通用物品格子（M1-8 拖拽改造）。
##
## 两种角色（`role`）：
##   ROLE_BAG  —— 背包格：`draggable = true` 时可拖出，载荷携带背包下标与物品实例；
##   ROLE_TRAY —— 出售托盘格：可接收来自背包格的投放；
##   ROLE_WAREHOUSE —— 仓库格：与背包格双向拖放。
##
## 拖拽载荷结构：{ "from": ROLE_BAG 或 ROLE_WAREHOUSE, "index": int, "item": Dictionary }
## 拖动时的跟随视觉由 DragGhost 承载（挂 UI 层最高层；**不用**引擎的拖拽预览，
## 原因见 `_spawn_drag_visual`）。界面本体仍为占位绘制（R5）：格内文字为模板名前 2 字 + 品质色描边。
##
## 为什么单独抽一个控件：Godot 4 的拖放是 Control 的虚方法（_get_drag_data /
## _can_drop_data / _drop_data），必须在脚本里覆写；界面为代码构建，无法给 Button 实例
## 单独挂虚方法，故统一由此类承载拖出与接收两端。

enum { ROLE_BAG, ROLE_TRAY, ROLE_WAREHOUSE, ROLE_EQUIP }

## 背包与仓库双栏共用的格子颜色，避免空格、悬停和品质边框出现两套样式。
const GRID_BORDER := Color(0.30, 0.33, 0.38, 0.95)
const GRID_FILLED := Color("1b282d")
const GRID_EMPTY := Color("142025")
const GRID_HOVER := Color("2b3a3d")
const GRID_TEXT := Color(0.90, 0.92, 0.95)
## 背包装备评分角标三态：可立即穿戴的高分件、等级未达的高分件和无提示。
enum UpgradeBadge { NONE, READY, LEVEL_LOCKED }
const UPGRADE_READY_COLOR := Color("78e5a5")
const UPGRADE_LOCKED_COLOR := Color("aab5bf")

## 目标格收到投放时回传（target_index 为本格下标，payload 见文件头）。
signal item_dropped(tray_index: int, payload: Dictionary)

var role: int = ROLE_BAG
var index: int = -1              # 背包下标（ROLE_BAG）/ 托盘下标（ROLE_TRAY）
var draggable: bool = false      # 是否允许拖出（背包可用物品 / 交易装备 / 仓库存取）
## 状态只影响格内提示，不参与装备穿戴判定或评分计算。
var upgrade_badge_state: UpgradeBadge = UpgradeBadge.NONE:
	set(value):
		upgrade_badge_state = value
		_refresh_upgrade_marker()

## 当前格内物品实例（由面板在刷新时写入）。**赋值即刷新右下角数量角标**（M4-10）。
var item: Dictionary = {}:
	set(value):
		item = value
		_refresh_count()
		_refresh_potion_marker()
		_refresh_favorite_marker()
		_refresh_quality_frame()
		_apply_sample_icon.call_deferred()
		queue_redraw()

## 数量角标（右下角）：仅 `count > 1` 显示 —— 装备 / 单个道具不顶「1」（Q4-A）。
var _count: Label
var _quality_frame: QualityFrameOverlay
var _potion_marker: Label
var _favorite_marker: Label
var _upgrade_marker: Label
var _drag_cover: PanelContainer
var _press_grab_point := Vector2.ZERO
var _press_grab_valid := false

## 空背包格和空仓库格绘制同一低对比定位纹样；不遮挡图标和数量角标。
func _draw() -> void:
	if role not in [ROLE_BAG, ROLE_WAREHOUSE] or not item.is_empty():
		return
	var center := size * 0.5
	var marker := Color("354a50")
	draw_arc(center, 10.0, 0.0, TAU, 24, marker, 1.0)
	draw_line(center + Vector2(-15, 0), center + Vector2(15, 0), marker, 1.0)
	draw_line(center + Vector2(0, -15), center + Vector2(0, 15), marker, 1.0)
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			var corner := center + Vector2(x_sign * 19.0, y_sign * 19.0)
			draw_line(corner, corner - Vector2(x_sign * 8.0, 0), marker, 1.0)
			draw_line(corner, corner - Vector2(0, y_sign * 8.0), marker, 1.0)

## 设置背包类格子的基础字号、尺寸和空槽样式；仓库可传入较小的布局尺寸。
func apply_grid_base(min_size: Vector2) -> void:
	custom_minimum_size = min_size
	clip_text = true
	add_theme_font_size_override("font_size", 13)
	add_theme_color_override("font_color", GRID_TEXT)
	add_theme_color_override("font_hover_color", Color.WHITE)
	add_theme_color_override("font_pressed_color", GRID_TEXT)
	add_theme_color_override("font_focus_color", GRID_TEXT)
	apply_grid_style(GRID_BORDER, false)

## 有品质动画框时隐藏静态描边，避免叠出双框；空格仍保留暗色边框。
func apply_grid_style(border: Color, filled: bool) -> void:
	var bg := GRID_FILLED if filled else GRID_EMPTY
	var painted_border := Color.TRANSPARENT if _quality_frame != null and _quality_frame.visible else border
	add_theme_stylebox_override("normal", _grid_style(bg, painted_border))
	add_theme_stylebox_override("hover", _grid_style(GRID_HOVER, painted_border))
	add_theme_stylebox_override("pressed", _grid_style(bg, painted_border))
	add_theme_stylebox_override("focus", _grid_style(Color.TRANSPARENT, Color.TRANSPARENT))
	add_theme_stylebox_override("disabled", _grid_style(bg, painted_border))

## 生成单个格子状态所用的圆角底板。
func _grid_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style

func _ready() -> void:
	_quality_frame = QualityFrameOverlay.new()
	_quality_frame.name = "QualityFrame"
	add_child(_quality_frame)
	_refresh_quality_frame()
	_count = Label.new()
	_count.set_anchors_preset(Control.PRESET_FULL_RECT)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count.add_theme_font_size_override("font_size", 11)
	_count.add_theme_constant_override("outline_size", 2)
	_count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_count.add_theme_color_override("font_color", Color(0.96, 0.94, 0.85))
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	_refresh_count()
	_potion_marker = Label.new()
	_potion_marker.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_potion_marker.offset_left = 3
	_potion_marker.offset_top = 2
	_potion_marker.add_theme_font_size_override("font_size", 15)
	_potion_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_potion_marker)
	_refresh_potion_marker()
	_favorite_marker = Label.new()
	_favorite_marker.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_favorite_marker.offset_left = 2
	_favorite_marker.offset_top = 0
	_favorite_marker.add_theme_font_size_override("font_size", 16)
	_favorite_marker.add_theme_color_override("font_color", PanelChrome.GOLD_LIGHT)
	_favorite_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_favorite_marker)
	_refresh_favorite_marker()
	_upgrade_marker = Label.new()
	_upgrade_marker.text = "↑"
	_upgrade_marker.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_upgrade_marker.offset_left = -21
	_upgrade_marker.offset_right = -2
	_upgrade_marker.offset_top = 0
	_upgrade_marker.offset_bottom = 22
	_upgrade_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_upgrade_marker.add_theme_font_size_override("font_size", 19)
	_upgrade_marker.add_theme_constant_override("outline_size", 3)
	_upgrade_marker.add_theme_color_override("font_outline_color", Color(0.03, 0.10, 0.06))
	_upgrade_marker.add_theme_color_override("font_color", UPGRADE_READY_COLOR)
	_upgrade_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_upgrade_marker.visible = false
	add_child(_upgrade_marker)
	_refresh_upgrade_marker()
	EventBus.settings_changed.connect(_refresh_potion_marker)
	_drag_cover = PanelContainer.new()
	_drag_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drag_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_cover.visible = false
	var cover_style := StyleBoxFlat.new()
	cover_style.bg_color = Color("1a1c21")
	cover_style.border_color = Color("626a73")
	cover_style.set_border_width_all(1)
	cover_style.set_corner_radius_all(4)
	_drag_cover.add_theme_stylebox_override("panel", cover_style)
	if role == ROLE_EQUIP:
		var empty_label := Label.new()
		empty_label.text = String(Equipment.slot_def(String(get("slot_id"))).get("label", ""))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", get_theme_font_size("font_size"))
		empty_label.add_theme_color_override("font_color", Color("8d959d"))
		empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drag_cover.add_child(empty_label)
	add_child(_drag_cover)
	button_down.connect(func() -> void:
		_press_grab_point = get_local_mouse_position()
		_press_grab_valid = true)
	set_process(false)

## 在装备、等级或格子内容变化时同步箭头颜色与可见性，清除旧状态残留。
func _refresh_upgrade_marker() -> void:
	if _upgrade_marker == null:
		return
	_upgrade_marker.visible = upgrade_badge_state != UpgradeBadge.NONE
	_upgrade_marker.add_theme_color_override("font_color",
		UPGRADE_LOCKED_COLOR if upgrade_badge_state == UpgradeBadge.LEVEL_LOCKED else UPGRADE_READY_COLOR)

func _process(_delta: float) -> void:
	if not get_viewport().gui_is_dragging():
		_drag_cover.visible = false
		_press_grab_valid = false
		set_process(false)

func _refresh_potion_marker() -> void:
	if _potion_marker == null:
		return
	var kind := ItemUtil.potion_kind(String(item.get("itemId", ""))) if String(item.get("kind", "")) == "potion" else ""
	_potion_marker.text = ItemUtil.potion_marker(kind)
	_potion_marker.add_theme_color_override("font_color", ItemUtil.potion_marker_color(kind))

## 收藏装备始终在格内保留金色星标，随实例在背包、仓库和托盘间移动。
func _refresh_favorite_marker() -> void:
	if _favorite_marker == null:
		return
	_favorite_marker.text = "★" if String(item.get("kind", "")) == "equip" and bool(item.get("favorite", false)) else ""

func _refresh_quality_frame() -> void:
	if _quality_frame == null:
		return
	_quality_frame.set_quality(String(item.get("quality", "common")) if String(item.get("kind", "")) == "equip" else "common")

## 依据 `item.count` 刷新角标文本。`_ready` 前被赋值时安全跳过（`_count` 为 null）。
func _refresh_count() -> void:
	if _count == null:
		return
	var n := 0
	if not item.is_empty():
		n = int(item.get("count", 1))
	_count.text = str(n) if n > 1 else ""

# ---- 拖出（ROLE_BAG）----

func _get_drag_data(at_position: Vector2) -> Variant:
	if not [ROLE_BAG, ROLE_WAREHOUSE].has(role) or not draggable or item.is_empty():
		return null
	_spawn_drag_visual(_grab_point(at_position))
	return {"from": role, "index": index, "item": item, "token": Warehouse.item_token(item)}

func _grab_point(fallback: Vector2) -> Vector2:
	return _press_grab_point if _press_grab_valid else fallback

## 拖动时跟随鼠标的视觉反馈（拖拽幽灵）。
## **不用引擎的 set_drag_preview**：预览挂载点由引擎自定（实测 4.7 插到本面板内部），
## 与其它面板同 canvas、同 z_index，绘制顺序由树的先后决定 —— 预览会被排在后面的
## 面板（如货郎面板）整块盖住，玩家看不到拖动的元素；`z_index` 只在同 canvas 内比较，
## 无法跨 canvas 纠正。故改为自绘 DragGhost，显式挂到 UI 层内最高层（组 drag_ghost_layer）。
## 兜底：场景中无该图层时（如独立测试场景）仍走引擎预览，并尽量抬高其 z_index。
## 引擎契约：`_get_drag_data` 内的拖拽态必为真（官方即推荐在此调用 set_drag_preview，
## 其内部同样断言 gui_is_dragging）；无头测试直接取载荷时为假 —— 此时不做任何视觉创建。
func _spawn_drag_visual(grab_point: Vector2) -> void:
	if not get_viewport().gui_is_dragging():
		return
	var layer := get_tree().get_first_node_in_group("drag_ghost_layer")
	if layer != null:
		DragGhost.spawn_slot(layer, self, grab_point)
	else:
		var preview := _make_drag_preview()
		preview.z_index = DragGhost.Z
		set_drag_preview(preview)
	_show_drag_origin()

func _show_drag_origin() -> void:
	_drag_cover.visible = true
	set_process(true)

## 无独立幽灵层时仍使用与源格一致的预览。
func _make_drag_preview() -> Control:
	return DragGhost.slot_copy(self)

# ---- 接收（ROLE_TRAY）----

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var source := int((data as Dictionary).get("from", -1))
	return (role == ROLE_TRAY and source == ROLE_BAG) \
		or (role == ROLE_WAREHOUSE and source == ROLE_BAG) \
		or (role == ROLE_BAG and source == ROLE_BAG) \
		or (role == ROLE_BAG and source == ROLE_WAREHOUSE) \
		or (role == ROLE_BAG and source == ROLE_EQUIP)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(index, data as Dictionary)

func _apply_sample_icon() -> void:
	SampleArt.decorate(self, SampleArt.icon_for(item))

## 背包装备对比：每个穿戴槽各占一张卡，空槽也保留位置。
func _make_custom_tooltip(_for_text: String) -> Object:
	if role != ROLE_BAG or String(item.get("kind", "")) != "equip":
		return null
	var row := preload("res://scripts/ui/equipment_comparison_tooltip.gd").new()
	row.source_slot = weakref(self)
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_populate_equipment_tooltip(row)
	return row

func _populate_equipment_tooltip(row: GridContainer) -> void:
	var card_count := 1 + Equipment.slots_for_kind(Equipment.item_kind(item)).size()
	var estimated_width := maxf(250.0, 320.0 * SettingsRuntime.text_scale_value())
	row.columns = clampi(int((get_viewport_rect().size.x - 32.0) / estimated_width), 1, card_count)
	var preview := Equipment.replacement_preview(GameState.equipment, item)
	var candidate_card := _equipment_tip_card(Localization.tr_key("ui.equip_tip.bag"), item)
	row.add_child(candidate_card)
	if bool(preview.get("ok", false)):
		var can_wear := Equipment.meets_level(item, int(GameState.player.level))
		var score_increase := bool(preview.get("score_increase", false))
		var column: VBoxContainer = candidate_card.get_child(0)
		var hint := Label.new()
		# 原生 tooltip 根据最小尺寸放置；固定短行避免自动换行产生错误高度。
		hint.autowrap_mode = TextServer.AUTOWRAP_OFF
		hint.add_theme_font_size_override("font_size", maxi(9, roundi(14.0 * SettingsRuntime.text_scale_value())))
		var text := ""
		if score_increase and not can_wear:
			text = Localization.tr_key("ui.equip_tip.locked_stronger", [Equipment.level_req(item)]) + "\n"
			hint.add_theme_color_override("font_color", UPGRADE_LOCKED_COLOR)
		if bool(preview.empty):
			text += Localization.tr_key("ui.equip_tip.empty", [String(preview.slot_label)]) if can_wear \
				else Localization.tr_key("ui.equip_tip.empty_target", [String(preview.slot_label)])
			text += Localization.tr_key("ui.equip_tip.empty_score", [float(preview.score_delta)])
		else:
			if bool(preview.stronger) and can_wear:
				text += Localization.tr_key("ui.equip_tip.stronger") + "\n"
				hint.add_theme_color_override("font_color", Color("78d8a4"))
			text += Localization.tr_key("ui.equip_tip.target", [String(preview.slot_label)])
			text += "\n" + Localization.tr_key("ui.equip_tip.delta", [float(preview.worn_score), float(preview.score_delta)])
			if bool(preview.lower_quality):
				text += "\n" + Localization.tr_key("ui.equip_tip.lower_quality")
		text += "\n" + Localization.tr_key("ui.equip_tip.score_note")
		hint.text = text
		column.add_child(hint)
		if not can_wear and not score_increase:
			var requirement := Label.new()
			requirement.text = Localization.tr_key("ui.equip_tip.required", [Equipment.level_req(item)])
			requirement.add_theme_font_size_override("font_size", maxi(9, roundi(14.0 * SettingsRuntime.text_scale_value())))
			requirement.add_theme_color_override("font_color", Color("ffad78"))
			column.add_child(requirement)
	for sid in Equipment.slots_for_kind(Equipment.item_kind(item)):
		var worn: Variant = GameState.equipment.get(sid)
		var heading := Localization.tr_key("ui.equip_tip.worn", [Equipment.slot_label(sid)])
		if bool(preview.get("ok", false)) and sid == String(preview.slot_id):
			heading += "\n" + Localization.tr_key("ui.equip_tip.default")
		row.add_child(_equipment_tip_card(heading, worn if worn is Dictionary else {}))

func _equipment_tip_card(heading: String, shown: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111820")
	style.border_color = ItemUtil.quality_color(String(shown.get("quality", "common"))) if not shown.is_empty() else Color("6a737b")
	style.set_border_width_all(1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = 210
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_child(column)
	var heading_label := Label.new()
	heading_label.text = heading
	heading_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	heading_label.add_theme_font_size_override("font_size", maxi(9, roundi(14.0 * SettingsRuntime.text_scale_value())))
	heading_label.add_theme_color_override("font_color", Color("9baebc"))
	column.add_child(heading_label)
	var detail := Label.new()
	# 自定义 tooltip 在独立弹窗中；无宽度约束时自动换行会把最小高度算成整屏。
	detail.autowrap_mode = TextServer.AUTOWRAP_OFF
	detail.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	detail.add_theme_font_size_override("font_size", maxi(9, roundi(16.0 * SettingsRuntime.text_scale_value())))
	if shown.is_empty():
		detail.text = Localization.tr_key("ui.equip_tip.unworn")
	else:
		var lines: Array[String] = [ItemUtil.display_name(shown)]
		lines.append_array(ItemUtil.attr_lines(shown))
		lines.append(Localization.tr_key("ui.equip_tip.score", [Equipment.score(shown)]))
		detail.text = "\n".join(PackedStringArray(lines))
		detail.add_theme_color_override("font_color", ItemUtil.quality_color(String(shown.get("quality", "common"))))
	column.add_child(detail)
	return panel
