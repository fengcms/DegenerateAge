extends Node
## Gameplay contract: one grid drives cave art, routing, collision and spawns.

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		print("[CaveLayoutTest] 失败：", message)

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "corruption_source"
	GameState.save_pos = Iso.grid_to_world(Vector2i(8, 25))
	GameState.has_save_pos = true
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	var world := main.get_node("Game")
	var ground := world.get_node("Ground") as IsoGround
	var cave := ground.cave
	check(cave != null and cave.size == Vector2i(50, 50), "洞穴布局加载")
	check(not cave.is_walkable(Vector2i(25, 20)) and cave.is_walkable(Vector2i(8, 25)), "黑暗区域阻挡与入口通行")
	var path := cave.path(Vector2i(8, 25), Vector2i(40, 26))
	check(path.size() > 0 and path[0] == Vector2i(8, 25) and path.back() == Vector2i(40, 26), "入口可绕岩柱抵达 Boss 区")
	for i in range(1, path.size()):
		var step := path[i] - path[i - 1]
		check(maxi(absi(step.x), absi(step.y)) == 1, "路线每一步必须八向相邻")
		if absi(step.x) == 1 and absi(step.y) == 1:
			check(cave.is_walkable(path[i - 1] + Vector2i(step.x, 0)) and
				cave.is_walkable(path[i - 1] + Vector2i(0, step.y)), "斜向移动不可穿过墙角")
	check(ground.clamp_to_map(Iso.grid_to_world(Vector2i(25, 20))) != Iso.grid_to_world(Vector2i(25, 20)), "阻挡格的落点会纠正")
	var walls := ground.get_node("CaveWalls") as StaticBody2D
	check(walls.get_child_count() == cave.boundary_cells().size(), "每个洞壁边缘都有物理碰撞")
	var spawner := world.get_node("Spawner") as MonsterSpawner
	for point in spawner.marker_points():
		var cell := Vector2i(Iso.world_to_grid(point.position).round())
		check(cave.is_walkable(cell), "怪物和墓碑只能位于可走格")
	var boss_found := false
	for point in spawner.marker_points():
		if String(point.monster_id) == "boss_corrupted_beast":
			boss_found = true
			check(Vector2i(Iso.world_to_grid(point.position).round()) == Vector2i(40, 26), "Boss 固定在战斗区")
	check(boss_found, "Boss 已生成")
	await get_tree().physics_frame
	var query := PhysicsPointQueryParameters2D.new()
	query.position = Iso.grid_to_world(Vector2i(6, 20))
	var hits := (world as Node2D).get_world_2d().direct_space_state.intersect_point(query)
	var wall_hit := false
	for hit in hits:
		if hit.collider == walls:
			wall_hit = true
	check(wall_hit, "岩柱中心存在真实碰撞")
	spawner.set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	var player := world.get_node("Entities/Player") as PlayerCharacter
	player._speed = 256.0
	check(player.request_map_move(Iso.grid_to_world(Vector2i(40, 26))), "点击移动接受 Boss 区目标")
	for _i in range(1400):
		if not player.map_move_active:
			break
		await get_tree().physics_frame
	check(player.global_position.distance_to(Iso.grid_to_world(Vector2i(40, 26))) < 20.0, "玩家绕岩柱抵达 Boss 区")
	print("[CaveLayoutTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
