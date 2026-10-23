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
##   「导出」把该槽写成可移植的明文 JSON 文件；「导入」从外部文件写回该槽（导入不自动读取；
##   活动槽禁止导入）——见工程文档《人物存档导出与导入设计方案》。
## 面板互斥：与背包 / 货郎同规则（09.2），同一时刻只开一个关闭式面板。
## 三张存档卡沿用共用面板材质；确认弹层不改变原有存档事务。

const PANEL_ID := "save"
## 一行最多同时出现 5 个按钮（保存 / 读取 / 导出 / 导入 / 删除），故下限比原来 560 放宽（工程文档 §4.3）。
const CARD_MIN := Vector2(700, 0)
## 内置文件选择器的**设计尺寸**（不使用平台原生对话框，见工程文档 §4.3）。
## 与面板同处界面设计坐标系：弹出时必须按界面倍率换算成视口像素并补上内容缩放，
## 否则高分屏 / 高界面倍率下会明显小于其余面板（见 _popup_file_dialog）。
const FILE_DIALOG_SIZE := Vector2i(760, 520)

const COL_WARN := Color(0.92, 0.55, 0.45)
const COL_OK := Color(0.56, 0.82, 0.48)

var _center: CenterContainer
var _dim: ColorRect
var _cards: Array[Dictionary] = []
var _mode := "manage"
var _hint: Label
var _name_row: HBoxContainer
var _name_input: LineEdit
## 工程 98 Q1=A：职业在「新的旅程」处二选一（默认武士），不做随时切换。
## 职业一旦落档就不可改：装备、技能阶、快捷栏、进度全部按它派生，切换等于半个重置系统。
var _class_row: HBoxContainer
var _class_option: OptionButton
var _class_desc: Label
var _overwrite_dialog: PanelConfirmDialog
var _pending_overwrite := -1
## 导出 / 导入的文件选择器与覆盖确认弹层（工程文档《人物存档导出与导入设计方案》§4.3）。
var _export_dialog: FileDialog
var _import_dialog: FileDialog
var _import_confirm: PanelConfirmDialog
## 待导出 / 待导入的目标槽（-1 = 无待处理动作）；弹层关闭时清空，避免残留上一次目标。
var _export_slot := -1
var _import_slot := -1
## 已选定、等待覆盖确认的导入文件路径。
var _pending_import := ""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	# 文件选择器是独立窗口，Esc 应由它自行关闭，不连带关掉整个存档面板。
	if _file_dialog_open():
		return
	if visible:
		set_open(false)
		get_viewport().set_input_as_handled()

## 任一文件选择器是否可见（内置 FileDialog 属独立窗口，不经过本面板的输入链）。
func _file_dialog_open() -> bool:
	return (_export_dialog != null and _export_dialog.visible) \
		or (_import_dialog != null and _import_dialog.visible)

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
	else:
		_close_dialogs()

## 收起所有弹层并清空待处理槽位，避免下次打开时残留上一次的目标槽。
func _close_dialogs() -> void:
	if _overwrite_dialog != null:
		_overwrite_dialog.hide()
	if _import_confirm != null:
		_import_confirm.hide()
	if _export_dialog != null:
		_export_dialog.hide()
	if _import_dialog != null:
		_import_dialog.hide()
	_pending_overwrite = -1
	_export_slot = -1
	_import_slot = -1
	_pending_import = ""

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

	var box := PanelChrome.new()
	_center.add_child(box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	box.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	var title := Label.new()
	title.text = Localization.tr_key("ui.save_panel.p001")
	title.add_theme_font_size_override("font_size", 18)
	head.add_child(title)
	PanelChrome.style_title(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(32, 28)
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)

	root.add_child(PanelChrome.make_title_gap())
	_name_row = HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = Localization.tr_key("ui.save_panel.p002")
	_name_row.add_child(name_label)
	_name_input = LineEdit.new()
	_name_input.text = Localization.tr_key("ui.save_panel.p003")
	_name_input.max_length = 16
	_name_input.custom_minimum_size = Vector2(190, 30)
	_name_row.add_child(_name_input)
	PanelChrome.style_line_edit(_name_input)
	var class_label := Label.new()
	class_label.text = Localization.tr_key("ui.save_panel.p004")
	class_label.custom_minimum_size = Vector2(64, 0)
	_name_row.add_child(class_label)
	root.add_child(_name_row)

	# 职业选择独占一行：说明文字较长，和名称挤一行会把输入框压到看不清。
	_class_row = HBoxContainer.new()
	_class_row.add_theme_constant_override("separation", 10)
	var class_spacer := Label.new()
	class_spacer.custom_minimum_size = Vector2(64, 0)
	_class_row.add_child(class_spacer)
	_class_option = OptionButton.new()
	_class_option.custom_minimum_size = Vector2(150, 30)
	_class_option.add_theme_font_size_override("font_size", 13)
	for class_id in PlayerClass.ids():
		_class_option.add_item(PlayerClass.display_name(String(class_id)))
		_class_option.set_item_metadata(_class_option.item_count - 1, String(class_id))
	PanelChrome.style_option_button(_class_option)
	_class_option.item_selected.connect(func(_index: int) -> void: _refresh_class_desc())
	_class_row.add_child(_class_option)
	_class_desc = Label.new()
	_class_desc.add_theme_font_size_override("font_size", 12)
	_class_desc.add_theme_color_override("font_color", PanelChrome.MUTED)
	_class_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_class_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_row.add_child(_class_desc)
	root.add_child(_class_row)
	_refresh_class_desc()

	var name_divider := HSeparator.new()
	root.add_child(name_divider)
	PanelChrome.style_separator(name_divider)

	for i in range(1, SaveManager.MAX_SLOTS + 1):
		_build_card(i, root)

	var card_divider := HSeparator.new()
	root.add_child(card_divider)
	PanelChrome.style_separator(card_divider)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", PanelChrome.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = CARD_MIN
	root.add_child(_hint)
	_overwrite_dialog = PanelConfirmDialog.new()
	_overwrite_dialog.title = Localization.tr_key("ui.save_panel.p005")
	_overwrite_dialog.confirmed.connect(_on_overwrite_confirmed)
	add_child(_overwrite_dialog)

	_import_confirm = PanelConfirmDialog.new()
	_import_confirm.title = Localization.tr_key("ui.save_panel.p023")
	_import_confirm.confirmed.connect(_on_import_confirmed)
	add_child(_import_confirm)

	# 文件选择器用**内置** FileDialog（`use_native_dialog = false`）：macOS / Windows 行为一致，
	# 且不引入平台原生对话框的额外风险（原生对话框列为可选增强，工程文档 §8）。
	var desktop := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	_export_dialog = _make_file_dialog(Localization.tr_key("ui.save_panel.p024"), FileDialog.FILE_MODE_SAVE_FILE, desktop)
	_export_dialog.file_selected.connect(_on_export_file_selected)
	_export_dialog.canceled.connect(func() -> void: _export_slot = -1)
	_import_dialog = _make_file_dialog(Localization.tr_key("ui.save_panel.p025"), FileDialog.FILE_MODE_OPEN_FILE, desktop)
	_import_dialog.file_selected.connect(_on_import_file_selected)
	_import_dialog.canceled.connect(func() -> void: _import_slot = -1)

## 建立只选 JSON 的内置文件选择器；默认目录取系统桌面（取不到时留空由 FileDialog 自定）。
## 外观统一交给 SaveDialogTheme：外框、标题带与内部控件沿用游戏内面板素材。
func _make_file_dialog(title: String, mode: FileDialog.FileMode, desktop: String) -> FileDialog:
	var d := FileDialog.new()
	d.title = title
	d.file_mode = mode
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = false
	d.add_filter("*.json", Localization.tr_key("ui.save_panel.p029"))
	if not desktop.is_empty():
		d.current_dir = desktop
	d.theme = SaveDialogTheme.build()
	add_child(d)
	return d

## 弹出文件选择器：FileDialog 是独立 Window，不受 UI CanvasLayer 的界面倍率变换影响，
## 故弹出前先补上同一份内容缩放，并把设计尺寸换算成视口像素
## （高分屏 / 高界面倍率下才不会比其余面板小一圈）。
func _popup_file_dialog(dialog: FileDialog) -> void:
	SettingsRuntime.apply_ui_scale_to_window(dialog)
	dialog.popup_centered(SettingsRuntime.dialog_popup_size(get_viewport().get_visible_rect().size, FILE_DIALOG_SIZE))

func _build_card(slot: int, parent: Node) -> void:
	var card := PanelContainer.new()
	PanelChrome.style_card(card)
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
	title.text = Localization.tr_key("ui.save_panel.p006") % slot
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", PanelChrome.TEXT)
	col.add_child(title)

	var info := Label.new()
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", PanelChrome.MUTED)
	col.add_child(info)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	row.add_child(btns)

	var save_b := _make_button(Localization.tr_key("ui.save_panel.p007"))
	save_b.pressed.connect(_on_save_pressed.bind(slot))
	btns.add_child(save_b)

	var load_b := _make_button(Localization.tr_key("ui.save_panel.p008"))
	load_b.pressed.connect(_on_load_pressed.bind(slot))
	btns.add_child(load_b)

	var export_b := _make_button(Localization.tr_key("ui.save_panel.p021"))
	export_b.pressed.connect(_on_export_pressed.bind(slot))
	btns.add_child(export_b)

	var import_b := _make_button(Localization.tr_key("ui.save_panel.p022"))
	import_b.pressed.connect(_on_import_pressed.bind(slot))
	btns.add_child(import_b)

	var del_b := _make_button(Localization.tr_key("ui.save_panel.p009"))
	del_b.pressed.connect(_on_delete_pressed.bind(slot))
	btns.add_child(del_b)

	# 二次确认（9.4：删除需二次确认）——两段式按钮，避免引入模态对话框（M4 才做统一对话框）
	var yes_b := _make_button(Localization.tr_key("ui.save_panel.p010"))
	yes_b.add_theme_color_override("font_color", COL_WARN)
	yes_b.visible = false
	yes_b.pressed.connect(_on_delete_confirmed.bind(slot))
	btns.add_child(yes_b)

	var no_b := _make_button(Localization.tr_key("ui.save_panel.p011"))
	no_b.visible = false
	no_b.pressed.connect(_on_delete_cancelled.bind(slot))
	btns.add_child(no_b)

	_cards.append({
		"slot": slot, "info": info,
		"save": save_b, "load": load_b, "export": export_b, "import": import_b,
		"del": del_b, "yes": yes_b, "no": no_b,
	})

func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(58, 28)
	b.add_theme_font_size_override("font_size", 13)
	# 不可用态明显置灰（空槽的「读取 / 删除」）
	b.add_theme_color_override("font_disabled_color", Color(0.34, 0.36, 0.40))
	PanelChrome.style_action(b)
	return b

# ---- 刷新 ----

func _refresh() -> void:
	_name_row.visible = _mode == "new"
	_class_row.visible = _mode == "new"
	_hint.text = Localization.tr_key("ui.save_panel.p012") if _mode == "new" else \
		Localization.tr_key("ui.save_panel.load_hint") if _mode == "load" else \
		Localization.tr_key("ui.save_panel.manage_hint")
	for c in _cards:
		var slot := int(c.slot)
		var s := SaveManager.slot_summary(slot)
		var info: Label = c.info
		var active := SaveManager.active_slot == slot

		# 任何刷新都回到"未确认删除"状态，避免确认态残留
		c.yes.visible = false
		c.no.visible = false
		c.del.visible = true
		c.export.visible = true
		c.import.visible = true
		# 「导出」只对可用档开放；「导入」对活动槽置灰（否则内容会被自动存覆盖，工程文档 §4.3）。
		c.export.disabled = not bool(s.get("ok", false))
		c.export.tooltip_text = Localization.tr_key("ui.save_panel.p028")
		c.import.disabled = active
		c.import.tooltip_text = Localization.tr_key("ui.save_panel.p027")

		if bool(s.get("ok", false)):
			var tag := Localization.tr_key("ui.save_panel.active_slot") if active else "○"
			var src := Localization.tr_key("ui.save_panel.backup_recovered") if String(s.get("source", "")) == "backup" else ""
			info.text = Localization.tr_key("ui.save_panel.p013") % [
				tag, String(s.get("name", "")), int(s.get("level", 1)), int(s.get("gold", 0)),
				String(s.get("mapName", "")), String(s.get("savedAt", "")), src,
			]
			info.add_theme_color_override("font_color", PanelChrome.TEXT if active else PanelChrome.MUTED)
			if not String(s.get("message", "")).is_empty():
				info.text += "\n⚠ " + String(s.get("message", ""))
				info.add_theme_color_override("font_color", COL_WARN)
			c.load.disabled = false
			c.del.disabled = false
		elif bool(s.get("exists", false)):
			# 文件在但不可用（损坏且备份不可用）：明确提示，不给"读取"假希望（10.3 不静默）
			info.text = Localization.tr_key("ui.save_panel.p014") % String(s.get("message", ""))
			info.add_theme_color_override("font_color", COL_WARN)
			c.load.disabled = true
			c.del.disabled = false
		else:
			info.text = Localization.tr_key("ui.save_panel.p015")
			info.add_theme_color_override("font_color", PanelChrome.MUTED)
			c.load.disabled = true
			c.del.disabled = true

		c.save.visible = _mode != "load"
		c.save.text = (Localization.tr_key("ui.save_panel.p016") if bool(s.get("exists", false)) else Localization.tr_key("ui.save_panel.p017")) if _mode == "new" else Localization.tr_key("ui.save_panel.p007")
		c.save.add_theme_color_override("font_color", COL_OK if active else PanelChrome.TEXT)

# ---- 操作 ----

func _on_save_pressed(slot: int) -> void:
	if _mode == "new":
		if not _valid_new_name():
			return
		if bool(SaveManager.slot_summary(slot).get("exists", false)):
			_pending_overwrite = slot
			_overwrite_dialog.dialog_text = Localization.tr_key("ui.save_panel.p018") % slot
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

## 当前选中的职业 id（`item_metadata` 存的是 id，不依赖显示名 —— 改名不会悄悄换职业）。
func _selected_class() -> String:
	if _class_option == null or _class_option.selected < 0:
		return PlayerClass.DEFAULT_ID
	return PlayerClass.normalize(String(_class_option.get_item_metadata(_class_option.selected)))

## 职业说明跟着选择走：面板上必须能看出「这个选择意味着什么」。
func _refresh_class_desc() -> void:
	if _class_desc == null:
		return
	var class_id := _selected_class()
	_class_desc.text = Localization.tr_key("ui.save_panel.class_desc") % [
		PlayerClass.describe(class_id),
		int(round(PlayerClass.mult("hpMult", class_id) * 100.0)),
		int(round(PlayerClass.mult("mpMult", class_id) * 100.0)),
		PlayerClass.attack_range(class_id),
	]

func _valid_new_name() -> bool:
	var name := _name_input.text.strip_edges()
	if name.length() >= 2 and name.length() <= 16:
		return true
	EventBus.toast_requested.emit(Localization.tr_key("ui.save_panel.p019"), "danger")
	_name_input.grab_focus()
	return false

func _create_new_slot(slot: int) -> void:
	if not _valid_new_name():
		return
	# 新档原子覆盖旧槽，成功后才清除旧备份；写盘失败保留旧存档。
	SaveManager.active_slot = -1
	# 职业必须随 `reset_to_defaults` 一起落 —— 快捷栏默认格与血/蓝上限都按它派生。
	GameState.reset_to_defaults(_selected_class())
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
	MapService.reload_world()

func _on_delete_pressed(slot: int) -> void:
	for c in _cards:
		var is_this := int(c.slot) == slot
		c.del.visible = not is_this
		c.yes.visible = is_this
		c.no.visible = is_this
		# 删除确认期间收起导出 / 导入，避免一行挤到 6 个按钮。
		c.export.visible = not is_this
		c.import.visible = not is_this

func _on_delete_cancelled(_slot: int) -> void:
	_refresh()

func _on_delete_confirmed(slot: int) -> void:
	SaveManager.delete_slot(slot)
	EventBus.toast_requested.emit(Localization.tr_key("ui.save_panel.p020") % slot, "info")
	_refresh()

# ---- 导出与导入（工程文档《人物存档导出与导入设计方案》§4.3）----

## 「导出」：活动槽先静默落盘一次，使导出内容与玩家当前进度一致（导出是只读副本，不改 active_slot）。
func _on_export_pressed(slot: int) -> void:
	if slot == SaveManager.active_slot:
		SaveManager.save_slot(slot, true)
	var s := SaveManager.slot_summary(slot)
	if not bool(s.get("ok", false)):
		_refresh()
		return
	_export_slot = slot
	_export_dialog.current_file = SaveManager.export_file_name(String(s.get("name", "")), int(s.get("level", 1)))
	_popup_file_dialog(_export_dialog)

func _on_export_file_selected(path: String) -> void:
	var slot := _export_slot
	_export_slot = -1
	if slot < 1:
		return
	SaveManager.export_slot(slot, path)

## 「导入」：先选文件，槽内已有有效档时再确认覆盖，最后才写入（活动槽的按钮已置灰）。
func _on_import_pressed(slot: int) -> void:
	if slot == SaveManager.active_slot:
		return
	_import_slot = slot
	_popup_file_dialog(_import_dialog)

func _on_import_file_selected(path: String) -> void:
	var slot := _import_slot
	if slot < 1:
		return
	if bool(SaveManager.slot_summary(slot).get("ok", false)):
		# 覆盖前二次确认：导入会取代该槽现档（现档先转 .bak，原档不会直接丢失）。
		_pending_import = path
		_import_confirm.dialog_text = Localization.tr_key("ui.save_panel.p026") % slot
		_import_confirm.popup_centered()
		return
	_do_import(slot, path)

func _on_import_confirmed() -> void:
	var slot := _import_slot
	var path := _pending_import
	if slot < 1 or path.is_empty():
		return
	_pending_import = ""
	_do_import(slot, path)

## 导入并刷新卡面；导入**不自动读取**，由玩家点「读取」进入该角色（工程文档 §5）。
func _do_import(slot: int, path: String) -> void:
	_import_slot = -1
	_pending_import = ""
	SaveManager.import_from_file(slot, path)
	_refresh()
