extends Node
## 验证表现事件、预算回收、完整主题映射与第二章旧判定兼容性。
var failures: Array[String] = []
## 聚合断言失败，确保异步场景输出真实完成标记。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
## 独立验证锁定事件、生命周期和旧公式，不改玩家存档。
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
	check(BossSkillVisual.validate_config(DataLoader.get_table("bossVisuals")).is_empty(), "正式表现配置合法")
	var boss_count := 0
	for tpl in DataLoader.get_table("monsters"):
		if tpl.get("kind") == "boss":
			boss_count += 1
			check(DataLoader.get_table("bossVisuals").bosses.has(tpl.id), "Boss有主题映射 " + tpl.id)
	check(boss_count == 17, "17个Boss主题全部登记")
	BossSkillVisual._warning_frame = -1
	var admitted := 0
	for i in range(100):
		if BossSkillVisual._admit_warning():
			admitted += 1
	check(admitted == 8, "同帧次要纹样预算有界")
	var mesh := BossSkillVisual.ring_mesh(30.0, 80.0)
	check(mesh == BossSkillVisual.ring_mesh(30.0, 80.0), "同半径共享环带网格")
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(vertices.size() == 192, "环带仍为48片四边形")
	for vertex in vertices:
		var radius := Vector2(vertex.x, vertex.y / Iso.GROUND_SQUASH).length()
		check(is_equal_approx(radius, 30.0) or is_equal_approx(radius, 80.0), "合批不填安全中心")
	for i in range(40):
		BossSkillVisual.ring_mesh(float(i), 100.0 + i)
	check(BossSkillVisual._rings.size() <= 32, "不同半径缓存有界")
	var bad: Dictionary = DataLoader.get_table("bossVisuals").duplicate(true)
	bad.styles.corruption.motif = "bad"
	check(not BossSkillVisual.validate_config(bad).is_empty(), "拒绝未知纹样")
	var second := preload("res://scenes/entities/Monster.tscn").instantiate()
	second.monster_id = "c2_boss_iron_foreman"
	second.ai_enabled = false
	add_child(second)
	second._chapter_boss_origin = Vector2(1000, 1000)
	second._chapter_boss_target = Vector2(1150, 1040)
	second._chapter_boss_centers.assign([Vector2(1000, 1000), Vector2(1150, 1040), Vector2(1300, 1100)])
	for shape in ["sweep", "line", "circle", "blasts"]:
		second._chapter_boss_warn = shape
		var geos: Array = second._chapter_boss_geometries()
		for x in range(500, 1600, 37):
			for y in range(600, 1400, 37):
				var point := Vector2(x, y)
				var hit := false
				for geo in geos:
					hit = hit or BossAction.hits_geometry(geo, point)
				check(hit == _old_chapter_hit(shape, point, second), "第二章新旧判定一致 " + shape)
	second.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("[BossSkillVisualTest] 全部通过 ✅")
	get_tree().quit(0 if failures.is_empty() else 1)

## 原第二章公式的独立对照，不调用新几何构造器，锁定旧数值与命中语义。
func _old_chapter_hit(shape: String, point: Vector2, boss: Monster) -> bool:
	var c := 1.4142135623730951
	var g := Iso.to_ground(point)
	var origin := Iso.to_ground(Vector2(1000, 1000))
	var direction := Iso.ground_dir(Vector2(150, 40).normalized())
	match shape:
		"sweep":
			return g.distance_to(origin) <= 170.0 * c and absf(direction.angle_to(g - origin)) <= deg_to_rad(68.0)
		"line":
			return Geometry2D.get_closest_point_to_segment(g, origin, origin + direction * 340.0 * c).distance_to(g) <= 48.0 * c
		"circle":
			return g.distance_to(Iso.to_ground(Vector2(1150, 1040))) <= 88.0 * c
		"blasts":
			for center in boss._chapter_boss_centers:
				if g.distance_to(Iso.to_ground(center)) <= 66.0 * c:
					return true
	return false
