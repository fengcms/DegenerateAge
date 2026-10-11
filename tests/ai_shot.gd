extends Node
## 怪物 AI 视觉验收工具（开发期）：把玩家移到野狼附近，让 AI 追击/攻击一段时间后截图。
## 运行：GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##       "$GODOT" --path . res://tests/AiShot.tscn

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(10):
		await get_tree().process_frame

	var player = main.get_node("Game/Entities/Player")
	var wolf = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if bool(e.get("ai_enabled")):
			wolf = e
			break
	if is_instance_valid(wolf):
		player.global_position = (wolf as Node2D).global_position + Vector2(-150.0, 0.0)

	# 让 AI 追击 / 攻击一段时间（约 1.5s）
	for _i in range(90):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/degenerateage_ai.png")
	print("[AiShot] player_hp=%d/%d wolf_state=%s" % [
		int(GameState.player.hp), GameState.max_hp(),
		str(wolf.state) if is_instance_valid(wolf) else "n/a"])
	get_tree().quit()
