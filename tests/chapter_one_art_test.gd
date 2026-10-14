extends Node

var failures: Array[String] = []

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "camp"
	GameState.save_pos = Iso.grid_to_world(Vector2i(20, 20))
	GameState.has_save_pos = true
	var camp := preload("res://scenes/Game.tscn").instantiate()
	add_child(camp)
	await get_tree().process_frame
	var roles := {}
	for node in camp.get_node("Npcs").get_children():
		var npc := node as Npc
		if npc == null:
			continue
		roles[npc.role] = true
		var art := npc.get_node_or_null("RoleArt") as Sprite2D
		expect(art != null and art.texture.get_size() == Vector2(512, 80), "Eight-direction NPC art: " + npc.role)
		var name_label := npc.get_node("NameLabel") as Label
		expect(name_label.position.y + name_label.size.y <= -64.0, "NPC name clears sprite head: " + npc.role)
		expect(npc.contains_screen_point(npc.get_global_transform_with_canvas().origin + Vector2(0, -55)), "NPC sprite head remains clickable: " + npc.role)
		expect(npc.contains_screen_point(name_label.get_global_transform_with_canvas() * (name_label.size * 0.5)), "Moved NPC name remains clickable: " + npc.role)
	for role in ["quest", "shop", "blacksmith", "warehouse", "carter"]:
		expect(roles.has(role), "Camp contains role " + role)
	var dummy_count := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var monster := node as Monster
		if monster != null and monster.monster_id == "training_dummy":
			dummy_count += 1
			expect(monster.dummy_art != null and monster.dummy_art.texture.get_size() == Vector2(192, 80), "Dummy has three visual states")
			expect(monster._head_hp_y() <= -68.0, "Dummy HP bar clears sprite head")
			monster.take_hit({"damage": 1, "miss": false}, null)
			monster._physics_process(0.01)
			expect(monster.dummy_art.frame == 1, "Dummy should visibly react to a hit")
	expect(dummy_count == 3, "Camp retains three training dummies")
	camp.queue_free()
	await get_tree().process_frame

	for map_id in ["wild_trial", "ash_land"]:
		GameState.reset_to_defaults()
		GameState.current_map = map_id
		GameState.save_pos = Iso.grid_to_world(Vector2i(30, 30))
		GameState.has_save_pos = true
		var world := preload("res://scenes/Game.tscn").instantiate()
		add_child(world)
		await get_tree().process_frame
		var found := {}
		for node in get_tree().get_nodes_in_group("enemies"):
			var monster := node as Monster
			if monster == null or monster.monster_id not in ["shellback_bug", "ash_wraith"]:
				continue
			found[monster.monster_id] = true
			expect(monster.sample_art != null, "New enemy art attached: " + monster.monster_id)
			if monster.sample_art != null:
				expect(is_equal_approx(monster._head_hp_y(), -46.0), "Existing monster HP bar position stays unchanged: " + monster.monster_id)
				var expected := Vector2(640, 640) if monster.monster_id == "shellback_bug" else Vector2(512, 640)
				expect(monster.sample_art.texture.get_size() == expected, "Enemy atlas dimensions: " + monster.monster_id)
				expect(monster.sample_art.hframes == 8 and monster.sample_art.vframes == 8, "Enemy has eight directions and pose rows")
		expect(found.has("shellback_bug"), map_id + " contains shellback bug")
		if map_id == "ash_land":
			expect(found.has("ash_wraith"), "Ash land contains ash wraith")
		world.queue_free()
		await get_tree().process_frame
	if failures.is_empty():
		print("[ChapterOneArtTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
