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
	expect(player.sample_art.extra_texture.get_size() == Vector2(512, 160), "Guardian hit and sit atlas dimensions")
	expect(player.sample_art.walk_texture.get_size() == Vector2(512, 320), "Guardian four-pose walk atlas dimensions")
	expect((player.get_node("CollisionShape2D").shape as CircleShape2D).radius == 12, "Art must not enlarge player collision")
	var art := player.sample_art
	player.set_physics_process(false)
	art._process(0.01)
	expect(is_equal_approx(art.scale.x, 1.25) and art.offset == Vector2(-32, -64), "Guardian display scale keeps foot pivot")
	for i in range(8):
		art.face(Vector2.from_angle(PI / 2 + i * PI / 4))
		expect(art.facing == i, "Screen direction %d" % i)
	player.set_sitting(true)
	art._process(0.01)
	expect(art.pose == "sit" and art.frame_coords.y == 1 and art.vframes == 2, "Resting should use independent eight-way seated art")
	player.set_sitting(false)
	player.velocity = Vector2(100, 0)
	art._process(0.1)
	expect(art.pose == "walk" and art.facing == 6 and art.vframes == 4 and art.phase >= 0 and art.phase < 8, "East movement should use eight walk beats")
	var walk_rows := {}
	for i in range(8):
		art._process(0.1)
		walk_rows[art.frame_coords.y] = true
		expect(art.position.y >= -1.0 and art.position.y <= 0.0, "Walk pivot bob stays within one world pixel")
	expect(walk_rows.size() == 4, "Guardian walk should show all four distinct pose rows")
	player.velocity = Vector2.ZERO
	art.attack(Vector2.DOWN, 0.8)
	art._process(0.01)
	expect(art.pose == "attack" and art.facing == 0, "Attack should face actual target")
	art._process(0.1)
	expect(art.pose == "attack" and art.phase > 0, "Attack should progress through recovery phases")
	art.hit()
	art._process(0.01)
	expect(art.pose == "hit" and art.vframes == 2, "Separate guardian hit should override attack visually")
	player.is_dead = true
	art._process(0.01)
	expect(art.pose == "death" and art.vframes == 2 and art.frame_coords.y == 0, "Death should start with a brief recoil")
	art._process(0.61)
	expect(art.phase == 5 and art.vframes == 8 and art.frame_coords.y == 7, "Death transition should finish prone and hold")
	player.is_dead = false
	var wolf: Monster
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
		if enemy is Monster and enemy.monster_id == "wolf_corrupted":
			wolf = enemy
	if wolf != null:
		expect(wolf.sample_art.texture.get_size() == Vector2(640, 640), "Wolf atlas dimensions")
		expect(wolf.sample_art.walk_texture.get_size() == Vector2(640, 320), "Wolf four-pose walk atlas dimensions")
		for atlas in [art.walk_texture, wolf.sample_art.walk_texture]:
			var sheet := (atlas as Texture2D).get_image()
			var cell_w := sheet.get_width() / 8
			for row in range(4):
				for col in range(8):
					var frame_image := sheet.get_region(Rect2i(col * cell_w, row * 80, cell_w, 80))
					var used := frame_image.get_used_rect()
					expect(used.position.y + used.size.y == 64, "Walk frame must share the same foot anchor")
		wolf.sample_art.hit()
		wolf.sample_art._process(0.01)
		expect(wolf.sample_art.pose == "hit" and wolf.sample_art.frame_coords.y == 6, "Wolf keeps its independent recoil art")
		expect(wolf.radius == 13, "Art must not change combat radius")
		var before := wolf.hp
		var hit := {"damage": 1, "miss": false, "critical": false}
		wolf.take_hit(hit, player)
		expect(wolf.hp == before - 1, "Art hit state must not cause duplicate damage")
	else:
		expect(false, "Sample wolves must exist")
	for id in ["weapon_iron", "potion_hp_small", "spirit_shard"]:
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
