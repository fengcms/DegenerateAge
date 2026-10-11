extends Node
## 战斗视觉验收工具（开发期）：自动对最近目标普攻数次后截图，验证飘字 / 目标区联动。
## 运行：GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##       "$GODOT" --path . res://tests/CombatShot.tscn

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(20):
		await get_tree().process_frame

	var player = main.get_node("Game/Entities/Player")
	var target = player.find_nearest_enemy_in_range()
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
