extends Node
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	GameState.reset_to_defaults()
	check(DataLoader.validate_all().is_empty(), "配置校验")
	var index := 0
	for table in ["potions", "runes"]:
		for tpl in DataLoader.get_table(table):
			var item := ItemFactory.make_any(tpl.id, 999)
			check(ItemUtil.stack_max(item) == 999 and SaveManager._valid_item(item), tpl.id + " 上限999且可保存")
			var inv: Array = [ItemFactory.make_any(tpl.id, 998), null, null]
			var incoming := ItemFactory.make_any(tpl.id, 1001)
			check(Inventory.add(inv, incoming) and inv[0].count == 999 and inv[1].count == 999 and inv[2].count == 1 and incoming.count == 1001,
				tpl.id + " 跨堆分配998+1001=1999不丢数量")
			var full: Array = [ItemFactory.make_any(tpl.id, 998)]
			var before := full.duplicate(true)
			check(not Inventory.add(full, ItemFactory.make_any(tpl.id, 2)) and full == before, tpl.id + " 容量不足保持原样")
			var sorted: Array = [ItemFactory.make_any(tpl.id, 99), ItemFactory.make_any(tpl.id, 99), ItemFactory.make_any(tpl.id, 5)]
			Inventory.organize(sorted)
			check(Inventory.used_slots(sorted) == 1 and sorted[0].count == 203, tpl.id + " 旧99堆整理合并为203")
			var bad := item.duplicate(true)
			bad.count = 1000
			check(not SaveManager._valid_item(bad), tpl.id + " 单堆1000仍拒绝")
			GameState.inventory[index] = item.duplicate(true)
			GameState.warehouse[index] = item.duplicate(true)
			index += 1
	var saved := SaveManager._collect()
	saved.slotId = 1
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved))
	check(SaveManager._is_valid_save(decoded), "全部药品如意999的JSON存档校验")
	SaveManager.apply_to_game_state(decoded)
	for i in range(index):
		check(GameState.inventory[i].count == 999 and GameState.warehouse[i].count == 999, "背包仓库往返保留999")
	check(ItemUtil.stack_max(ItemFactory.make_any("gold_ingot")) == 99, "其他杂项堆叠不变")
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[PotionRuneStackTest] 全部通过 ✅")
	get_tree().quit(0 if failures.is_empty() else 1)
