extends Node2D
## 多 Boss 物理站位回归：真实 AI 汇聚、同点出生与三代技能锁定；隔离存档，不放宽原碰撞规则。
var failures: Array[String] = []
var target: Node2D
var actors: Array[Monster] = []
const STEP := 1.0 / 60.0

## 不移动、不死亡的战斗目标，记录真实命中次数而不干扰站位。
class Target extends Node2D:
	var is_dead := false
	var hits := 0
	## 接受真实攻击回调，避免受伤反馈改变目标位置。
	func apply_damage(_amount: int) -> int:
		hits += 1
		return 0

## 顺序运行夹具，只有全部行为断言通过才输出完成标记。
func _ready() -> void:
	GameState.reset_to_defaults()
	SaveManager.active_slot = -1
	SaveManager.autosave_enabled = false
	GameState.current_map = "c7_boss_field"
	target = Target.new()
	target.position = Iso.grid_to_world(Vector2i(80, 60))
	target.add_to_group("player")
	add_child(target)
	await _converge([Vector2(40, 0), Vector2(40, 0)], "同点出生")
	await _converge([Vector2(120, 0), Vector2(200, 0), Vector2(280, 0)], "同侧追击")
	for id in ["boss_corrupted_beast", "c2_boss_iron_foreman", "c6_boss03"]:
		await _warning_anchor(id)
	await _moving_pack()
	await _minor_enemies()
	await _wall_and_removal()
	if failures.is_empty():
		print("[BossCrowdTest] PASS")
	get_tree().quit(0 if failures.is_empty() else 1)

## 装配正式模板；保留技能和数值，目标不受伤所以不用改攻击力。
func _spawn(id: String, offset: Vector2) -> Monster:
	var boss := load("res://scenes/entities/Monster.tscn").instantiate() as Monster
	boss.monster_id = id
	boss.position = target.position + offset
	boss.spawn_position = boss.position
	boss.ai_enabled = true
	add_child(boss)
	actors.append(boss)
	return boss

## 检查同点/汇聚后的持续站位；尾段每帧检查，避免瞬时分开冒充稳定收敛。
func _converge(offsets: Array, label: String) -> void:
	for offset in offsets:
		_spawn("c6_boss03", offset)
	var bad_frames := 0
	var minimum := INF
	var hits_before: int = target.hits
	for frame in range(600):
		await get_tree().physics_frame
		if frame >= 420:
			var gap := _minimum_gap()
			minimum = minf(minimum, gap)
			if gap < 80.0:
				bad_frames += 1
	_check(bad_frames == 0, "%s：尾段180帧间距不得小于80地面像素，最小%.2f，失败帧%d" % [label, minimum, bad_frames])
	_check(target.hits > hits_before, label + "：分离后仍能接战命中")
	print("[PERF] ", label, " 最小地面间距=", minimum, " 命中=", target.hits - hits_before)
	await _clear()

## 测量所有存活 Boss 的地面中心距，独立于实现的分离向量和半径字段。
func _minimum_gap() -> float:
	var minimum := INF
	for i in range(actors.size()):
		for j in range(i + 1, actors.size()):
			minimum = minf(minimum, Iso.ground_distance(actors[i].position, actors[j].position))
	return minimum

## 由正式技能入口触发预警；邻居重叠时锁定身体与几何，邻居须主动避开。
func _warning_anchor(id: String) -> void:
	var caster := _spawn(id, Vector2(40, 0))
	caster._enter(Monster.State.ATTACK)
	if id == "boss_corrupted_beast":
		caster.hp = int(caster.max_hp * 0.5)
	elif caster.boss_action != null:
		caster.boss_action._a_countdown = 0.0
	else:
		caster._chapter_boss_skill_cd = 0.0
	_check(caster._update_boss(0.0), id + "：正式入口应开始预警")
	var origin := caster.position
	var geometry: Variant = _geometry(caster).duplicate(true)
	var neighbor := _spawn("c6_boss03", Vector2(45, 0))
	var drift := 0.0
	var same_geometry := true
	for _i in range(24):
		await get_tree().physics_frame
		drift = maxf(drift, caster.position.distance_to(origin))
		same_geometry = same_geometry and _geometry(caster) == geometry
	_check(drift < 0.01, id + "：预警中的施法者不得被邻居推动")
	_check(same_geometry, id + "：锁定预警几何不得漂移")
	_check(Iso.ground_distance(caster.position, neighbor.position) > 15.0, id + "：可移动邻居必须避让施法者")
	_check(caster.collision_mask == 1 and neighbor.collision_mask == 1, "Boss 不新增实体硬碰撞")
	await _clear()

## 读取正式画判共用几何，覆盖首章、第二章和共享动作组件。
func _geometry(boss: Monster) -> Variant:
	if boss.boss_action != null:
		return boss.boss_action.geometry()
	if boss._stomp_pending:
		return boss._stomp_geometry()
	return boss._chapter_boss_geometries()

## 等待队列释放完毕，避免旧敌人污染下一次近邻查询。
func _clear() -> void:
	for boss in actors:
		boss.queue_free()
	actors.clear()
	await get_tree().process_frame
	await get_tree().physics_frame

## 保留所有失败证据并由场景返回非零退出码。
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[BossCrowdTest] " + message)

## 墙边分离继续受物理阻挡；死亡与排队删除的身体不再挤开活体，也不阻挡玩家。
func _wall_and_removal() -> void:
	var wall := StaticBody2D.new()
	wall.position = target.position + Vector2(0, 120)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(1000, 16)
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	var first := _spawn("c6_boss03", Vector2(40, 60))
	var second := _spawn("c6_boss03", Vector2(40, 60))
	var crossed := false
	for _i in range(240):
		await get_tree().physics_frame
		for boss in actors:
			crossed = crossed or boss.position.y >= wall.position.y - 8.0
	_check(not crossed, "避让不得将Boss推穿实体墙")
	_check(_minimum_gap() > 80.0, "墙边同点起步仍须分开")
	first.set_physics_process(false)
	second.set_physics_process(false)
	second.position = first.position
	second.suppress_rewards = true
	second.take_hit({"damage":999999999,"miss":false})
	first.velocity = Vector2.ZERO
	first._hold_attack_spacing(target)
	_check(first.velocity.is_zero_approx(), "死亡Boss不占据分离位置")
	var queued := _spawn("c6_boss03", first.position - target.position)
	queued.queue_free()
	first._hold_attack_spacing(target)
	_check(first.velocity.is_zero_approx(), "已排队退场的Boss不占据分离位置")
	actors.erase(queued)
	var player := load("res://scenes/entities/Player.tscn").instantiate() as PlayerCharacter
	add_child(player)
	player.set_physics_process(false)
	player.get_node("AutoPilot").set_physics_process(false)
	player.position = first.position - Vector2(100, 0)
	await get_tree().physics_frame
	_check(not player.test_move(player.global_transform, Vector2(200, 0)), "真实玩家仍可穿过Boss与尸体")
	player.queue_free()
	wall.queue_free()
	# 动画尸体可能已自行释放，只清理仍有效的节点。
	for i in range(actors.size() - 1, -1, -1):
		if not is_instance_valid(actors[i]):
			actors.remove_at(i)
	await _clear()

## 玩家连续拉动混合首领时，不得持续收敛到同一中心，仍须保持攻击机会。
func _moving_pack() -> void:
	var home := target.position
	_spawn("c6_boss03", Vector2(120, 0))
	_spawn("c2_boss_iron_foreman", Vector2(200, 0))
	_spawn("boss_corrupted_beast", Vector2(280, 0))
	var streak := 0
	var longest := 0
	var hits_before: int = target.hits
	for frame in range(720):
		target.position = home + Vector2(80.0 * sin(frame / 150.0), 40.0 * sin(frame / 90.0))
		await get_tree().physics_frame
		if frame >= 180:
			streak = streak + 1 if _minimum_gap() < 16.0 else 0
			longest = maxi(longest, streak)
	_check(longest < 60, "连续拉怪不得持续一秒叠点，最长%d帧" % longest)
	_check(target.hits > hits_before, "连续拉怪时仍能接战")
	print("[PERF] 连续拉怪重叠最长帧=", longest, " 命中=", target.hits - hits_before)
	target.position = home
	await _clear()

## 活动Boss身边的召唤物不会反向推走Boss；不通过关闭Boss AI来绕过该规则。
func _minor_enemies() -> void:
	var boss := _spawn("c6_boss03", Vector2(40, 0))
	boss._enter(Monster.State.ATTACK)
	var origin := boss.position
	boss._spawn_summons("wolf_corrupted", 3, false, true)
	for _i in range(90):
		await get_tree().physics_frame
	_check(boss.position.distance_to(origin) < 0.01, "召唤小怪不能推走正在攻击的Boss")
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy != boss:
			enemy.queue_free()
	await _clear()
