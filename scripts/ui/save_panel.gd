extends Control
## 存档面板（M1-10）。依据：产品文档 09.4（读档界面：3 张存档卡 + 保存 / 读取 / 删除二次确认）、
## 09.3「数据：存档管理（手动存 / 备份 / 删除）」、10.3（原子写入 / 备份 / 损坏恢复）。
##
## 交互：
##   主菜单或暂停菜单打开；Esc 仅关闭本面板并返回上级菜单；
##   每张卡显示 角色名 / 等级 / 金币 / 地图 / 存档时间（9.4 的"职业"本项目暂无，占位见工程文档 06）；
##   「保存」写入该槽并把它设为**活动槽**（此后自动存档都写本槽）；
##   「读取」载入该槽 → 关面板 → 重载世界（销旧怪物 / 掉落 / 面板状态，见工程文档 06 §5）；
##   「删除」两段式二次确认（9.4），删除后清空该槽。
## 面板互斥：与背包 / 货郎同规则（09.2），同一时刻只开一个关闭式面板。
## 占位素材（R5）：纯文本 + 描边卡片，不加载图标。

const PANEL_ID := "save"
const CARD_MIN := Vector2(560, 0)

const COL_PANEL := Color(0.06, 0.07, 0.09, 0.97)
const COL_CARD := Color(0.11, 0.12, 0.15, 0.95)
const COL_BORDER := Color(0.30, 0.33, 0.38, 0.95)
const COL_TEXT := Color(0.90, 0.92, 0.95)
const COL_TEXT_DIM := Color(0.52, 0.55, 0.60)
const COL_GOLD := Color(0.94, 0.78, 0.38)
const COL_WARN := Color(0.92, 0.55, 0.45)
const COL_OK := Color(0.56, 0.82, 0.48)

var _center: CenterContainer
var _dim: ColorRect
var _cards: Array[Dictionary] = []
var _mode := "manage"
var _hint: Label
var _name_row: HBoxContainer
var _name_input: LineEdit
var _overwrite_dialog: ConfirmationDialog
var _pending_overwrite := -1

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false
	EventBus.panel_opened.connect(_on_panel_opened)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if visible:
		set_open(false)
		get_viewport().set_input_as_handled()

func set_mode(mode: String) -> void:
	if mode not in ["new", "load", "manage"]:
		return
	_mode = mode
	if visible:
		_refresh()

## 开关面板；同步全局面板标志（角色操控在 player.gd 中据此屏蔽）。
func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open(PANEL_ID, open)
	if open:
		EventBus.panel_opened.emit(PANEL_ID)
		_refresh()

## 其他面板打开时自动关闭本面板，保证互斥。
func _on_panel_opened(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		return
	if visible:
		set_open(false)

# ---- 构建 ----

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _panel_style())
	_center.add_child(box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	box.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "存档"
	title.add_theme_font_size_override("font_size", 18)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(32, 28)
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)

	root.add_child(HSeparator.new())
	_name_row = HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "角色名称"
	_name_row.add_child(name_label)
	_name_input = LineEdit.new()
	_name_input.text = "守护者"
	_name_input.max_length = 16
	_name_input.custom_minimum_size = Vector2(190, 30)
	_name_row.add_child(_name_input)
	var class_label := Label.new()
	class_label.text = "职业：灵刃战士"
	_name_row.add_child(class_label)
	root.add_child(_name_row)

	root.add_child(HSeparator.new())

	for i in range(1, SaveManager.MAX_SLOTS + 1):
		_build_card(i, root)

	root.add_child(HSeparator.new())

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", COL_TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = CARD_MIN
	root.add_child(_hint)
	_overwrite_dialog = ConfirmationDialog.new()
	_overwrite_dialog.title = "覆盖存档"
	_overwrite_dialog.confirmed.connect(_on_overwrite_confirmed)
	add_child(_overwrite_dialog)

func _build_card(slot: int, parent: Node) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	parent.add_child(card)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	card.add_child(m)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = CARD_MIN
	m.add_child(row)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	var title := Label.new()
	title.text = "槽 %d" % slot
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", COL_TEXT)
	col.add_child(title)

	var info := Label.new()
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", COL_TEXT_DIM)
	col.add_child(info)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	row.add_child(btns)

	var save_b := _make_button("保存")
	save_b.pressed.connect(_on_save_pressed.bind(slot))
	btns.add_child(save_b)

	var load_b := _make_button("读取")
	load_b.pressed.connect(_on_load_pressed.bind(slot))
	btns.add_child(load_b)

	var del_b := _make_button("删除")
	del_b.pressed.connect(_on_delete_pressed.bind(slot))
	btns.add_child(del_b)

	# 二次确认（9.4：删除需二次确认）——两段式按钮，避免引入模态对话框（M4 才做统一对话框）
	var yes_b := _make_button("确认删除")
	yes_b.add_theme_color_override("font_color", COL_WARN)
	yes_b.visible = false
	yes_b.pressed.connect(_on_delete_confirmed.bind(slot))
	btns.add_child(yes_b)

	var no_b := _make_button("取消")
	no_b.visible = false
	no_b.pressed.connect(_on_delete_cancelled.bind(slot))
	btns.add_child(no_b)

	_cards.append({
		"slot": slot, "info": info,
		"save": save_b, "load": load_b, "del": del_b, "yes": yes_b, "no": no_b,
	})

func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(58, 28)
	b.add_theme_font_size_override("font_size", 13)
	# 不可用态明显置灰（空槽的「读取 / 删除」）
	b.add_theme_color_override("font_disabled_color", Color(0.34, 0.36, 0.40))
	return b

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	return sb

func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_CARD
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	return sb

# ---- 刷新 ----

func _refresh() -> void:
	_name_row.visible = _mode == "new"
	_hint.text = "选择存档槽开始新游戏；覆盖已有槽位前需要确认。" if _mode == "new" else \
		"选择存档槽读取游戏。" if _mode == "load" else \
		"保存后该槽成为活动槽：定时、关键事件与退出时自动写入本槽。"
	for c in _cards:
		var slot := int(c.slot)
		var s := SaveManager.slot_summary(slot)
		var info: Label = c.info
		var active := SaveManager.active_slot == slot

		# 任何刷新都回到"未确认删除"状态，避免确认态残留
		c.yes.visible = false
		c.no.visible = false
		c.del.visible = true

		if bool(s.get("ok", false)):
			var tag := "● 活动槽" if active else "○"
			var src := "（从备份恢复）" if String(s.get("source", "")) == "backup" else ""
			info.text = "%s %s　灵刃战士 Lv%d　金币 %d　%s　%s %s" % [
				tag, String(s.get("name", "")), int(s.get("level", 1)), int(s.get("gold", 0)),
				String(s.get("mapName", "")), String(s.get("savedAt", "")), src,
			]
			info.add_theme_color_override("font_color", COL_TEXT if active else COL_TEXT_DIM)
			if not String(s.get("message", "")).is_empty():
				info.text += "\n⚠ " + String(s.get("message", ""))
				info.add_theme_color_override("font_color", COL_WARN)
			c.load.disabled = false
			c.del.disabled = false
		elif bool(s.get("exists", false)):
			# 文件在但不可用（损坏且备份不可用）：明确提示，不给"读取"假希望（10.3 不静默）
			info.text = "⚠ 存档损坏，无法读取：%s" % String(s.get("message", ""))
			info.add_theme_color_override("font_color", COL_WARN)
			c.load.disabled = true
			c.del.disabled = false
		else:
			info.text = "（空）　—　保存将在此建立新存档"
			info.add_theme_color_override("font_color", COL_TEXT_DIM)
			c.load.disabled = true
			c.del.disabled = true

		c.save.visible = _mode != "load"
		c.save.text = ("覆盖" if bool(s.get("exists", false)) else "新建") if _mode == "new" else "保存"
		c.save.add_theme_color_override("font_color", COL_OK if active else COL_TEXT)

# ---- 操作 ----

func _on_save_pressed(slot: int) -> void:
	if _mode == "new":
		if not _valid_new_name():
			return
		if bool(SaveManager.slot_summary(slot).get("exists", false)):
			_pending_overwrite = slot
			_overwrite_dialog.dialog_text = "槽 %d 已有存档。确认覆盖并开始新游戏？此操作不能撤销。" % slot
			_overwrite_dialog.popup_centered()
		else:
			_create_new_slot(slot)
		return
	if _mode != "manage":
		return
	SaveManager.save_slot(slot, false)
	_refresh()

func _on_overwrite_confirmed() -> void:
	if _pending_overwrite < 1:
		return
	var slot := _pending_overwrite
	_pending_overwrite = -1
	_create_new_slot(slot)

func _valid_new_name() -> bool:
	var name := _name_input.text.strip_edges()
	if name.length() >= 2 and name.length() <= 16:
		return true
	EventBus.toast_requested.emit("角色名称需要 2–16 个字符", "danger")
	_name_input.grab_focus()
	return false

func _create_new_slot(slot: int) -> void:
	if not _valid_new_name():
		return
	# 新档原子覆盖旧槽，成功后才清除旧备份；写盘失败保留旧存档。
	SaveManager.active_slot = -1
	GameState.reset_to_defaults()
	GameState.player.name = _name_input.text.strip_edges()
	if not SaveManager.save_slot(slot, true, true):
		_refresh()
		return
	_start_loaded_world()

func _on_load_pressed(slot: int) -> void:
	var res := SaveManager.load_into_game(slot)
	if not bool(res.get("ok", false)):
		_refresh()
		return
	# 重载世界：销毁并重建 Main 场景，清掉旧怪物 / 掉落 / 面板状态（10.5 读档清旧实体）
	GameState.emit_all()
	_start_loaded_world()

func _start_loaded_world() -> void:
	set_open(false)
	GameState.menu_mode = "world"
	get_tree().paused = false
	get_tree().reload_current_scene.call_deferred()

func _on_delete_pressed(slot: int) -> void:
	for c in _cards:
		var is_this := int(c.slot) == slot
		c.del.visible = not is_this
		c.yes.visible = is_this
		c.no.visible = is_this

func _on_delete_cancelled(_slot: int) -> void:
	_refresh()

func _on_delete_confirmed(slot: int) -> void:
	SaveManager.delete_slot(slot)
	EventBus.toast_requested.emit("已删除槽 %d 的存档" % slot, "info")
	_refresh()
