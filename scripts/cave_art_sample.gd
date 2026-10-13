extends Node2D
## F6 review entry for the playable cave without changing a save slot.

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.menu_mode = "world"
	GameState.current_map = "corruption_source"
	GameState.visited_maps = ["camp", "wild_trial", "ash_land", "corruption_source"]
	var at_boss := OS.get_cmdline_user_args().has("--art-boss")
	GameState.save_pos = Iso.grid_to_world(Vector2i(37, 30) if at_boss else Vector2i(8, 25))
	GameState.has_save_pos = true
	SaveManager.active_slot = -1
	SaveManager.autosave_enabled = false
	var main := preload("res://scenes/Main.tscn").instantiate()
	main.name = "Main"
	add_child(main)
	var overview := OS.get_cmdline_user_args().has("--art-overview")
	if overview:
		var ground := main.get_node("Game/Ground") as IsoGround
		var camera := Camera2D.new()
		camera.position = ground.get_world_bounds().get_center()
		camera.zoom = Vector2.ONE * 0.35
		add_child(camera)
		camera.make_current()
	GameState.emit_all()
	if OS.get_cmdline_user_args().has("--art-capture"):
		_capture.call_deferred(at_boss, overview)

func _capture(at_boss: bool, overview: bool) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var file := "全图预览.png" if overview else "Boss区预览.png" if at_boss else "洞口预览.png"
	var path := "res://docs/素材设计/样板/腐化源头洞穴布局-v2/" + file
	get_viewport().get_texture().get_image().save_png(path)
	print("[CaveArtSample] captured ", path)
	get_tree().quit()
