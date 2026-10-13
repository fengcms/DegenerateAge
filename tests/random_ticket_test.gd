extends Node
## 背包/快捷栏共用的随机券落点与消费边界，不写真实存档。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "wild_trial"
	GameState.inventory[0] = {"kind": "misc", "itemId": "misc_random_ticket", "count": 2}
	check(HotbarConfig.valid_entry({"kind": "item", "id": "misc_random_ticket"}), "随机券可绑定快捷栏")
	check(not GameState.use_item(0).get("ok", false) and GameState.inventory[0].count == 2,
		"无世界时不消耗随机券")
	var world := preload("res://scenes/Game.tscn").instantiate()
	add_child(world)
	var player := world.get_node("Entities/Player") as PlayerCharacter
	player.set_physics_process(false)
	var origin := player.global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var used := TravelItem.use_random_ticket(0, rng)
	check(bool(used.get("ok", false)) and GameState.inventory[0].count == 1, "传送成功才消耗一张")
	check(GameState.current_map == "wild_trial" and player.global_position != origin, "随机券只在本图移动")
	var ground := world.get_node("Ground") as IsoGround
	check(ground.is_walkable_cell(Vector2i(Iso.world_to_grid(player.global_position).round())), "落在可通行格")
	GameState.player.hp = 0
	check(not GameState.use_item(0).get("ok", false) and GameState.inventory[0].count == 1, "死亡时不消耗")
	GameState.player.hp = GameState.max_hp()
	player.is_dead = true
	check(not GameState.use_item(0).get("ok", false) and GameState.inventory[0].count == 1, "死亡态不绕过校验")
	player.is_dead = false
	check(GameState.use_item(0).get("ok", false) and GameState.inventory[0] == null, "背包统一入口消耗末张")
	world.queue_free()
	await get_tree().process_frame
	GameState.current_map = "corruption_source"
	var cave_world := preload("res://scenes/Game.tscn").instantiate()
	add_child(cave_world)
	var cave_player := cave_world.get_node("Entities/Player") as PlayerCharacter
	cave_player.set_physics_process(false)
	var cave_ground := cave_world.get_node("Ground") as IsoGround
	rng.seed = 9
	var cave_destination := TravelItem._random_destination(cave_ground, cave_player.global_position, rng)
	check(cave_destination.is_finite() and cave_ground.is_walkable_cell(Vector2i(Iso.world_to_grid(cave_destination).round()))
		and not cave_ground.route(cave_player.global_position, cave_destination).is_empty(),
		"洞穴随机落点需同连通区且可通行")
	if failures.is_empty():
		print("RandomTicketTest: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
