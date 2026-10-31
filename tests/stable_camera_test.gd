extends Node
## 实际相机确定性回归：各倍率/大真实步长不越过目标，父节点运动不直接带走镜头。
var failures: Array[String] = []

## 聚合失败并以非零退出，防止仅加载场景就误认通过。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

## 改变Engine倍率但用相同真实时间推进正式入口，验证镜头轨迹完全一致。
func _ready() -> void:
	var original := Engine.time_scale
	var target := Node2D.new()
	add_child(target)
	var camera := StableFollowCamera.new()
	target.add_child(camera)
	camera.set_process(false)
	check(camera.top_level and not camera.position_smoothing_enabled, "原生不稳定平滑已关闭")
	var reference: Array[Vector2] = []
	for scale in [0.0, 1.0, 2.0, 4.0, 8.0, 16.0]:
		Engine.time_scale = scale
		target.position = Vector2(1280, -2544)
		camera.snap_to_target()
		target.position += Vector2(100, 0)
		check(camera.global_position.x == 1280.0, "父变换不直接推走镜头")
		var previous := 1280.0
		for frame in range(120):
			camera.advance_follow(1.0 / 60.0)
			var p := camera.global_position
			check(p.is_finite() and p.x >= previous and p.x <= 1380.0, "阶跃单调收敛不越过目标")
			if scale == 0.0:
				reference.append(p)
			else:
				check(p.is_equal_approx(reference[frame]), "同真实时间轨迹不受倍率影响")
			previous = p.x
		check(absf(camera.global_position.x - 1380.0) < 0.01, "镜头保持跟随响应")
	for delta in [0.0, 0.0333, 0.1333, 0.2667, 1.0, 30.0]:
		target.position = Vector2.ZERO
		camera.snap_to_target()
		target.position = Vector2(100, 0)
		camera.advance_follow(delta)
		check(camera.global_position.is_finite() and camera.global_position.x >= 0.0 and camera.global_position.x <= 100.0, "大步长无发散")
	Engine.time_scale = original
	target.queue_free()
	await get_tree().process_frame
	print("[StableCameraTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
