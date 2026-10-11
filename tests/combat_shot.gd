extends Node
## 战斗视觉验收工具（开发期）：把玩家移到最近怪物旁并普攻数次后截图，验证飘字 / 目标区联动。
## 运行：GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##       "$GODOT" --path . res://tests/CombatShot.tscn

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(20):
		await get_tree().process_frame

	var player = main.get_node("Game/Entities/Player")
	var enemies := get_tree().get_nodes_in_group("enemies")
	var target = enemies[0] if enemies.size() > 0 else null
	if is_instance_valid(target):
		# 怪物会移动，先把玩家移到目标身旁再普攻
		player.global_position = (target as Node2D).global_position + Vector2(-40.0, 0.0)
		await get_tree().process_frame

	var results: Array = []
	for _k in range(3):
		if is_instance_valid(target):
			results.append(player.perform_attack(target))

	for _i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/degenerateage_combat.png")
	var hp_after: int = int(target.get("hp")) if is_instance_valid(target) else -1
	print("[CombatShot] results=%s target_hp_after=%d" % [str(results), hp_after])
	get_tree().quit()
