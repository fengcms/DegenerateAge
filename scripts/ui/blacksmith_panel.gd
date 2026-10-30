extends Control
## 铁匠对话与功能菜单。NPC 的自我介绍来自地图配置，菜单打开升星、重铸及四种合成服务。
##
## 两种模式共用同一个面板节点（工程 108）：
##   · 回城铁匠：问候卡 + 「继续」→ 服务菜单，全部原价；
##   · 随身铁匠：跳过问候卡直接进菜单，修理 1.5× / 成长服务 ×1.2（`ServiceFee`）。
## 服务按钮**一份**，不做第二套 —— 复用的意义就在这里，复制一份必然漏掉某个 `_refresh_*`。

const PANEL_ID := "blacksmith"
const COL_PANEL := Color(0.06, 0.07, 0.09, 0.97)
const COL_BORDER := Color(0.36, 0.31, 0.26)

## 是否为随身模式。由 `blacksmith_panel_requested` 第三参设置，**每次打开都重置** ——
## 面板是常驻节点，只在打开时写一次会让「上一次随身、这一次回城」沿用旧状态。
var _portable := false
var _title: Label
var _greeting: Label
var _continue: Button
var _leave: Button
var _upgrade: Button
var _reforge: Button
var _repair: Button
var _fusion_buttons: Array[Button] = []
var _service_grids: Array[GridContainer] = []
var _greeting_card: Control
var _service_card: Control
var _center: FloatingWindow
var _root: VBoxContainer
var _footer: HBoxContainer
var _service_scroll: ScrollContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.blacksmith_panel_requested.connect(_on_requested)
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
	EventBus.settings_changed.connect(_resize)
	get_viewport().size_changed.connect(_resize)
	_resize.call_deferred()

## 根据逻辑视口限制菜单宽度；服务区高度不再写死一档，改由 FloatingWindow.fit_content
## 按内容自然高度结算：内容放得下就按内容铺开（100% 缩放下不出滚动条），
## 只有窄窗口（如 200% 缩放）才收回到可见区内，由滚动条兜底。
func _resize() -> void:
	if _root == null:
		return
	var logical := get_viewport_rect().size / SettingsRuntime.ui_scale_value()
	_root.custom_minimum_size = Vector2(minf(500.0, logical.x * 0.84), 0.0)
	# 同一滚动容器重复注入是幂等的，只是触发一次 deferred 重排。
	_center.set_content_scroll(_service_scroll)

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("pause")):
		set_open(false)
		get_viewport().set_input_as_handled()

## 第三参 `portable` 是**必填**（信号参数无默认值）。故意不给方法默认值：
## 漏补 emit 时应当当场 `too few arguments` 炸出来，而不是静默走错模式。
func _on_requested(npc_name: String, greeting: String, portable: bool) -> void:
	_portable = portable
	if _portable:
		# 随身模式没有 NPC 可以称呼：标题取路由器里的「随身铁匠」。
		# 若沿用 `npc_name` 的回退分支，标题会变成「铁匠」——玩家分不清自己开的是哪个。
		_title.text = PanelChrome.title_text(PanelRouter.title(PANEL_ID))
	else:
		_title.text = PanelChrome.title_text(npc_name if not npc_name.is_empty() else Localization.tr_key("ui.blacksmith_panel.p002"))
	_greeting.text = "「%s」" % greeting
	set_open(true)

func _on_panel_opened(panel_id: String) -> void:
	if panel_id != PANEL_ID and visible:
		set_open(false)

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open(PANEL_ID, open)
	if open:
		# 「离开」只在回城模式有意义：随身模式没有对话可离开，右上角 × 足够；
		# 底部留一个空按钮会让人以为漏了什么。
		# 🔴 必须**每次**显式重置：只在随身分支里藏它的话，下一次回城打开会继承隐藏状态
		#    （面板是常驻节点，`visible` 不会自己回到 true）。
		_leave.visible = not _portable
		if _portable:
			# 直接进服务菜单：没有 NPC 可问候，一屏空话 + 一次多余点击是纯摩擦。
			# 复用 `_show_menu()` 而不是复制它的几行 —— 那几行里有 `_refresh_repair_button()`
			# 与 `set_content_scroll()`，复制一份必然漏掉其中一个。
			_show_menu()
		else:
			_continue.visible = true
			_upgrade.visible = false
			_reforge.visible = false
			for button in _fusion_buttons:
				button.visible = false
			_greeting_card.visible = true
			_service_card.visible = false
		EventBus.panel_opened.emit(PANEL_ID)
		_center.show_window()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.36)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_center = FloatingWindow.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	var panel := PanelChrome.new()
	_center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	_root = VBoxContainer.new()
	var root := _root
	root.custom_minimum_size = Vector2(500, 0)
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	_title = Label.new()
	_title.text = Localization.tr_key("ui.blacksmith_panel.p002")
	_title.add_theme_font_size_override("font_size", 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	PanelChrome.style_title(_title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)
	# 与其余浮窗同构：标题行拖动、点击置前、越界夹紧（工程 74 §7）。
	_center.setup(self, panel, head, Vector2(0.5, 0.5))
	root.add_child(PanelChrome.make_title_gap())
	_greeting_card = PanelContainer.new()
	PanelChrome.style_card(_greeting_card as PanelContainer)
	_greeting_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_greeting_card)
	var greeting_row := HBoxContainer.new()
	greeting_row.add_theme_constant_override("separation", 18)
	_greeting_card.add_child(greeting_row)
	var portrait := TextureRect.new()
	var portrait_atlas := AtlasTexture.new()
	portrait_atlas.atlas = preload("res://assets/sprites/npcs/blacksmith/idle_atlas.png")
	portrait_atlas.region = Rect2(0, 0, 64, 80)
	portrait.texture = portrait_atlas
	portrait.custom_minimum_size = Vector2(118, 150)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	greeting_row.add_child(portrait)
	var speech := VBoxContainer.new()
	speech.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	greeting_row.add_child(speech)
	var speaker := Label.new()
	speaker.text = Localization.tr_key("ui.blacksmith_panel.p002")
	PanelChrome.style_section(speaker)
	speech.add_child(speaker)
	_greeting = Label.new()
	_greeting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_greeting.add_theme_color_override("font_color", PanelChrome.TEXT)
	speech.add_child(_greeting)
	_service_card = PanelContainer.new()
	PanelChrome.style_card(_service_card as PanelContainer)
	_service_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_service_card.visible = false
	root.add_child(_service_card)
	_service_scroll = ScrollContainer.new()
	_service_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_service_card.add_child(_service_scroll)
	var service_content := VBoxContainer.new()
	service_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	service_content.add_theme_constant_override("separation", 10)
	_service_scroll.add_child(service_content)
	var service_title := Label.new()
	service_title.text = Localization.tr_key("ui.blacksmith_panel.p007")
	PanelChrome.style_section(service_title)
	service_content.add_child(service_title)
	# 强化组：升星与重铸都改单件装备，放在一起并共用一句说明。
	var enhance_grid := _build_group(service_content, "ui.blacksmith_panel.group_enhance",
		"ui.blacksmith_panel.hint_enhance")
	_upgrade = _make_service(enhance_grid, "ui.blacksmith_panel.p004", true)
	_upgrade.pressed.connect(_open_upgrade)
	_reforge = _make_service(enhance_grid, "ui.reforge_panel.p002", true)
	_reforge.pressed.connect(_open_reforge)
	# 合成组：四项服务排成 2×2 —— 四金合紫 / 四紫定向 一行，四紫升紫 / 保星升级 一行，
	# 两种「往上升档」的服务同排，也省掉一整行按钮高度（滚动条的根因，见 _resize）。
	# 下排两项都走高亮样式：一格金一格灰并排会显得层级不齐，而这两项本来就是同一档语义。
	var forge_grid := _build_group(service_content, "ui.blacksmith_panel.group_forge",
		"ui.blacksmith_panel.hint_forge")
	for service in [
		{"mode": EquipmentFusion.GOLD_TO_PURPLE, "key": "ui.fusion.gold_title", "primary": false},
		{"mode": EquipmentFusion.PURPLE_TARGET, "key": "ui.fusion.purple_title", "primary": false},
		{"mode": EquipmentFusion.PURPLE_UP_TIER, "key": "ui.fusion.purple_up_title", "primary": true},
		{"mode": EquipmentFusion.STAR_TRANSFER, "key": "ui.fusion.star_title", "primary": true},
	]:
		var button := _make_service(forge_grid, String(service.key), bool(service.primary))
		button.pressed.connect(_open_fusion.bind(String(service.mode)))
		_fusion_buttons.append(button)
	# 保星升级有跨档扣费规则（工程 64），说明整行跟在网格下方。
	(forge_grid.get_parent() as VBoxContainer).add_child(
		_make_hint("ui.blacksmith_panel.hint_transfer"))
	# 维护组（工程 77）：一键修理身上 14 件，价格写在按钮上、点击即修不再二次确认。
	# 工程 87：紫装献祭并排放在这里 —— 两者都是「就地处理已有装备」，共用一行说明后
	# 菜单高度不增、维护组也从单按钮变成成对（不再留孤格）。
	var repair_grid := _build_group(service_content, "ui.blacksmith_panel.group_maintain",
		"ui.blacksmith_panel.hint_maintain")
	_repair = _make_service(repair_grid, "ui.blacksmith_panel.repair", true)
	_repair.pressed.connect(_on_repair)
	var sacrifice := _make_service(repair_grid, "ui.sacrifice.title", false)
	sacrifice.tooltip_text = Localization.tr_key("ui.sacrifice.hint_short")
	sacrifice.pressed.connect(_open_fusion.bind(EquipmentFusion.SACRIFICE))
	_fusion_buttons.append(sacrifice)
	# 离开与继续固定在底部操作行，不再混进服务网格。
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 8)
	root.add_child(_footer)
	_leave = _make_footer_action("ui.blacksmith_panel.p008", false)
	_leave.pressed.connect(func() -> void: set_open(false))
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(footer_spacer)
	_continue = _make_footer_action("ui.blacksmith_panel.p003", true)
	_continue.pressed.connect(_show_menu)
	# 交给浮窗层按可见区结算服务区高度（F-P2-3）：放得下就是内容高度，放不下才出滚动条。
	_center.set_content_scroll(_service_scroll)

## 服务分组：小标题 + 一句话说明 + 两列按钮，替代原来挤在滚动区里的三段长文。
func _build_group(parent: VBoxContainer, title_key: String, hint_key: String) -> GridContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 4)
	parent.add_child(group)
	var title := Label.new()
	title.text = Localization.tr_key(title_key)
	PanelChrome.style_section(title)
	group.add_child(title)
	group.add_child(_make_hint(hint_key))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	group.add_child(grid)
	_service_grids.append(grid)
	return grid

## 12px 灰字一句话说明；允许折行，避免窄面板被长句撑宽。
func _make_hint(key: String) -> Label:
	var hint := Label.new()
	hint.text = Localization.tr_key(key)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", PanelChrome.MUTED)
	return hint

## 服务按钮填满所在列，保证同一横排宽度一致。
func _make_service(parent: Control, key: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = Localization.tr_key(key)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	PanelChrome.style_action(button, primary)
	return button

## 底部固定行按钮：等宽，避免贴两端显得单薄。
func _make_footer_action(key: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = Localization.tr_key(key)
	button.custom_minimum_size.x = 140.0
	_footer.add_child(button)
	PanelChrome.style_action(button, primary)
	return button

func _show_menu() -> void:
	_continue.visible = false
	_upgrade.visible = true
	_reforge.visible = true
	_refresh_repair_button()
	_repair.visible = true
	for button in _fusion_buttons:
		button.visible = true
	_greeting_card.visible = false
	_service_card.visible = true
	# 问候卡与服务卡互换后最小尺寸会变，重新触发一次结算再抢焦点。
	_center.set_content_scroll(_service_scroll)
	_upgrade.grab_focus()

## 修理按钮：价格直接写在按钮上（点击即修，多一层确认就是纯摩擦）。
## 全身无破损置灰「装备完好」；重铸配置缺失时也置灰（费用算不出来）。
## 🔴 显示价与 `_on_repair` 的扣费必须同源：两处都读 `ServiceFee.repair_rate_for(_portable)`，
##    并且取整都走 `ServiceFee.apply_repair()`（与 `GameState.repair_equipment` 内部的 `round` 一致）。
##    只改一处 = 按钮写一个数、实扣另一个数，玩家对账立刻发现。
func _refresh_repair_button() -> void:
	if _repair == null:
		return
	var maximum := Durability.max_durability()
	var total := 0
	var damaged := 0
	for slot_id in GameState.equipment.keys():
		var it = GameState.equipment[slot_id]
		if not it is Dictionary:
			continue
		var missing := maximum - Durability.current(it)
		if missing <= 0:
			continue
		damaged += 1
		var full := Durability.repair_full_price(it)
		if full < 0:
			_repair.text = Localization.tr_key("ui.blacksmith_panel.repair")
			_repair.disabled = true
			return
		total += maxi(1, int(ceil(float(full) * float(missing) / float(maximum))))
	if damaged == 0:
		_repair.text = Localization.tr_key("ui.blacksmith_panel.repair_full")
		_repair.disabled = true
	else:
		total = ServiceFee.apply_repair(total, ServiceFee.repair_rate_for(_portable))
		_repair.text = Localization.tr_key("ui.blacksmith_panel.repair_cost", [total])
		_repair.disabled = false

## 一键修理（工程 77）：只修身上 14 件；金币不足一件不修，与合成「校验失败不消耗」同口径。
func _on_repair() -> void:
	var result := GameState.repair_equipment(ServiceFee.repair_rate_for(_portable))
	if bool(result.get("ok", false)):
		EventBus.toast_requested.emit(Localization.tr_key("ui.durability.repair_done",
			[int(result.get("repaired", 0)), int(result.get("cost", 0))]), "pickup")
		_refresh_repair_button()
	else:
		EventBus.toast_requested.emit(String(result.get("reason", "修理失败")), "danger")

func _open_upgrade() -> void:
	set_open(false)
	EventBus.upgrade_panel_requested.emit(_portable)

## M10-8：铁匠服务菜单第二项。与升星同构 —— 先关铁匠再开重铸面板。
func _open_reforge() -> void:
	set_open(false)
	EventBus.reforge_panel_requested.emit(_portable)

## 铁匠菜单进入对应合成服务；对话窗口先关闭，避免层叠遮挡。
func _open_fusion(mode: String) -> void:
	set_open(false)
	EventBus.equipment_fusion_panel_requested.emit(mode, _portable)
