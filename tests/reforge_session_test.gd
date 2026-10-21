extends Node
## 工程 87：重铸与背包并开会话 + 随机放入紫装 —— 7 组用例。
##
## 三条最值钱的断言：
## 1. **打开重铸自动开背包，关闭重铸保留背包** —— 与合成工作台同口径，玩家不用再按 I；
## 2. **在背包侧按 Esc / I 关闭时，重铸跟着退出** —— 只关一半会留下一个「没有材料来源」
##    的重铸面板，玩家只能再按一次 Esc；
## 3. **随机放入只改面板预选、不动背包** —— 快照断言，防止「点一下按钮就扣了材料」。

var failures: Array[String] = []
var _bag: Control
var _panel: Control

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[ReforgeSessionTest] " + label)

func _ready() -> void:
	_bag = (load("res://scenes/ui/InventoryPanel.tscn") as PackedScene).instantiate()
	_panel = (load("res://scenes/ui/ReforgePanel.tscn") as PackedScene).instantiate()
	add_child(_bag)
	add_child(_panel)
	_test_coexist_declaration()
	_test_open_opens_bag()
	_test_random_fill()
	_test_close_keeps_bag()
	_test_close_bag_closes_reforge()
	_test_other_panel_closes()
	_test_random_without_candidates()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[ReforgeSessionTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error(failure)
		print("[ReforgeSessionTest] 失败 %d 项" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

# ---- 工具 ----

func _make(item_id: String, level: int, quality: String, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if level > Balance.SOFTCAP_LEVEL:
		return ItemFactory.make_equip_exact(item_id, level, quality, rng)
	return ItemFactory.make_equip_roll(item_id, ItemFactory.tier_start_for_template(item_id),
		quality, rng)

## 目标固定占背包第 1 格，材料依次放后面，保证选择器默认选中目标。
func _setup_inventory(material_count: int) -> Dictionary:
	GameState.reset_to_defaults()
	GameState.gold = 1000000
	var target := _make("c6_equip_necklace", 100, "legendary", 3001)
	GameState.inventory[0] = target
	for i in range(material_count):
		GameState.inventory[1 + i] = _make("c6_equip_weapon", 100, "legendary", 3100 + i)
	return target

# ---- 1) 互斥表：重铸与背包双向放行 ----

func _test_coexist_declaration() -> void:
	check(GameState.panels_coexist("reforge", "inventory"), "重铸打开时背包应保持打开")
	check(GameState.panels_coexist("inventory", "reforge"), "背包打开时重铸应保持打开")
	check(not GameState.panels_coexist("reforge", "character"), "重铸不得与人物面板并开")
	check(not GameState.panels_coexist("character", "reforge"), "人物面板打开时重铸应关闭")

# ---- 2) 打开重铸自动开背包并选中目标 ----

func _test_open_opens_bag() -> void:
	var target := _setup_inventory(4)
	_panel.set_open(true)
	check(_panel.visible, "重铸面板应打开")
	check(_bag.visible, "打开重铸应自动打开背包")
	check(GameState.npc_dialog_open(), "重铸会话应暂停自动战斗挂机")
	var selected: Dictionary = _panel._selected_item()
	check(String(selected.get("instanceId", "")) == String(target.get("instanceId", "")),
		"默认应选中背包里的目标装备")
	check(String(_panel._random_refine.text) == Localization.tr_key("ui.reforge_panel.p022"),
		"随机按钮文案应走本地化，实际「%s」" % String(_panel._random_refine.text))

# ---- 3) 随机放入：填满 4 格、只动预选、不动背包 ----

func _test_random_fill() -> void:
	var before := str(GameState.inventory)
	_panel._on_random_refine()
	var materials: Array = _panel.refine_materials()
	check(materials.size() == 4, "随机应填满 4 格，实际 %d" % materials.size())
	check(str(GameState.inventory) == before, "随机放入不得修改背包")
	check(String(_panel._feedback.text).is_empty(), "成功时不应留下错误提示")
	check(not String(_panel._refine_hint.text).contains("ui.reforge_panel"),
		"下限提示应走本地化，实际「%s」" % String(_panel._refine_hint.text))
	check(String(_panel._refine_hint.text).contains("60"),
		"4 件同档的下限应为 60%%，实际提示「%s」" % String(_panel._refine_hint.text))
	var target_id := String(_panel._selected_item().get("instanceId", ""))
	for item in materials:
		check(String(item.get("instanceId", "")) != target_id, "目标自身不得被随机投入")

# ---- 4) 关闭重铸保留背包，并清空预选 ----

func _test_close_keeps_bag() -> void:
	_panel.set_open(false)
	check(not _panel.visible, "重铸应关闭")
	check(_bag.visible, "关闭重铸应保留背包（与合成工作台一致）")
	check(_panel.refine_materials().is_empty(), "关闭重铸应清空材料预选")

# ---- 5) 关闭背包 = 退出整场会话 ----

func _test_close_bag_closes_reforge() -> void:
	_panel.set_open(true)
	check(_panel.visible and _bag.visible, "重铸与背包应并开")
	_bag.set_open(false)
	check(not _bag.visible, "背包应关闭")
	check(not _panel.visible, "关闭会话中的背包也应关闭重铸")

# ---- 6) 其他面板打开时重铸自动关闭 ----

func _test_other_panel_closes() -> void:
	_panel.set_open(true)
	check(_panel.visible and _bag.visible, "重新开会话应再次并开")
	EventBus.panel_opened.emit("character")
	check(not _panel.visible, "人物面板打开时重铸应关闭")
	check(_bag.visible, "背包与人物面板同属浮窗组，应保持打开")
	_bag.set_open(false)

# ---- 7) 没有候选：提示且保留原有预选 ----

func _test_random_without_candidates() -> void:
	_setup_inventory(1)
	_panel.set_open(true)
	_panel.drop_refine_material(0, 1)
	check(_panel.refine_materials().size() == 1, "手动投入 1 件材料应生效")
	GameState.inventory[1]["favorite"] = true
	_panel._on_random_refine()
	check(String(_panel._feedback.text) == Localization.tr_key("ui.reforge_panel.p024"),
		"无候选时应提示原因，实际「%s」" % String(_panel._feedback.text))
	check(_panel.refine_materials().size() == 1, "无候选时应保留原有预选")
	_panel.set_open(false)
	_bag.set_open(false)
