extends Node
## 第一章NPC、木桩与怪物美术集成回归；甲虫采用正式四帧八向，其余既有规格保持不变。

var failures: Array[String] = []

## 汇总检查失败并保留具体对象，最后统一退出。
func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

## 从正式Game装配营地和两张野外图，检查名称、点击范围、帧格与头顶位置。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "camp"
	GameState.save_pos = Iso.grid_to_world(Vector2i(20, 20))
	GameState.has_save_pos = true
	var camp := preload("res://scenes/Game.tscn").instantiate()
	add_child(camp)
	await get_tree().process_frame
	var player := camp.get_node("Entities/Player") as PlayerCharacter
	expect(is_equal_approx(player.sample_art.display_scale, 1.5), "Player art uses 150% scale")
	var roles := {}
	for node in camp.get_node("Npcs").get_children():
		var npc := node as Npc
		if npc == null:
			continue
		roles[npc.role] = true
		var art := npc.get_node_or_null("RoleArt") as Sprite2D
		expect(art != null and art.texture.get_size() == Vector2(512, 80), "Eight-direction NPC art: " + npc.role)
		expect(art != null and art.scale == Vector2(1.5, 1.5), "NPC art uses 150% scale: " + npc.role)
		var name_label := npc.get_node("NameLabel") as Label
		expect(name_label.position.y + name_label.size.y <= -96.0, "NPC name clears enlarged sprite head: " + npc.role)
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
				if monster.monster_id=="shellback_bug":
					expect(monster.sample_art is MonsterActorArt, "甲虫使用正式动画包")
					expect(is_equal_approx(monster._head_hp_y(),-78.0), "甲虫血条匹配新帧尺寸")
					expect(monster.sample_art.texture.get_size()==Vector2(512,768), "甲虫四帧八向图集尺寸")
					expect(monster.sample_art.hframes==4 and monster.sample_art.vframes==8, "甲虫横四帧、纵八向")
				else:
					expect(is_equal_approx(monster._head_hp_y(),-46.0), "灰烬幽魂血条保持不变")
					expect(monster.sample_art.texture.get_size()==Vector2(512,640), "灰烬幽魂图集尺寸保持不变")
					expect(monster.sample_art.hframes==8 and monster.sample_art.vframes==8, "既有八方向姿态行保持不变")
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
