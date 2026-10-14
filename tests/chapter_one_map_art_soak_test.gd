extends Node
## 第一章大图持续运行回归：野外、灰烬、源头在自动战斗中保持装饰与碰撞稳定。
## 隔离测试只观察节点数和场景生命周期，不修改真实存档或怪物预算。


## 每张战斗图运行 600 个物理帧，确保新静态素材不随镜头或战斗重复实例化。
func _ready() -> void:
	for map_id in ["wild_trial", "ash_land", "corruption_source"]:
		GameState.reset_to_defaults()
		GameState.current_map = map_id
		var world := preload("res://scenes/Game.tscn").instantiate()
		add_child(world)
		await get_tree().physics_frame
		var ground := world.get_node("Ground") as IsoGround
		var expected_sprites := ground._chapter_one_art.get_child_count()
		var initial_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var peak_nodes := initial_nodes
		GameState.set_auto_battle(true)
		for _index in range(600):
			await get_tree().physics_frame
			peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
			assert(ground._chapter_one_art.get_child_count() == expected_sprites,
				"静态地图美术不得在战斗中重复实例化：%s" % map_id)
		assert(peak_nodes - initial_nodes < 150,
			"短时间战斗节点数异常增长：%s / %s" % [map_id, peak_nodes - initial_nodes])
		print("[PERF] %s auto 600 physics frames: nodes start %d, peak %d, static sprites %d" % [
			map_id, initial_nodes, peak_nodes, expected_sprites])
		GameState.set_auto_battle(false)
		world.queue_free()
		await get_tree().physics_frame
	print("[ChapterOneMapArtSoakTest] PASS")
	get_tree().quit()
