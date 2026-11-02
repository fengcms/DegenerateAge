extends Node
## Boss宿主接战入口回归：远处闲置不放技能，合法索敌后才计时，脱战取消并重置首放。
var failures: Array[String] = []

class StubPlayer extends Node2D:
	## 只提供宿主查找玩家与取消动作需要的生命周期，不参与伤害数值测试。
	var is_dead := false
	## 承接可能发生的段命中，供真实组件推进；不替换战斗结算。
	func apply_damage(amount: int) -> int:
		return amount

## 收集契约失败，隔离user目录内运行，不接触玩家存档。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

## 对所有共享模板验证宿主门槛，而非直接给动作组件传入伪造target_valid。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "c3_map02"
	var player := StubPlayer.new()
	add_child(player)
	player.add_to_group("player")
	player.position = Vector2(1000,1000)
	var tested := 0
	for row in DataLoader.get_table("monsters"):
		if row.get("kind") != "boss" or not row.get("bossSkill") is Dictionary or not row.bossSkill.has("shape"):
			continue
		var template: String = String(row.id)
		var boss := load("res://scenes/entities/Monster.tscn").instantiate() as Monster
		boss.monster_id = String(template)
		boss.position = player.position + Vector2(1800,0)
		boss.ai_enabled = true
		add_child(boss)
		boss.set_physics_process(false)
		boss.spawn_position = boss.position
		for idle_state in [Monster.State.IDLE, Monster.State.PATROL, Monster.State.RETURN]:
			boss.state = idle_state
			check(not boss._update_boss(30.0) and not boss.boss_action.is_busy(), "未接战不启动技能 " + String(template))
		check(is_equal_approx(boss.boss_action._a_countdown,boss.boss_action.first_delay), "闲置不消耗首放 " + String(template))
		boss.state = Monster.State.IDLE
		boss.position = player.position + Vector2(64,0)
		boss.spawn_position = boss.position
		boss._physics_process(0.0)
		check(boss.state == Monster.State.CHASE, "技能不能阻塞合法索敌 " + String(template))
		boss._update_boss(boss.boss_action.first_delay - 0.1)
		check(not boss.boss_action.is_busy(), "接战保留首放延迟 " + String(template))
		boss._update_boss(0.11)
		check(boss.boss_action.is_warning(), "接战后正常预警 " + String(template))
		var locked_geometry := boss.boss_action.geometry().duplicate(true)
		player.position += Vector2(10,0)
		boss._update_boss(0.0)
		check(boss.boss_action.geometry() == locked_geometry, "有效战斗中预警不追踪玩家 " + String(template))
		player.position -= Vector2(10,0)
		if template == "c3_boss01":
			boss._update_boss(boss.boss_action.warn_t + 0.01)
			check(boss.boss_action.stage == BossAction.Stage.GAP, "真实首段结算进入段间隙")
		player.is_dead = true
		boss._update_boss(0.01)
		check(boss._boss_retreating and not boss.boss_action.is_busy(), "目标死亡立即取消技能 " + String(template))
		boss._update_boss(5.1)
		player.is_dead = false
		boss._physics_process(0.0)
		check(boss.state == Monster.State.CHASE and is_equal_approx(boss.boss_action._a_countdown,boss.boss_action.first_delay), "再接战重新首放计时 " + String(template))
		boss._enter(Monster.State.IDLE)
		boss.take_hit({"damage":1,"miss":false},player)
		check(boss.state == Monster.State.CHASE, "合法受击仍可拉怪 " + String(template))
		boss._update_boss(boss.boss_action.first_delay + 0.01)
		GameState.current_map = "c3_map00"
		player.position = Iso.grid_pt(MapService.safe_area_cells("c3_map00").get_center().x, MapService.safe_area_cells("c3_map00").get_center().y)
		check(MapService.is_in_rest_zone(GameState.current_map,player.position), "休息区夹具有效")
		boss._update_boss(0.01)
		check(boss._boss_retreating and not boss.boss_action.is_busy(), "进入休息区取消后续技能 " + String(template))
		GameState.current_map = "c3_map02"
		player.position = Vector2(1000,1000)
		boss.free()
		tested += 1
	check(tested == 13, "覆盖当前13个共享Boss模板")
	await test_legacy(player)
	player.free()
	print("[BossEngagementTest] ","全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

## 首章及第二章的阶段、预警和召唤必须受接战与目标生命周期约束。
func test_legacy(player: StubPlayer) -> void:
	for id in ["boss_corrupted_beast","c2_boss_iron_foreman","c2_boss_slag_devourer","c2_boss_hundred_arm_extractor"]:
		var boss := load("res://scenes/entities/Monster.tscn").instantiate() as Monster
		boss.monster_id = id
		boss.position = player.position + Vector2(60,0)
		add_child(boss)
		boss.set_physics_process(false)
		boss.spawn_position = boss.position
		boss.hp = int(boss.max_hp * 0.2)
		boss._update_boss(30.0)
		check(boss.boss_phase == 0 and not boss._boss_enraged and not boss._stomp_pending and boss._chapter_boss_warn.is_empty(), "旧入口闲置不推进阶段或技能 " + id)
		boss.hp = int(boss.max_hp * 0.55)
		boss._enter(Monster.State.CHASE)
		boss._chapter_boss_skill_cd = 0.0
		boss._update_boss(0.01)
		check(boss._stomp_pending or not boss._chapter_boss_warn.is_empty(), "旧入口合法接战仍有预警 " + id)
		player.is_dead = true
		boss._update_boss(0.01)
		check(boss.state == Monster.State.RETURN and not boss._stomp_pending and boss._chapter_boss_warn.is_empty(), "旧入口目标死亡即时撤销预警 " + id)
		if boss.sample_art is MonsterActorArt:
			check(not boss.sample_art._warning_pose, "取消践踏不残留抬臂姿势")
		player.is_dead = false
		boss._enter(Monster.State.CHASE)
		boss.hp = int(boss.max_hp * 0.2)
		boss._update_boss(0.01)
		boss._enter(Monster.State.RETURN)
		await get_tree().process_frame
		check(get_tree().get_nodes_in_group("enemies").size() == 1, "延迟阶段召唤不越过脱战 " + id)
		boss.free()
