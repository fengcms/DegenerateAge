extends Node
## 正式世界镜头生命周期：出生落位、倍率缩放、暂停/零倍速、传送复位及退出清理。
var failures: Array[String] = []

## 记录全部失败，确保测试恢复暂停和全局倍率后才退出。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

## 冻结战斗但保留相机的真实process，验证倍速与暂停语义。
func _ready() -> void:
	var original_scale := Engine.time_scale
	GameState.reset_to_defaults()
	GameState.current_map = "c7_boss_field"
	var world := preload("res://scenes/Game.tscn").instantiate()
	add_child(world)
	world.get_node("Spawner").set_process(false)
	var player := world.get_node("Entities/Player") as PlayerCharacter
	player.set_physics_process(false)
	player.get_node("AutoPilot").set_physics_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	var camera := player.get_node("Camera2D") as StableFollowCamera
	check(camera != null and camera.global_position.is_equal_approx(player.global_position), "出生后立即落位")
	player.global_position += Vector2(200, 0)
	StableFollowCamera.snap(camera)
	check(camera.global_position.is_equal_approx(player.global_position), "明确传送不拖着旧位置飞行")
	for scale in [0.8, 1.0, 2.0]:
		GameState.settings.mapScale = scale
		SettingsRuntime.apply_map_scale_to(camera)
		check(camera._follow_position.is_equal_approx(player.global_position), "缩放清理旧内部状态")
	Engine.time_scale = 0.0
	player.global_position += Vector2(100, 0)
	var before := camera.global_position
	for i in range(4):
		await get_tree().process_frame
	check(camera.global_position.x > before.x and camera.global_position.x <= player.global_position.x, "零游戏倍率仍可稳定处理镜头视觉")
	get_tree().paused = true
	before = camera.global_position
	for i in range(4):
		await get_tree().process_frame
	check(camera.global_position == before, "真正暂停不更新镜头")
	get_tree().paused = false
	Engine.time_scale = 16.0
	for i in range(4):
		await get_tree().process_frame
	check(camera.global_position.is_finite() and camera.global_position.x <= player.global_position.x, "恢复及十六倍无过冲")
	Engine.time_scale = original_scale
	world.queue_free()
	await get_tree().process_frame
	check(get_tree().get_nodes_in_group("player_camera").is_empty(), "旧地图相机随父节点释放")
	print("[CameraLifecycleTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
