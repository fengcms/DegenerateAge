extends Node
## 实际地面物与背包联动，避免死亡时复制或误删穿戴装备。

const Penalty = preload("res://scripts/systems/death_penalty.gd")

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "wild_trial"
	var loot_root := Node2D.new()
	loot_root.add_to_group("loot_root")
	add_child(loot_root)
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(1000, 1000)
	var bag_equip := ItemFactory.make_equip("weapon_starter")
	GameState.inventory[0] = bag_equip.duplicate(true)
	GameState.inventory[1] = {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	GameState.warehouse[0] = ItemFactory.make_equip("weapon_starter")
	var worn := ItemFactory.make_equip("weapon_starter")
	GameState.equipment["weapon"] = worn.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 10
	var result: Dictionary = Penalty.drop_one(player, rng)
	check(not result.is_empty() and GameState.inventory[0] == null, "背包装备只移走一次")
	check(loot_root.get_child_count() == 1, "死亡处生成地面物")
	var drop := loot_root.get_child(0) as GroundItem
	check(drop != null and drop.item == bag_equip and not drop.auto_claim and not drop.persistent,
		"掉落保留原装备实例且需拾取")
	check(GameState.inventory[1].count == 3 and GameState.equipment["weapon"] == worn
		and GameState.warehouse[0] is Dictionary, "药水、已穿戴与仓库不受影响")
	check(Penalty.drop_one(player, rng).is_empty(), "无背包装备时无额外惩罚")
	# 处于正常游戏状态时，走原有点击收取通道。
	GameState.auto_pickup_on = false
	check(drop._try_pickup(), "原地复活后可重新拾取")
	check(GameState.inventory[0] == bag_equip, "拾取恢复同一实例而非重随机属性")
	GameState.damage_player(99999)
	player._begin_death()
	check(GameState.inventory[0] == null and loot_root.get_child_count() == 2,
		"真实死亡入口只移出一件背包装备")
	player._begin_death()
	check(loot_root.get_child_count() == 2, "重复死亡回调不会多掉装备")
	if failures.is_empty():
		print("DeathDropTest: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
