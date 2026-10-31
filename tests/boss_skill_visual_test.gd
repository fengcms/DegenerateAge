extends Node
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
func _ready() -> void:
	var skill: Dictionary = DataLoader.get_entry("monsters", "c3_boss01").bossSkill
	var action := BossAction.new(skill)
	var visual := BossSkillVisual.new()
	var hits: Array = []
	action.visual_impact.connect(func(geo: Dictionary) -> void:
		hits.append(geo)
		visual.impact(geo))
	action._start(Vector2(400, 300), Vector2.RIGHT, BossAction.Move.A)
	var geometry := action.geometry().duplicate(true)
	var count := [0]
	action.update(float(skill.warn), Vector2(999, 999), Vector2.DOWN, true, 1.0,
		func(_coefficient: float) -> void: count[0] += 1)
	check(count[0] == 1 and hits.size() == 1 and hits[0] == geometry, "命中事件与锁定几何一致且仅触发一次")
	visual.tick(1.0)
	check(visual.impacts.is_empty() and BossSkillVisual.detail_count == 0, "消散释放预算")
	var line := {"kind": "line", "from": Vector2.ZERO, "to": Vector2(100, 0), "half": 20.0}
	var points := BossSkillVisual.line_points(line)
	check(Array(points).any(func(point: Vector2) -> bool: return point.distance_to(Vector2(120, 0)) < 0.001) and Array(points).any(func(point: Vector2) -> bool: return point.distance_to(Vector2(-20, 0)) < 0.001), "圆头轮廓覆盖原胶囊判定")
	for _i in range(50):
		visual.impact(line)
	check(visual.impacts.size() == 3 and BossSkillVisual.detail_count == 3, "单Boss残留有界")
	visual.clear()
	var owners: Array[BossSkillVisual] = []
	for _i in range(40):
		var fx := BossSkillVisual.new()
		fx.impact(line)
		owners.append(fx)
	check(BossSkillVisual.detail_count == 24 and owners[39].impacts.size() == 1, "装饰限额不吞主要命中表现")
	for fx in owners:
		fx.clear()
	var boss := preload("res://scenes/entities/Monster.tscn").instantiate()
	boss.monster_id = "boss_corrupted_beast"
	boss.ai_enabled = false
	add_child(boss)
	boss._boss_visual_impact(line)
	boss.queue_free()
	await get_tree().process_frame
	check(BossSkillVisual.detail_count == 0, "宿主释放清理预算")
	if failures.is_empty():
		print("[BossSkillVisualTest] 全部通过 ✅")
	get_tree().quit(0 if failures.is_empty() else 1)
