extends Control
## M10-8：装备重铸面板。选装备 → 看当前词条与费用 → 重铸。
## 与升星面板同构（选装备 → 看现状 → 看价格 → 按按钮 → 看结果），但**不消耗如意**、
## 只有一掷：词条全换，品质 / 星级 / 基底 / 实例 id 一律不动。
##
## 工程 81：每条词条右侧有「锁」按钮，锁住的词条连数值一起保留，只有未锁定的重掷；
## 每条锁定加价 `Reforge.lockFactor`。🔴 锁定**不落档**（面板内按 `instanceId` 记忆）——
## 写进存档要动 schema / 迁移 / 校验三处，收益只是「下次打开还记得」；而重铸后
## `instanceId` 不变 ⇒ 连续重掷时锁定照样保留，正是玩家真正需要的那一次。

const PANEL_ID := "reforge"
const WIDTH := 520.0
## 与背包并排时的固定间距（工程 87，与合成工作台同口径）。
const GAP := 12.0
const COL_WARN := Color(0.88, 0.42, 0.36)
## 无词条（普通品质）时的占位符：与「×」同类，属界面符号不属文案。
const EMPTY_AFFIX_TEXT := "—"
## 锁按钮宽度：与「锁 / 已锁」两字等宽，避免切换时整行抖动。
const LOCK_BUTTON_WIDTH := 60.0
## 工程 86 精炼材料：4 格，每格一件紫装；有效件数按档位折算（见 `Reforge.refine_value`）。
const REFINE_SLOTS := 4
const REFINE_SLOT_SIZE := Vector2(56.0, 56.0)

var _picker: OptionButton
var _hint: Label
var _affix_title: Label
var _affix_rows: VBoxContainer
## 工程 90：当前选中装备的评分。与「当前词条」**同一行右对齐** —— 不是审美选择：
## 实测本面板 570×623、内容自然高 581，uiScale 1.25 时可用高只剩 640（余量 17px），
## 独立占一行（+26px）当场顶穿，而评分又必须常驻可读。
var _score: Label
## 破损件补充说明：`score()` 走 `attrs_for_use`，破损时只算基底 ⇒ 词条重掷了、分数不动。
## 不解释就是「花 5 万金币买了个寂寞」（工程 88 的口径，见产品 05 §5.9）。
var _score_note: Label
## 上一次重铸**前**的评分（Q5=A）。只在重铸成功分支里写；换装备 / 关面板清零。
## 🔴 不能写在 `_refresh_details` 里：它被 `inventory_changed` / `gold_changed` / 锁定切换反复调用，
## 基准会被随手覆盖 ⇒ 永远显示「持平」，而且这种错在测试里极易假绿。
var _score_base := NAN
var _score_base_owner := ""
## 内容区滚动容器（Q4=A，F-P2-3）。标题行留在外框渐变带内，其余内容整体可滚。
var _scroll: ScrollContainer
var _lock_hint: Label
var _refine_title: Label
var _refine_head: HBoxContainer
var _refine_row: HBoxContainer
var _refine_slots: Array[ItemSlot] = []
## 材料快照（与锁定同口径：面板内的临时状态，不落档，关闭即清空）。
var _refine_selected: Array[Dictionary] = []
var _refine_hint: Label
var _random_refine: Button
var _price: Label
var _feedback: Label
var _button: Button
var _center: FloatingWindow
var _box: PanelChrome
var _content: VBoxContainer
var _dim: ColorRect
var _choices: Array[Dictionary] = []
var _selected_id := ""
## 锁定的属性名；`_locked_owner` 记的是它属于哪一件装备（换装备即清空，见 §2.6）。
var _locked: Array[String] = []
var _locked_owner := ""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
	EventBus.inventory_changed.connect(_on_items_changed)
	EventBus.equipment_changed.connect(_on_items_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.reforge_panel_requested.connect(_on_requested)
	EventBus.reforge_close_requested.connect(func() -> void: set_open(false))
	EventBus.settings_changed.connect(_resize)
	get_viewport().size_changed.connect(_resize)

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("pause")):
		set_open(false)
		get_viewport().set_input_as_handled()

func _on_requested() -> void:
	set_open(true)

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open(PANEL_ID, open)
	if open:
		_feedback.text = ""
		_refresh_choices()
		# 工程 87：先通知背包进入会话，背包自动打开并让出左半屏；随后再广播本面板已打开。
		EventBus.reforge_mode_changed.emit(true)
		EventBus.panel_opened.emit(PANEL_ID)
		_center.show_window()
		_resize.call_deferred()
		return
	# 工程 81：锁定不落档 —— 关面板即清空，下次打开是干净的（不写进存档 ⇒ schema 不动）。
	_locked.clear()
	_locked_owner = ""
	# 工程 90：增量基准同口径 —— 关掉面板就不再记住「上次重铸前多少分」。
	_score_base = NAN
	_score_base_owner = ""
	# 工程 86：精炼材料同口径，关面板即清空（材料在确认重铸时才扣除）。
	for i in range(_refine_selected.size()):
		_refine_selected[i] = {}
	_refresh_refine_slots()
	# 工程 87：只关重铸，背包保留（与合成工作台一致）。
	EventBus.reforge_mode_changed.emit(false)

func _on_panel_opened(panel_id: String) -> void:
	if visible and not GameState.panels_coexist(panel_id, PANEL_ID):
		set_open(false)

func _on_items_changed() -> void:
	if visible:
		_refresh_choices()

func _on_gold_changed(_amount: int) -> void:
	if visible:
		_refresh_details()

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.42)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_center = FloatingWindow.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_box = PanelChrome.new()
	_center.add_child(_box)
	var margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_box.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	var title := Label.new()
	title.text = Localization.tr_key("ui.reforge_panel.p002")
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	PanelChrome.style_title(title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)
	# 与其余浮窗同构：标题行拖动、点击置前、越界夹紧（工程 74 §7）。
	_center.setup(self, _box, head, Vector2(0.5, 0.5))
	root.add_child(PanelChrome.make_title_gap())
	# 工程 90 Q4=A（F-P2-3）：标题行固定在外框渐变带内，其余内容整体滚动。
	# 不接的后果是量出来的：uiScale 1.5 时面板高 623 > 可用高 533，费用行与「重铸」按钮直接出屏，
	# 又没有滚动条可救（与 08 §7 第 44 条同源）。
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)
	_center.set_content_scroll(_scroll)
	_content = VBoxContainer.new()
	_content.custom_minimum_size = Vector2(WIDTH, 0)
	_content.add_theme_constant_override("separation", 10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_hint = Label.new()
	_hint.text = Localization.tr_key("ui.reforge_panel.p001")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", PanelChrome.MUTED)
	_content.add_child(_hint)
	_picker = OptionButton.new()
	_picker.custom_minimum_size.y = 36
	_picker.item_selected.connect(_on_selected)
	_content.add_child(_picker)
	PanelChrome.style_option_button(_picker)
	var affix_head := HBoxContainer.new()
	affix_head.add_theme_constant_override("separation", 8)
	_content.add_child(affix_head)
	_affix_title = Label.new()
	_affix_title.text = Localization.tr_key("ui.reforge_panel.p003")
	_affix_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PanelChrome.style_section(_affix_title)
	affix_head.add_child(_affix_title)
	# 工程 90：评分贴在同一行右侧。`autowrap=OFF` + `SHRINK_END` —— 文字倍率放大后
	# 让标题先挤压，而不是把「评分：166.4」折成两行把整行顶高。
	_score = Label.new()
	_score.autowrap_mode = TextServer.AUTOWRAP_OFF
	_score.size_flags_horizontal = Control.SIZE_SHRINK_END
	_score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score.add_theme_font_size_override("font_size", 15)
	_score.visible = false
	affix_head.add_child(_score)
	_score_note = Label.new()
	_score_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_score_note.add_theme_font_size_override("font_size", 12)
	_score_note.add_theme_color_override("font_color", PanelChrome.MUTED)
	_score_note.visible = false
	_content.add_child(_score_note)
	_affix_rows = VBoxContainer.new()
	_affix_rows.add_theme_constant_override("separation", 4)
	_content.add_child(_affix_rows)
	_lock_hint = Label.new()
	_lock_hint.text = Localization.tr_key("ui.reforge_panel.p011")
	_lock_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lock_hint.add_theme_font_size_override("font_size", 12)
	_lock_hint.add_theme_color_override("font_color", PanelChrome.MUTED)
	_content.add_child(_lock_hint)
	_refine_title = Label.new()
	_refine_title.text = Localization.tr_key("ui.reforge_panel.p018")
	PanelChrome.style_section(_refine_title)
	var refine_head := HBoxContainer.new()
	_refine_head = refine_head
	refine_head.add_theme_constant_override("separation", 8)
	refine_head.add_child(_refine_title)
	var refine_spacer := Control.new()
	refine_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refine_head.add_child(refine_spacer)
	_random_refine = Button.new()
	_random_refine.text = Localization.tr_key("ui.reforge_panel.p022")
	_random_refine.tooltip_text = Localization.tr_key("ui.reforge_panel.p023")
	_random_refine.pressed.connect(_on_random_refine)
	refine_head.add_child(_random_refine)
	PanelChrome.style_action(_random_refine)
	_content.add_child(refine_head)
	_refine_row = HBoxContainer.new()
	_refine_row.add_theme_constant_override("separation", 8)
	_content.add_child(_refine_row)
	for i in range(REFINE_SLOTS):
		var slot := ItemSlot.new()
		slot.role = ItemSlot.ROLE_TRAY
		slot.index = i
		slot.apply_grid_base(REFINE_SLOT_SIZE)
		slot.item_dropped.connect(_on_refine_dropped)
		slot.pressed.connect(_clear_refine.bind(i))
		_refine_row.add_child(slot)
		_refine_slots.append(slot)
		_refine_selected.append({})
	_refine_hint = Label.new()
	_refine_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refine_hint.add_theme_font_size_override("font_size", 12)
	_refine_hint.add_theme_color_override("font_color", PanelChrome.MUTED)
	_content.add_child(_refine_hint)
	_price = Label.new()
	_price.add_theme_color_override("font_color", PanelChrome.GOLD_LIGHT)
	_content.add_child(_price)
	_button = Button.new()
	_button.text = Localization.tr_key("ui.reforge_panel.p004")
	_button.custom_minimum_size.y = 38
	_button.pressed.connect(_on_reforge)
	_content.add_child(_button)
	PanelChrome.style_action(_button, true)
	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_feedback)

## 工程 87：与背包并排。宽屏把背包 dock 在左侧、重铸 pin 到背包右侧；
## 窄屏不强行分区（52% 高度会裁掉按钮），改为背包铺满背景、重铸保持居中浮窗，
## 玩家拖标题栏即可让出背包格。
func _resize() -> void:
	if _box == null or _content == null:
		return
	var logical := get_viewport_rect().size / SettingsRuntime.ui_scale_value()
	if logical.x <= 0.0 or logical.y <= 0.0:
		return
	var width := minf(WIDTH, logical.x * 0.9)
	_content.custom_minimum_size.x = width
	var bag: Variant = get_node_or_null("../InventoryPanel")
	var bag_width := 540.0
	if bag != null and bag._center != null:
		bag_width = bag._center.panel_box.get_combined_minimum_size().x
	# 并开时去掉全屏暗色遮罩：本面板在背包之后入树，遮罩会把左半屏背包一起压暗。
	_dim.visible = bag == null or not bool(bag.visible)
	if logical.x >= bag_width + width + GAP + 24.0:
		var left := (logical.x - bag_width - width - GAP) * 0.5
		if bag != null and bag.visible:
			bag._center.set_docked(true, left / logical.x, (left + bag_width) / logical.x)
		_center.set_pinned(false)
		var panel_width := _box.get_combined_minimum_size().x
		_center.set_origin(Vector2((left + bag_width + GAP) / maxf(1.0, logical.x - panel_width), 0.5), true)
	else:
		if bag != null and bag.visible:
			bag._center.set_docked(true, 0.0, 1.0)
		_center.set_pinned(false)
		_center.set_origin(Vector2(0.5, 0.5), true)

## 工程 87：随机放入只替换面板预选，不动背包；候选与排序全部由规则层决定。
func _on_random_refine() -> void:
	if not visible:
		return
	var target := _selected_item()
	if target.is_empty():
		return
	var picked := Reforge.random_refine_materials(GameState.inventory, target, REFINE_SLOTS)
	if picked.is_empty():
		_feedback.text = Localization.tr_key("ui.reforge_panel.p024")
		return
	for i in range(_refine_selected.size()):
		_refine_selected[i] = picked[i] if i < picked.size() else {}
	_feedback.text = ""
	_refresh_details()

## 候选＝已穿戴（按槽位定义序）+ 背包（按格序），与升星面板同一范式。
## 刻意**不过滤「不能重铸的装备」**：普通品质的装备也要能选中，玩家才看得到
## 按钮为什么是灰的（tooltip 给出原因），而不是「我的装备消失了」。
func _refresh_choices() -> void:
	_choices.clear()
	_picker.clear()
	for slot in Equipment.SLOT_DEFS:
		var sid := String(slot.id)
		var item = GameState.equipment.get(sid)
		if item is Dictionary:
			_add_choice("worn", sid, item, Localization.tr_key("ui.upgrade.worn_slot") % String(slot.label))
	for index in range(GameState.inventory.size()):
		var item = GameState.inventory[index]
		if item is Dictionary and String(item.get("kind", "")) == "equip":
			_add_choice("bag", index, item, Localization.tr_key("ui.upgrade.bag_slot") % (index + 1))
	if _choices.is_empty():
		_picker.add_item(Localization.tr_key("ui.reforge_panel.p005"))
		_picker.disabled = true
		_selected_id = ""
	else:
		_picker.disabled = false
		var choice_index := 0
		for i in range(_choices.size()):
			if String(_choices[i].id) == _selected_id:
				choice_index = i
				break
		_picker.select(choice_index)
		_selected_id = String(_choices[choice_index].id)
	_refresh_details()

func _add_choice(source: String, key: Variant, item: Dictionary, prefix: String) -> void:
	var id := String(item.get("instanceId", ""))
	if id.is_empty():
		return
	_choices.append({"source": source, "key": key, "id": id})
	_picker.add_item("%s　%s" % [prefix, ItemUtil.display_name(item)])

## 等价于在下拉里选中第 `index` 项（测试不依赖输入系统）。
## 🔴 只调 `_on_selected` 不够：`_selected_item()` 读的是 `_picker.selected`，
## 真实路径下信号先改了它，直接调函数则仍是旧值 ⇒ 面板显示的还是上一件。
func select_choice(index: int) -> void:
	if index < 0 or index >= _choices.size():
		return
	_picker.select(index)
	_on_selected(index)

func _on_selected(index: int) -> void:
	if index >= 0 and index < _choices.size():
		_selected_id = String(_choices[index].id)
		# 工程 90：换装备即丢掉上一次重铸的对比基准（与锁定「换件即清空」同口径）。
		_score_base = NAN
		_score_base_owner = ""
		_feedback.text = ""
		_refresh_details()

func _selected_item() -> Dictionary:
	var index := _picker.selected
	if index < 0 or index >= _choices.size():
		return {}
	var choice := _choices[index]
	var candidate = GameState.inventory[choice.key] if choice.source == "bag" \
		else GameState.equipment.get(choice.key)
	if candidate is Dictionary and String(candidate.get("instanceId", "")) == String(choice.id):
		return candidate
	return {}

func _refresh_details() -> void:
	var item := _selected_item()
	if item.is_empty():
		_build_affix_rows({})
		# 工程 90：无候选就整行隐藏 —— 显示「评分 0.0」会被读成「这件装备一文不值」，
		# 而真实原因是「你还没有装备」。
		_refresh_score({})
		_lock_hint.visible = false
		_refine_head.visible = false
		_refine_row.visible = false
		_refine_hint.visible = false
		_price.text = ""
		_button.text = Localization.tr_key("ui.reforge_panel.p004")
		_button.disabled = true
		_button.tooltip_text = ""
		return
	# 换装备即清空锁定；重铸后 instanceId 不变 ⇒ 锁定保留（连续重掷的关键体验）。
	var owner_id := String(item.get("instanceId", ""))
	if _locked_owner != owner_id:
		_locked.clear()
		_locked_owner = owner_id
	_locked = _prune_locks(item)
	_build_affix_rows(item)
	_refresh_score(item)
	_lock_hint.visible = true
	_refresh_refine(item)
	var price := Reforge.cost(Equipment.level_req(item), _locked.size())
	var guard := Reforge.can_reforge(item)
	var locks := Reforge.validate_locks(item, _locked)
	_price.text = "" if price <= 0 else Localization.tr_key("ui.reforge_panel.p014") % [
		price, _locked.size(), GameState.gold]
	_button.text = Localization.tr_key("ui.reforge_panel.p004") if _locked.is_empty() \
		else Localization.tr_key("ui.reforge_panel.p017") % [_locked.size()]
	_button.disabled = not bool(guard.get("ok", false)) or price <= 0 or GameState.gold < price \
		or not bool(locks.get("ok", false))
	if not bool(guard.get("ok", false)):
		_button.tooltip_text = String(guard.get("reason", ""))
	elif not bool(locks.get("ok", false)):
		_button.tooltip_text = String(locks.get("reason", ""))
	elif price <= 0:
		_button.tooltip_text = Localization.tr_key("msg.reforge.p004")
	elif GameState.gold < price:
		_button.tooltip_text = Localization.tr_key("ui.reforge_panel.p007")
	else:
		_button.tooltip_text = ""

## ---- 工程 90：评分（当前值 + 与上一次重铸的差值）----
## 🔴 口径只有 `Equipment.score` 一个入口（内部走 `EquipmentMath.attrs_for_use`）。
## 面板自己再算一遍就会出现「面板 166.4 / 背包浮层 172.0」的分裂 —— 与工程 88
## 「面板与结算各写一遍」同型；测试直接用 `Equipment.score` 的返回值当判据。
func _refresh_score(item: Dictionary) -> void:
	if _score == null or _score_note == null:
		return
	if item.is_empty():
		_score.visible = false
		_score.text = ""
		_score_note.visible = false
		return
	_score.visible = true
	var current := _rounded_score(Equipment.score(item))
	var text := Localization.tr_key("ui.equip_tip.score", [current])
	var color := PanelChrome.GOLD_LIGHT
	if _score_base_owner == String(item.get("instanceId", "")) and not is_nan(_score_base):
		var delta := current - _score_base
		if absf(delta) < 0.005:
			text += Localization.tr_key("ui.reforge_panel.p026")
			color = PanelChrome.MUTED
		else:
			text += Localization.tr_key("ui.reforge_panel.p025") % _signed_delta(delta)
			color = PanelChrome.GOLD_LIGHT if delta > 0.0 else COL_WARN
	_score.text = text
	_score.add_theme_color_override("font_color", color)
	# 破损件：词条重掷了，但评分一点不动（`score` 只算基底）。不说清楚就是「花了钱没效果」。
	var broken := Durability.is_broken(item)
	_score_note.visible = broken
	if broken:
		_score_note.text = Localization.tr_key("ui.reforge_panel.p027")

## 先归一到 `%.1f` 再比：166.44 与 166.36 都显示 166.4，差值直接相减却是 -0.1，
## 玩家会看到「评分 166.4（较上次 -0.1）」这种自相矛盾的文案。
static func _rounded_score(value: float) -> float:
	return roundf(value * 10.0) / 10.0

## 涨要带 `+`；跌由 `%.1f` 自带 `-`（format 不补正号）。
static func _signed_delta(value: float) -> String:
	return ("+%.1f" % value) if value > 0.0 else ("%.1f" % value)

## 词条区改行容器：每行「词条文本 + 锁按钮」。锁定行用金色，未锁用正文色。
## 🔴 锁按钮到上限后**置灰而不是隐藏** —— 隐藏会让玩家以为「这件装备只能锁两条」，
## 置灰 + tooltip 才说清「已经锁满了」。
func _build_affix_rows(item: Dictionary) -> void:
	for child in _affix_rows.get_children():
		_affix_rows.remove_child(child)
		child.queue_free()
	if item.is_empty():
		var placeholder := Label.new()
		placeholder.text = Localization.tr_key("ui.reforge_panel.p010")
		placeholder.add_theme_color_override("font_color", PanelChrome.MUTED)
		_affix_rows.add_child(placeholder)
		return
	var entries: Array[Dictionary] = []
	for key in ["affixes", "pctAttrs"]:
		var arr: Variant = item.get(String(key), [])
		if not arr is Array:
			continue
		for e in arr as Array:
			if e is Dictionary:
				entries.append(e as Dictionary)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = EMPTY_AFFIX_TEXT
		empty.add_theme_color_override("font_color", PanelChrome.MUTED)
		_affix_rows.add_child(empty)
		return
	var limit := Reforge.max_lock_count(item)
	for entry in entries:
		var stat := String(entry.get("stat", ""))
		var is_locked := _locked.has(stat)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_affix_rows.add_child(row)
		var text := Label.new()
		text.text = ItemUtil.stat_line(stat, float(entry.get("value", 0.0)))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_color_override("font_color",
			PanelChrome.GOLD_LIGHT if is_locked else PanelChrome.TEXT)
		row.add_child(text)
		var lock := Button.new()
		lock.toggle_mode = true
		lock.custom_minimum_size.x = LOCK_BUTTON_WIDTH
		lock.text = Localization.tr_key("ui.reforge_panel.p013") if is_locked \
			else Localization.tr_key("ui.reforge_panel.p012")
		lock.button_pressed = is_locked
		lock.set_meta("stat", stat)
		lock.pressed.connect(_on_lock_toggled.bind(stat))
		row.add_child(lock)
		PanelChrome.style_action(lock, is_locked)
		if limit <= 0:
			lock.disabled = true
			lock.tooltip_text = Localization.tr_key("ui.reforge_panel.p016")
		elif not is_locked and _locked.size() >= limit:
			lock.disabled = true
			lock.tooltip_text = Localization.tr_key("msg.reforge.p006")

## 丢弃已经不在装备上的锁定（正常流程不会发生；防的是「锁定残留 → 校验拒绝 → 按钮莫名变灰」）。
func _prune_locks(item: Dictionary) -> Array[String]:
	var present: Array[String] = []
	for key in ["affixes", "pctAttrs"]:
		var arr: Variant = item.get(String(key), [])
		if not arr is Array:
			continue
		for e in arr as Array:
			if e is Dictionary:
				present.append(String((e as Dictionary).get("stat", "")))
	var kept: Array[String] = []
	for stat in _locked:
		if present.has(stat) and not kept.has(stat):
			kept.append(stat)
	return kept

## ---- 精炼材料（工程 86）----
## 只抬本次**未锁定**词条的数值下限；材料在确认重铸时才由 `GameState` 校验并扣除。
## 面板内保存的是快照（与锁定同口径），确认时按实例 id 重新定位，拖放期间整理也不会误耗。

## 丢弃已不在背包 / 已不合格的材料，再按有效件数算下限。
func _refresh_refine(target: Dictionary) -> void:
	_refine_head.visible = true
	_refine_row.visible = true
	_refine_hint.visible = true
	_prune_refine(target)
	_refresh_refine_slots()
	var materials := refine_materials()
	var effective := Reforge.refine_count(materials, target)
	_refine_hint.text = Localization.tr_key("ui.reforge_panel.p019") if materials.is_empty() else \
		Localization.tr_key("ui.reforge_panel.p020") % [
			materials.size(), effective, int(round(Reforge.floor_ratio(effective) * 100.0))]

func _prune_refine(target: Dictionary) -> void:
	for i in range(_refine_selected.size()):
		var snapshot := _refine_selected[i]
		if snapshot.is_empty():
			continue
		var found := GameState.find_owned_item(String(snapshot.get("instanceId", "")))
		var current: Dictionary = found.get("item", {}) if not found.is_empty() else {}
		if String(found.get("loc", "")) != "bag" or current != snapshot \
				or not bool(Reforge.can_refine(current, target).get("ok", false)):
			_refine_selected[i] = {}

func _refresh_refine_slots() -> void:
	for i in range(_refine_slots.size()):
		var slot := _refine_slots[i]
		var item := _refine_selected[i]
		slot.item = item
		slot.text = ItemUtil.display_name(item).substr(0, 2) if not item.is_empty() else \
			Localization.tr_key("ui.reforge_panel.p021") % (i + 1)
		slot.apply_grid_style(
			ItemUtil.quality_color(String(item.get("quality", "common"))) if not item.is_empty() \
				else ItemSlot.GRID_BORDER, not item.is_empty())
		slot.tooltip_text = "" if item.is_empty() else "%s\n%s" % [
			ItemUtil.display_name(item), "\n".join(PackedStringArray(ItemUtil.attr_lines(item)))]
		SampleArt.decorate(slot, SampleArt.icon_for(item))

## 接收背包拖入；与铁匠合成同口径，收藏件 / 非紫装 / 重复件一律拒绝并说明原因。
func _on_refine_dropped(row: int, payload: Dictionary) -> void:
	if not visible:
		return
	var target := _selected_item()
	if target.is_empty():
		return
	var item := _source_item(payload)
	if item.is_empty():
		_feedback.text = Localization.tr_key("msg.reforge.p013")
		return
	var guard := Reforge.can_refine(item, target)
	if not bool(guard.get("ok", false)):
		_feedback.text = String(guard.get("reason", ""))
		return
	var id := String(item.get("instanceId", ""))
	for i in range(_refine_selected.size()):
		if i != row and String(_refine_selected[i].get("instanceId", "")) == id:
			_feedback.text = Localization.tr_key("msg.reforge.p012")
			return
	_refine_selected[row] = item.duplicate(true)
	_feedback.text = ""
	_refresh_details()

func _clear_refine(row: int) -> void:
	if row < 0 or row >= _refine_selected.size() or _refine_selected[row].is_empty():
		return
	_refine_selected[row] = {}
	_feedback.text = ""
	_refresh_details()

## 验证拖拽载荷仍指向原背包装备（拖动期间整理 / 变更即失效）。
func _source_item(payload: Dictionary) -> Dictionary:
	if int(payload.get("from", -1)) != ItemSlot.ROLE_BAG:
		return {}
	var index := int(payload.get("index", -1))
	if index < 0 or index >= GameState.inventory.size() or not GameState.inventory[index] is Dictionary:
		return {}
	var current: Dictionary = GameState.inventory[index]
	if current != payload.get("item", {}) or not Warehouse.token_matches(current, String(payload.get("token", ""))):
		return {}
	return current


## 按词条顺序返回锁按钮；未选中装备时为空。
func lock_buttons() -> Array[Button]:
	var out: Array[Button] = []
	if _affix_rows == null:
		return out
	for row in _affix_rows.get_children():
		if not row is HBoxContainer:
			continue
		for child in (row as HBoxContainer).get_children():
			if child is Button:
				out.append(child as Button)
	return out

## 当前锁定的属性名（面板内的临时状态，不落档）。
func locked_stats() -> Array[String]:
	return _locked.duplicate()

## 等价于点击第 `stat` 行的锁按钮（测试不依赖输入系统）。
func toggle_lock(stat: String) -> void:
	_on_lock_toggled(stat)

func _on_lock_toggled(stat: String) -> void:
	if _locked.has(stat):
		_locked.erase(stat)
	elif not stat.is_empty():
		_locked.append(stat)
	_feedback.text = ""
	_refresh_details()

## ---- 精炼材料测试锚点（`RefineTest`：不依赖输入系统即可投放 / 撤下材料）----

## 当前已放入的材料快照（空槽已剔除）。
func refine_materials() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for snapshot in _refine_selected:
		if not snapshot.is_empty():
			out.append(snapshot)
	return out

func refine_slots() -> Array[ItemSlot]:
	return _refine_slots.duplicate()

## 等价于把第 `bag_index` 格拖入第 `row` 个精炼格。
func drop_refine_material(row: int, bag_index: int) -> void:
	if bag_index < 0 or bag_index >= GameState.inventory.size():
		return
	var item = GameState.inventory[bag_index]
	if not item is Dictionary:
		return
	_on_refine_dropped(row, {"from": ItemSlot.ROLE_BAG, "index": bag_index,
		"item": item, "token": Warehouse.item_token(item)})

func _on_reforge() -> void:
	var index := _picker.selected
	if index < 0 or index >= _choices.size():
		return
	var choice := _choices[index]
	var before := _selected_item()
	var old_lines := ItemUtil.affix_lines(before)
	# 工程 90：基准必须在调用前取成**值**。`before` 是字典引用，重铸若原地改写它，
	# 事后取分就会静默拿到「新分」⇒ 增量恒为 0，而且不报任何错。
	var before_score := Equipment.score(before)
	# 快照：重铸会触发 `inventory_changed` → `_refresh_details`，那之后 `_locked` 已被剪枝重建。
	var locked_snapshot := _locked.duplicate()
	var refine_snapshot: Array[String] = []
	for snapshot in _refine_selected:
		if not snapshot.is_empty():
			refine_snapshot.append(String(snapshot.get("instanceId", "")))
	var result := GameState.reforge_equipment(String(choice.source), choice.key, String(choice.id),
		null, locked_snapshot, refine_snapshot)
	if not bool(result.get("ok", false)):
		_feedback.text = String(result.get("reason", ""))
		_feedback.add_theme_color_override("font_color", COL_WARN)
		_refresh_details()
		return
	for i in range(_refine_selected.size()):
		_refine_selected[i] = {}
	# 工程 90：基准只在这里落定（成功分支）。失败分支（金币不足 / 校验拒绝）不写 ——
	# 否则下一次成功时会拿一个很旧的基准去比，差值失去意义。
	_score_base = _rounded_score(before_score)
	_score_base_owner = String(choice.id)
	var new_lines: Array = ItemUtil.affix_lines({
		"affixes": result.get("affixes", []), "pctAttrs": result.get("pctAttrs", []),
	})
	# R-2：重掷有可能掷出与原来完全相同的词条 —— 静默会让玩家以为按钮坏了。
	if bool(result.get("unchanged", false)):
		_feedback.text = Localization.tr_key("ui.reforge_panel.p009")
	elif locked_snapshot.is_empty():
		_feedback.text = Localization.tr_key("ui.reforge_panel.p008") % [
			", ".join(old_lines), ", ".join(new_lines)]
	else:
		var kept_lines: Array[String] = []
		for key in ["affixes", "pctAttrs"]:
			var arr: Variant = result.get(String(key), [])
			if not arr is Array:
				continue
			for e in arr as Array:
				if not e is Dictionary or not locked_snapshot.has(String((e as Dictionary).get("stat", ""))):
					continue
				kept_lines.append(ItemUtil.stat_line(String((e as Dictionary).get("stat", "")),
					float((e as Dictionary).get("value", 0.0))))
		_feedback.text = Localization.tr_key("ui.reforge_panel.p015") % [
			", ".join(kept_lines), ", ".join(old_lines), ", ".join(new_lines)]
	_feedback.add_theme_color_override("font_color", PanelChrome.GOLD_LIGHT)
	_refresh_choices()
