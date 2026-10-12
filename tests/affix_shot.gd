extends Node
## 精英六词缀视觉检查；测试场景禁用自动存档。运行后输出截图并退出。
func _ready() -> void:
	GameState.reset_to_defaults()
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var world: Node2D = main.get_node("Game")
	world.get_node("Spawner").set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	var player: PlayerCharacter = main.get_node("Game/Entities/Player")
	var tpl: Dictionary = DataLoader.get_entry("monsters", "elite_wolf_king")
	var original := tpl.duplicate(true)
	var ids := ["rage", "frost", "hard", "fast", "summon", "vampire"]
	for i in range(ids.size()):
		tpl.affixPool = [ids[i]]
		tpl.affixCount = [1, 1]
		var monster := (load("res://scenes/entities/Monster.tscn") as PackedScene).instantiate() as Monster
		monster.monster_id = "elite_wolf_king"
		monster.position = player.position + Vector2((i % 3 - 1) * 260, -150 if i < 3 else 120)
		world.add_child(monster)
		monster.set_physics_process(false)
		if i == 0:
			EventBus.target_changed.emit(monster)
	tpl.clear()
	tpl.merge(original, true)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var path := "/tmp/degenerateage_elite_affixes.png"
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("[AffixShot] ", path, " result=", error)
	get_tree().quit(0 if error == OK else 1)
