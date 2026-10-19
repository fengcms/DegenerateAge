extends Node
## 背包高分装备角标与对比浮层回归：用真实装备实例检验等级锁定、默认槽和穿戴门槛。
## 在隔离项目中运行，不读取或改写玩家的正式存档。

var failures: Array[String] = []

## 构建背包面板后逐次改变角色等级和装备，确认既有刷新信号能更新角标。
func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 10
	var old_shoes := ItemFactory.make_equip_roll("shoes_cloth", 1, "common", rng)
	var better_shoes := ItemFactory.make_equip_roll("c2_road_shoes", 11, "common", rng)
	var low_ring := ItemFactory.make_equip_roll("ring_basic", 1, "common", rng)
	var better_ring := ItemFactory.make_equip_roll("c2_road_ring", 11, "common", rng)
	check(not old_shoes.is_empty() and not better_shoes.is_empty() and not better_ring.is_empty(), "测试装备实例生成成功")
	GameState.equipment = Equipment.create()
	GameState.equipment.shoes = old_shoes
	GameState.player.level = 11
	GameState.inventory[0] = better_shoes
	var panel := preload("res://scripts/ui/inventory_panel.gd").new()
	add_child(panel)
	var slot: ItemSlot = panel._bag_buttons[0]
	var preview := Equipment.replacement_preview(GameState.equipment, better_shoes)
	check(bool(preview.get("score_increase", false)) and String(preview.get("slot_id", "")) == "shoes", "默认鞋槽评分确实提高")
	check(slot.upgrade_badge_state == ItemSlot.UpgradeBadge.LEVEL_LOCKED, "未达等级的高分装备显示灰箭头")
	check(slot._upgrade_marker.get_theme_color("font_color").is_equal_approx(ItemSlot.UPGRADE_LOCKED_COLOR), "灰箭头使用锁定色")
	var tip_text := _labels_text(slot._make_custom_tooltip(""))
	check(tip_text.contains("评分更高，需 Lv12 才可穿戴") and tip_text.contains("目标评分"), "浮层说明等级、目标和分差")
	check(not tip_text.contains("更强 ↑"), "等级不足时不出现可立即穿戴的绿色提示")
	var before_item: Variant = GameState.inventory[0]
	var equip_result := Equipment.equip_from_inventory(GameState.equipment, GameState.inventory, "shoes", 0, 11)
	check(not bool(equip_result.get("ok", false)) and GameState.inventory[0] == before_item and GameState.equipment.shoes == old_shoes,
		"灰箭头不绕过穿戴等级校验")
	GameState.player.level = 12
	EventBus.player_leveled.emit(12)
	check(slot.upgrade_badge_state == ItemSlot.UpgradeBadge.READY, "升级到门槛后由灰转绿")
	check(slot._upgrade_marker.get_theme_color("font_color").is_equal_approx(ItemSlot.UPGRADE_READY_COLOR), "绿箭头使用可穿戴色")
	GameState.equipment.shoes = better_shoes.duplicate(true)
	EventBus.equipment_changed.emit()
	check(slot.upgrade_badge_state == ItemSlot.UpgradeBadge.NONE, "同分装备不显示箭头")
	GameState.inventory[0] = old_shoes
	EventBus.inventory_changed.emit()
	check(slot.upgrade_badge_state == ItemSlot.UpgradeBadge.NONE, "低分装备不显示箭头")
	GameState.inventory[0] = null
	EventBus.inventory_changed.emit()
	check(slot.upgrade_badge_state == ItemSlot.UpgradeBadge.NONE and not slot._upgrade_marker.visible, "移走物品后清除箭头")
	GameState.equipment = Equipment.create()
	GameState.player.level = 1
	GameState.inventory[0] = old_shoes
	EventBus.inventory_changed.emit()
	check(slot.upgrade_badge_state == ItemSlot.UpgradeBadge.LEVEL_LOCKED, "空槽但等级未达也显示灰箭头")
	check(_labels_text(slot._make_custom_tooltip("")).contains("默认目标空槽"), "空槽浮层不声称胜过已穿装备")
	GameState.equipment = Equipment.create()
	GameState.equipment.ring_1 = low_ring
	GameState.player.level = 18
	GameState.inventory[0] = better_ring
	EventBus.inventory_changed.emit()
	var ring_preview := Equipment.replacement_preview(GameState.equipment, better_ring)
	check(String(ring_preview.get("slot_id", "")) == "ring_2" and slot.upgrade_badge_state == ItemSlot.UpgradeBadge.LEVEL_LOCKED,
		"双槽优先选择空槽并显示灰箭头")
	var ring_tip := _labels_text(slot._make_custom_tooltip(""))
	check(ring_tip.contains("戒指②") and ring_tip.contains("未穿着"), "双槽浮层说明默认空槽且保留另一槽比较")
	if failures.is_empty():
		print("[InventoryUpgradeBadgeTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

## 收集浮层中的所有标签文字，用于检验玩家实际看到的完整提示。
func _labels_text(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label else ""
	for child in node.get_children():
		result += _labels_text(child)
	return result

## 记录断言失败并在测试结束时统一报告，避免首个失败遮住后续状态问题。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
