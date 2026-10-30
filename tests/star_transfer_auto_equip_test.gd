extends Node
var failures: Array[String] = []
var rng := RandomNumberGenerator.new()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func setup_pair(slot: String, worn: bool = true, player_level: int = 200) -> Array[Dictionary]:
	GameState.reset_to_defaults()
	GameState.player.level = player_level
	GameState.gold = 10000000
	var kind := String(Equipment.slot_def(slot).kind)
	var id := EquipmentFusion.template_for(51, kind)
	var old := ItemFactory.make_equip_exact(id, 100, "legendary", rng)
	old.star = 12
	var fresh := ItemFactory.make_equip_exact(id, 110, "legendary", rng)
	if worn:
		GameState.equipment[slot] = old
	else:
		GameState.inventory[1] = old
	GameState.inventory[0] = fresh
	return [old.duplicate(true), fresh.duplicate(true)]

func _ready() -> void:
	rng.seed = 12612
	for slot in Equipment.SLOT_DEFS:
		var pair := setup_pair(slot.id)
		var sibling := ""
		var slots := Equipment.slots_for_kind(slot.kind)
		var other := {}
		if slots.size() == 2:
			sibling = slots[0] if slots[1] == slot.id else slots[1]
			other = ItemFactory.make_equip_exact(EquipmentFusion.template_for(51, slot.kind), 100, "legendary", rng)
			GameState.equipment[sibling] = other
		var gold_before := GameState.gold
		var result := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, pair, "", rng)
		check(result.ok and result.equipped and result.slot == slot.id and result.index == -1, "按实际旧槽自动穿回 " + slot.id)
		check(GameState.equipment[slot.id].instanceId == result.item.instanceId and GameState.inventory_used() == 0, "产物只存在穿戴栏 " + slot.id)
		check(GameState.find_owned_item(pair[0].instanceId).is_empty() and GameState.find_owned_item(pair[1].instanceId).is_empty(), "两件旧材料仅消耗一次")
		check(GameState.gold == gold_before - result.cost and result.item.star == 12, "按原费用结算并保留12星")
		if not sibling.is_empty():
			check(GameState.equipment[sibling] == other, "不改动另一双槽 " + sibling)
		check(SaveManager._valid_item(result.item) and not ReforgeAffixes.unlocked(result.item), "自动穿戴仍是合法四词条新实例")
	var hp_pair := setup_pair("armor")
	GameState.player.hp = GameState.max_hp()
	GameState.player.mp = GameState.max_mp()
	var hp_before := int(GameState.player.hp)
	var mp_before := int(GameState.player.mp)
	var hp_result := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, hp_pair, "", rng)
	check(hp_result.ok and GameState.player.hp == mini(hp_before, GameState.max_hp())
		and GameState.player.mp == mini(mp_before, GameState.max_mp()), "血蓝仅按最终穿戴状态收敛一次")
	var rune_pair := setup_pair("weapon")
	GameState.inventory[1] = ItemFactory.make_any("rune_diamond", 4)
	var rune_result := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, rune_pair, "", rng,
		["rune_diamond", "rune_diamond", "rune_diamond", "rune_diamond"])
	check(rune_result.ok and rune_result.equipped and rune_result.tries == 17 and GameState.inventory_used() == 0,
		"自动穿戴路径如意只扣一次且17次取优")
	var pair := setup_pair("weapon", true, 1)
	var low := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, pair, "", rng)
	check(low.ok and not low.equipped and GameState.equipment.weapon == null and GameState.inventory[low.index].instanceId == low.item.instanceId, "等级不足退回背包")
	pair = setup_pair("weapon", false)
	var bag := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, pair, "", rng)
	check(bag.ok and not bag.equipped and GameState.equipment.weapon == null and GameState.inventory[bag.index].instanceId == bag.item.instanceId, "背包旧料不自动穿戴")
	pair = setup_pair("ring_2")
	for i in range(1, GameState.inventory.size()):
		GameState.inventory[i] = ItemFactory.make_any("potion_hp_small", 99)
	var full := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, pair, "", rng)
	check(full.ok and full.equipped and GameState.inventory_used() == GameState.inventory.size() - 1, "满背包仍穿回原槽且材料格释放")
	var doc := SaveManager._collect()
	doc.slotId = 1
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(doc))
	check(SaveManager._is_valid_save(decoded), "自动穿戴状态可保存")
	SaveManager.apply_to_game_state(decoded)
	check(GameState.equipment.ring_2.instanceId == full.item.instanceId, "存档往返保留原槽产物")
	pair = setup_pair("weapon")
	var before := GameState.inventory.duplicate(true)
	var worn_before := GameState.equipment.duplicate(true)
	GameState.gold = 0
	var rejected := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, pair, "", rng)
	check(not rejected.ok and GameState.inventory == before and GameState.equipment == worn_before and GameState.gold == 0, "失败不脱装备不扣材料")
	await test_ui()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[StarTransferAutoEquipTest] 全部通过 ✅")
	get_tree().quit(0 if failures.is_empty() else 1)

func test_ui() -> void:
	var pair := setup_pair("weapon")
	var panel := preload("res://scenes/ui/EquipmentFusionPanel.tscn").instantiate()
	add_child(panel)
	panel._on_requested(EquipmentFusion.STAR_TRANSFER, true)
	panel._on_material_dropped(0, {"from": ItemSlot.ROLE_EQUIP, "slot_id": "weapon", "item": pair[0], "token": Warehouse.item_token(pair[0])})
	panel._on_material_dropped(1, {"from": ItemSlot.ROLE_BAG, "index": 0, "item": pair[1], "token": Warehouse.item_token(pair[1])})
	panel._on_confirm()
	check(panel._feedback.text.contains("自动穿回原槽位") and not panel._feedback.text.contains("该部位将空出"), "首次确认明确自动穿回")
	panel._on_confirm()
	check(GameState.equipment.weapon is Dictionary and GameState.equipment.weapon.instanceId != pair[0].instanceId and GameState.inventory_used() == 0, "真实UI结算自动穿戴")
	panel.queue_free()
	await get_tree().process_frame
