extends Node2D
## Isolated playable art review: uses real combat/UI without touching save files.

func _prepare() -> void:
	GameState.reset_to_defaults()
	GameState.menu_mode = "world"
	GameState.current_map = "wild_trial"
	GameState.visited_maps = ["camp", "wild_trial"]
	GameState.save_pos = Iso.grid_to_world(Vector2i(20, 20))
	GameState.has_save_pos = true
	GameState.inventory[0] = ItemFactory.make_any("weapon_starter")
	GameState.inventory[1] = ItemFactory.make_any("potion_hp_small")
	GameState.inventory[1]["count"] = 8
	GameState.inventory[2] = ItemFactory.make_any("spirit_shard")
	GameState.inventory[2]["count"] = 3

func _ready() -> void:
	_prepare()
	SaveManager.active_slot = -1
	SaveManager.autosave_enabled = false
	var main := preload("res://scenes/Main.tscn").instantiate()
	main.name = "Main"
	(main.get_node("Game/Ground") as IsoGround).sample_camp_theme = true
	add_child(main)
	print("[ArtSample] map=", GameState.current_map, " bag=", GameState.inventory_used())
	var ground := $Main/Game/Ground as IsoGround
	ground.sample_camp_theme = true
	ground.queue_redraw()
	var player := $Main/Game/Entities/Player as PlayerCharacter
	# Existing rest-zone rules stay active. This encounter is outside them.
	var index := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Monster and enemy.monster_id == "wolf_corrupted":
			enemy.position = player.position + Vector2(240 + (index % 3) * 95, -60 + (index / 3) * 130)
			enemy.spawn_position = enemy.position
			enemy.sample_art.face(player.global_position - enemy.global_position)
			index += 1
	# A small non-modal legend is useful when opened directly from the editor.
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var label := Label.new()
	label.text = "美术可玩样板 · WASD移动 · 点击野狼攻击 · I背包 · F自动战斗"
	label.position = Vector2(20, 180)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("e6ddc6"))
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	GameState.emit_all()
	if OS.get_cmdline_user_args().has("--art-capture"):
		capture_review.call_deferred()

func capture_review() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://docs/素材设计/样板/可玩样板-v1/"
	get_viewport().get_texture().get_image().save_png(path + "world.png")
	var panel := $Main/UI/InventoryPanel
	panel.set_open(true)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path + "inventory.png")
	panel.set_open(false)
	GameState.settings.mapScale = 1.5
	SettingsRuntime.apply_map_scale_to($Main/Game/Entities/Player/Camera2D)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path + "world_150.png")
	GameState.settings.mapScale = 0.8
	SettingsRuntime.apply_map_scale_to($Main/Game/Entities/Player/Camera2D)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path + "world_80.png")
	print("[ArtSample] review captures saved")
	get_tree().quit()
