extends Node
## 工程 78 浮层样式统一：主题外壳 + 单卡两档 + 背包对比多卡零回退。
##
## 三组最值钱的断言：
## 1. **用例 1 钉死外壳** —— TooltipPanel 必须不透明深底 + 灰边 + 圆角 + 内衬。
##    半透明回潮 = 用户痛点（黑半透明浮层）复发，这里当场红。
## 2. **用例 2 钉死人物装备槽走结构化卡** —— 门卫一旦收窄回「只放背包装备」，
##    ROLE_EQUIP 就回退原生浮层，这正是本次要根治的直接痛点。
## 3. **用例 5 钉死背包对比多卡零回退** —— 三栏结构与「未穿着」占位是用户满意基准，
##    卡片结构被顺手改动（标题行挪位、少一栏）都会当场红。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[TooltipStyleTest] " + label)

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _ready() -> void:
	_test_theme_shell()
	_test_character_equip_card()
	_test_empty_slot_native()
	_test_text_card()
	_test_bag_compare_regression()
	_test_tray_text_priority()
	_test_structured_roles()
	if failures.is_empty():
		print("[TooltipStyleTest] 全部通过 ✅")
	else:
		for failure in failures:
			print("[TooltipStyleTest] 失败：" + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

## 收集控件树里全部 Label 文本（含子节点），用于断言卡片内容。
func _all_text(control: Control) -> String:
	var parts: Array[String] = []
	var stack: Array[Node] = [control]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Label:
			parts.append((node as Label).text)
		for child in node.get_children():
			stack.append(child)
	return "\n".join(parts)

## 用例 1：原生浮层外壳（TooltipPanel / TooltipLabel）—— 48 处简易浮层一次换装的根据地。
func _test_theme_shell() -> void:
	SettingsRuntime._apply_text_scale()
	var theme := ThemeDB.get_project_theme()
	check(theme != null, "项目主题存在（project.godot gui/theme/custom）")
	if theme == null:
		return
	var sb := theme.get_stylebox("panel", "TooltipPanel")
	check(sb is StyleBoxFlat, "TooltipPanel 外壳应是 StyleBoxFlat，实际 " + sb.get_class())
	if sb is StyleBoxFlat:
		var flat: StyleBoxFlat = sb as StyleBoxFlat
		check(flat.bg_color == Color("111820"), "外壳底色应为 111820，实际 " + str(flat.bg_color))
		check(flat.bg_color.a >= 1.0, "外壳不得半透明（黑半透明 = 用户痛点），实际 alpha " + str(flat.bg_color.a))
		check(flat.border_color == Color("74818a"), "外壳描边应为 74818a，实际 " + str(flat.border_color))
		check(flat.get_border_width(SIDE_LEFT) == 1 and flat.get_border_width(SIDE_TOP) == 1, "外壳描边应为 1px")
		check(flat.get_corner_radius(CORNER_TOP_LEFT) == 5, "外壳圆角应为 5，实际 " + str(flat.get_corner_radius(CORNER_TOP_LEFT)))
		check(flat.get_margin(SIDE_LEFT) == 10.0 and flat.get_margin(SIDE_TOP) == 8.0,
			"外壳内衬应为 10/8，实际 " + str(flat.get_margin(SIDE_LEFT)) + "/" + str(flat.get_margin(SIDE_TOP)))
	check(theme.get_color("font_color", "TooltipLabel") == Color("e1e7ee"),
		"原生提示文字应为 e1e7ee，实际 " + str(theme.get_color("font_color", "TooltipLabel")))

## 用例 2：人物装备槽（ROLE_EQUIP）走结构化卡 —— 本次直接痛点 + Q3 评分行。
## 用 EquipmentSlot 而非裸 ItemSlot：生产里人物槽就是 EquipmentSlot（item_slot._ready
## 的空槽标签依赖 slot_id），与真机同形。
func _test_character_equip_card() -> void:
	GameState.reset_to_defaults()
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", _rng(100))
	check(not item.is_empty(), "测试装备可生成")
	if item.is_empty():
		return
	var slot := EquipmentSlot.new()
	slot.role = ItemSlot.ROLE_EQUIP
	slot.slot_id = "weapon"
	slot.tooltip_heading = "武器"
	slot.item = item
	add_child(slot)
	var tip: Control = slot._make_custom_tooltip("应被结构化卡取代的原生文案") as Control
	check(tip != null, "人物装备槽（ROLE_EQUIP）不得回退原生浮层")
	if tip != null:
		check(tip is PanelContainer, "结构化卡应是品质描边卡（PanelContainer），实际 " + tip.get_class())
		var text := _all_text(tip)
		check(text.contains("武器"), "单卡标题应为槽位名，实际「" + text + "」")
		check(text.contains(Localization.tr_key("ui.durability.line",
			[Durability.current(item), Durability.max_durability()])), "单卡应含耐久行，实际「" + text + "」")
		check(text.contains("评分"), "单卡应含评分行（Q3），实际「" + text + "」")
		check(not text.contains("应被结构化卡取代的原生文案"), "结构化卡不得回显面板 tooltip_text")
		var sb := (tip as PanelContainer).get_theme_stylebox("panel")
		check(sb is StyleBoxFlat and (sb as StyleBoxFlat).border_color == ItemUtil.quality_color("epic"),
			"卡片描边应为品质色（epic）")
		tip.free()
	slot.free()
	GameState.reset_to_defaults()

## 用例 3：空槽保持原生（工程 78 已换壳），不弹大卡。
func _test_empty_slot_native() -> void:
	var slot := EquipmentSlot.new()
	slot.role = ItemSlot.ROLE_EQUIP
	slot.slot_id = "weapon"
	slot.tooltip_heading = "武器"
	slot.item = {}
	add_child(slot)
	check(slot._make_custom_tooltip("空槽提示") == null, "空槽应走原生浮层，不得弹结构化大卡")
	slot.free()

## 用例 4：背包非装备（药水/杂项）走文案卡 —— Q2，内容零改动。
func _test_text_card() -> void:
	GameState.reset_to_defaults()
	var potion := {"kind": "potion", "itemId": "potion_hp_small", "count": 1, "quality": "common"}
	var slot: ItemSlot = ItemSlot.new()
	slot.role = ItemSlot.ROLE_BAG
	slot.item = potion
	add_child(slot)
	var tip_text := "小瓶生命药水\n恢复 80\n双击使用"
	var tip: Control = slot._make_custom_tooltip(tip_text) as Control
	check(tip != null, "背包非装备（药水）应走文案卡")
	if tip != null:
		check(tip is PanelContainer, "文案卡应是卡片壳，实际 " + tip.get_class())
		var text := _all_text(tip)
		check(text == tip_text, "文案卡内容必须零改动沿用面板文案，实际「" + text + "」")
		tip.free()
	slot.free()

## 用例 5：背包装备对比多卡零回退 —— 用户满意基准，卡片结构不许变。
func _test_bag_compare_regression() -> void:
	GameState.reset_to_defaults()
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "rare", _rng(300))
	check(not item.is_empty(), "对比用装备可生成")
	if item.is_empty():
		return
	var slot: ItemSlot = ItemSlot.new()
	slot.role = ItemSlot.ROLE_BAG
	slot.item = item
	add_child(slot)
	var tip: Control = slot._make_custom_tooltip("") as Control
	check(tip != null, "背包装备应走对比多卡")
	if tip != null:
		check(tip is GridContainer, "对比多卡根节点是 GridContainer（多栏），实际 " + tip.get_class())
		var expect_cards := 1 + Equipment.slots_for_kind(Equipment.item_kind(item)).size()
		check(tip.get_child_count() == expect_cards,
			"对比多卡应有 " + str(expect_cards) + " 栏（背包候选 + 各穿戴槽），实际 " + str(tip.get_child_count()))
		if tip.get_child_count() == expect_cards:
			var worn_text := _all_text(tip.get_child(1) as Control)
			check(worn_text.contains(Localization.tr_key("ui.equip_tip.unworn")),
				"缺穿戴件时应保留「未穿着」栏，实际「" + worn_text + "」")
		tip.free()
	slot.free()
	GameState.reset_to_defaults()

## 用例 6：出售托盘装备优先文案卡（售价/单价行不许被结构化卡吃掉）。
func _test_tray_text_priority() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "epic", _rng(400))
	check(not item.is_empty(), "托盘用装备可生成")
	if item.is_empty():
		return
	var slot: ItemSlot = ItemSlot.new()
	slot.role = ItemSlot.ROLE_TRAY
	slot.tooltip_as_text = true
	slot.item = item
	add_child(slot)
	var tip_text := "名剑\n售价：1000"
	var tip: Control = slot._make_custom_tooltip(tip_text) as Control
	check(tip != null, "托盘装备应走文案卡")
	if tip != null:
		var text := _all_text(tip)
		check(text == tip_text, "托盘文案卡必须保留售价行，实际「" + text + "」")
		tip.free()
	slot.free()

## 用例 7：仓库 / 合成材料（默认不带 tooltip_as_text）走结构化卡。
func _test_structured_roles() -> void:
	var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "rare", _rng(500))
	check(not item.is_empty(), "仓库/合成用装备可生成")
	if item.is_empty():
		return
	for role in [ItemSlot.ROLE_WAREHOUSE, ItemSlot.ROLE_TRAY]:
		var slot: ItemSlot = ItemSlot.new()
		slot.role = role
		slot.item = item
		add_child(slot)
		var tip: Control = slot._make_custom_tooltip("原生文本") as Control
		check(tip != null and tip is PanelContainer, "仓库/合成材料（role " + str(role) + "）应走结构化卡")
		if tip != null:
			check(_all_text(tip).contains("评分"), "结构化卡应含评分行")
			check(not _all_text(tip).contains("原生文本"), "结构化卡不得回显面板 tooltip_text")
			tip.free()
		slot.free()
