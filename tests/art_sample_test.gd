extends Node

var failures: Array[String] = []

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "wild_trial"
	var sample := preload("res://scenes/ArtSample.tscn").instantiate()
	add_child(sample)
	await get_tree().process_frame
	var player := sample.get_node("Main/Game/Entities/Player") as PlayerCharacter
	var ground := sample.get_node("Main/Game/Ground") as IsoGround
	expect(GameState.current_map == "wild_trial", "Sample map must survive autoload initialization")
	expect(GameState.inventory_used() == 3, "Sample must contain three item examples")
	expect(SaveManager.active_slot == -1 and not SaveManager.autosave_enabled, "Sample must not autosave")
	expect(ground.sample_camp_theme, "Sample ground theme must be active")
	expect(player.sample_art.texture.get_size() == Vector2(512, 640), "Guardian frame atlas dimensions")
	expect((player.get_node("CollisionShape2D").shape as CircleShape2D).radius == 12, "Art must not enlarge player collision")
	var art := player.sample_art
	player.set_physics_process(false)
	for i in range(8):
		art.face(Vector2.from_angle(PI / 2 + i * PI / 4))
		expect(art.facing == i, "Screen direction %d" % i)
	player.velocity = Vector2(100, 0)
	art._process(0.1)
	expect(art.pose == "walk" and art.facing == 6, "East movement should animate east walk")
	player.velocity = Vector2.ZERO
	art.attack(Vector2.DOWN, 0.8)
	art._process(0.01)
	expect(art.pose == "attack" and art.facing == 0, "Attack should face actual target")
	art.hit()
	art._process(0.01)
	expect(art.pose == "hit", "Hit should override attack visually")
	player.is_dead = true
	art._process(0.01)
	expect(art.pose == "death" and art.frame_coords.y == 7, "Dead actor should display death row")
	player.is_dead = false
	var wolf: Monster
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		if enemy is Monster and enemy.monster_id == "wolf_corrupted":
			wolf = enemy
	if wolf != null:
		expect(wolf.sample_art.texture.get_size() == Vector2(640, 640), "Wolf atlas dimensions")
		expect(wolf.radius == 13, "Art must not change combat radius")
		var before := wolf.hp
		var hit := {"damage": 1, "miss": false, "critical": false}
		wolf.take_hit(hit, player)
		expect(wolf.hp == before - 1, "Art hit state must not cause duplicate damage")
	else:
		expect(false, "Sample wolves must exist")
	for id in ["weapon_starter", "potion_hp_small", "spirit_shard"]:
		var item := ItemFactory.make_any(id)
		expect(SampleArt.icon_for(item).get_size() == Vector2(48, 48), "48px icon for " + id)
		expect(SampleArt.ground_for(item).get_size() == Vector2(32, 32), "32px ground item for " + id)
	expect(SampleArt.icon_for(ItemFactory.make_any("ring_basic")) == null, "Unmade icons must preserve fallback")
	var panel := sample.get_node("Main/UI/InventoryPanel")
	panel.set_open(true)
	await get_tree().process_frame
	var buttons: Array = panel.get("_bag_buttons")
	for i in range(3):
		expect(buttons[i].icon != null and buttons[i].text.is_empty(), "Inventory should display icon %d" % i)
	panel.set_open(false)
	for tile in IsoGround.CAMP_TILES:
		expect(tile.get_size() == Vector2(64, 32), "2:1 logical ground footprint")
	if failures.is_empty():
		print("[ArtSampleTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for message in failures:
			push_error(message)
		get_tree().quit(1)
