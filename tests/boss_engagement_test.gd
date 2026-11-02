extends Node
## Boss宿主接战入口回归：远处闲置不放技能，合法索敌后才计时，脱战取消并重置首放。
var failures: Array[String] = []

class StubPlayer extends Node2D:
	## 只提供宿主查找玩家与取消动作需要的生命周期，不参与伤害数值测试。
	var is_dead := false

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
		player.is_dead = true
		boss._update_boss(0.01)
		check(boss._boss_retreating and not boss.boss_action.is_busy(), "目标死亡立即取消技能 " + String(template))
		boss._update_boss(5.1)
		player.is_dead = false
		boss._physics_process(0.0)
		check(boss.state == Monster.State.CHASE and is_equal_approx(boss.boss_action._a_countdown,boss.boss_action.first_delay), "再接战重新首放计时 " + String(template))
		boss.free()
		tested += 1
	check(tested == 13, "覆盖当前13个共享Boss模板")
	player.free()
	print("[BossEngagementTest] ","全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
