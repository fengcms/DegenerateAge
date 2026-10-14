extends Node

var failures: Array[String] = []

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		print("[MonsterAnimation] FAIL: " + message)

func _ready() -> void:
	GameState.reset_to_defaults()
	SaveManager.active_slot = -1
	SaveManager.autosave_enabled = false
	GameState.current_map = "wild_trial"
	GameState.save_pos = Iso.grid_to_world(Vector2i(30, 30))
	GameState.has_save_pos = true
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var world: Node2D = main.get_node("Game")
	var player: PlayerCharacter = world.get_node("Entities/Player")
	player.set_physics_process(false)
	player.get_node("AutoPilot").set_physics_process(false)
	world.get_node("Spawner").set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	var offsets := [Vector2(-220, -35), Vector2(-75, -110), Vector2(125, -55), Vector2(265, 125)]
	var monsters: Array[Monster] = []
	for i in range(MonsterActorArt.IDS.size()):
		var monster: Monster = load("res://scenes/entities/Monster.tscn").instantiate()
		monster.monster_id = MonsterActorArt.IDS[i]
		world.get_node("Entities").add_child(monster)
		monster.global_position = player.global_position + offsets[i]
		monster.set_physics_process(false)
		monsters.append(monster)
		expect(monster.sample_art is MonsterActorArt, "runtime art attached: " + monster.monster_id)
		var art := monster.sample_art as MonsterActorArt
		if art == null:
			continue
		art.set_process(false)
		for d in range(8):
			monster.velocity = Vector2.from_angle(PI / 2.0 + d * PI / 4.0) * 30.0
			art._process(0.2)
			expect(art.pose == "walk" and art.frame_coords.y == d, "eight-way movement " + str(d))
		monster.velocity = Vector2.ZERO
		art._process(0.01)
		expect(art.pose == "idle", "stopping returns to idle")
		var hp := int(GameState.player.hp)
		art.attack(Vector2.LEFT, monster.attack_interval)
		expect(art.pose == "attack" and art.phase == int(art.definitions.attack.contact), "attack starts at actual contact")
		art._process(0.1)
		expect(int(GameState.player.hp) == hp, "animation never applies damage")
		art.hit()
		art._process(0.05)
		expect(art.pose == "hit", "hit uses own atlas")
		art._process(0.3)
		art.face(Vector2(-1, 1))
		art._process(0.01)
		expect(monster._head_hp_y() < -80.0, "head bar clears full sprite")
		var click := monster.get_global_transform_with_canvas() * Vector2(0, -70)
		expect(world.enemy_at_screen(click) == monster, "sprite head can be clicked")
	var boss := monsters[-1]
	var boss_art := boss.sample_art as MonsterActorArt
	boss.global_position = player.global_position + Vector2(50, 0)
	boss.hp = int(boss.max_hp * 0.5)
	GameState.player.dodge = 0.0
	GameState.player.hp = GameState.max_hp()
	player._invuln = 0.0
	var before := int(GameState.player.hp)
	boss._update_boss(0.0)
	boss_art._process(0.3)
	expect(boss_art.pose == "stomp" and boss_art.phase < int(boss_art.definitions.stomp.contact), "warning holds wind-up")
	boss._update_boss(0.79)
	boss_art._process(0.0)
	expect(int(GameState.player.hp) == before, "stomp warning causes no early damage")
	boss._update_boss(0.02)
	expect(boss_art.pose == "stomp" and boss_art.phase == int(boss_art.definitions.stomp.contact), "physics impact preserves stomp art")
	var after := int(GameState.player.hp)
	expect(after < before, "stomp damage resolves on original warning end")
	boss_art._process(0.1)
	expect(int(GameState.player.hp) == after, "recovery does not hit again")
	boss_art._process(0.3)
	boss.hp = int(boss.max_hp * 0.25)
	boss._stomp_cooldown = 5.0
	boss._update_boss(0.0)
	expect(boss_art.pose == "enrage_summon", "phase three plays roar")
	boss_art.hit()
	expect(boss_art.pose == "enrage_summon", "hits do not cancel phase roar")
	boss_art._process(0.6)
	boss.global_position = player.global_position + offsets[3]
	player.select_target(boss)
	boss._announce_boss_hp()
	if DisplayServer.get_name() != "headless":
		for spawned in get_tree().get_nodes_in_group("enemies"):
			if spawned not in monsters:
				spawned.queue_free()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_monster_animation_integration.png")
	# Animation is visible for its full duration; settlement still happens once immediately.
	boss.take_hit({"damage":999999,"miss":false})
	expect(boss.is_dead and boss_art.pose == "death", "death begins immediately")
	boss_art._process(0.65)
	expect(boss_art.pose == "death" and boss_art.phase >= 5, "late death frames exist before removal")
	await get_tree().create_timer(0.4).timeout
	expect(is_instance_valid(boss) and is_equal_approx(boss.modulate.a, 1.0), "full death animation precedes fading")
	expect((boss.get_node("CollisionShape2D") as CollisionShape2D).disabled, "visible corpse never blocks movement")
	await get_tree().create_timer(0.8).timeout
	expect(not is_instance_valid(boss), "corpse removed after death and fade")
	main.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("[MonsterAnimation] PASS: directional states, clicks, warning/impact, roar, death lifecycle")
	get_tree().quit(0 if failures.is_empty() else 1)
