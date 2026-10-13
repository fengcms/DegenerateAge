extends Node2D
## Playable chapter-one character review. F6 opens camp; --art-map selects a field map.

const REVIEW_ROOT := "res://docs/素材设计/样板/第一章角色-v1/"

func _ready() -> void:
	var map_id := "camp"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--art-map="):
			map_id = arg.trim_prefix("--art-map=")
	if not map_id in ["camp", "wild_trial", "ash_land"]:
		map_id = "camp"
	GameState.reset_to_defaults()
	GameState.menu_mode = "world"
	GameState.current_map = map_id
	GameState.visited_maps = ["camp", "wild_trial", "ash_land"]
	GameState.save_pos = Iso.grid_to_world(Vector2i(20, 20) if map_id == "camp" else Vector2i(30, 30))
	GameState.has_save_pos = true
	SaveManager.active_slot = -1
	SaveManager.autosave_enabled = false
	var main := preload("res://scenes/Main.tscn").instantiate()
	main.name = "Main"
	add_child(main)
	var label := Label.new()
	label.text = "第一章角色样板 · 营地 NPC / 木桩 · 野外裂壳虫 · 灰烬游魂 · WASD 移动 · E 交互"
	label.position = Vector2(20, 180)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("e6ddc6"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	layer.add_child(label)
	GameState.emit_all()
	if OS.get_cmdline_user_args().has("--art-capture"):
		capture_review.call_deferred(map_id)

func capture_review(map_id: String) -> void:
	var player := $Main/Game/Entities/Player as PlayerCharacter
	GameState.settings.mapScale = 1.0
	SettingsRuntime.apply_map_scale_to(player.get_node("Camera2D"))
	player.set_physics_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	# Keep the live scene's spawns unchanged; arrange visible examples only for a screenshot.
	if map_id != "camp":
		var offsets := [Vector2(160, -75), Vector2(235, 35), Vector2(145, 110), Vector2(-170, 45)]
		var quotas := {"wolf_corrupted": 2, "shellback_bug": 2} if map_id == "wild_trial" else {"ash_wraith": 2, "shellback_bug": 2}
		var counts := {}
		var placed := 0
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if not enemy is Monster or enemy.sample_art == null:
				continue
			var id := String(enemy.monster_id)
			if int(counts.get(id, 0)) >= int(quotas.get(id, 0)):
				continue
			counts[id] = int(counts.get(id, 0)) + 1
			enemy.global_position = player.global_position + offsets[placed % offsets.size()]
			enemy.sample_art.face(player.global_position - enemy.global_position)
			placed += 1
			if placed >= offsets.size():
				break
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var file := "camp.png" if map_id == "camp" else "wild.png" if map_id == "wild_trial" else "ash.png"
	get_viewport().get_texture().get_image().save_png(REVIEW_ROOT + file)
	print("[ChapterOneArtSample] captured ", file)
	get_tree().quit()
