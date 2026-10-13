extends Node
## 主动技能的真实玩家施放回归；使用假敌人记录单次受击，不写角色存档。

class TestEnemy extends Node2D:
	var is_dead := false
	var hits := 0
	var damage := 0
	func _ready() -> void:
		add_to_group("enemies")
	func get_defense() -> float:
		return 0.0
	func get_dodge() -> float:
		return 0.0
	func take_hit(result: Dictionary, _from: Node = null) -> void:
		hits += 1
		damage += int(result.get("damage", 0))

var _failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "wild_trial"
	GameState.player.level = 5
	GameState.player.mp = 100
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(1500, 1500)
	var near := _enemy(player.global_position + Vector2(90, 0))
	var upper := _enemy(player.global_position + Vector2(80, -40))
	var lower := _enemy(player.global_position + Vector2(80, 40))
	var fourth := _enemy(player.global_position + Vector2(110, 0))
	var behind := _enemy(player.global_position + Vector2(-65, 0))
	var cleave: Dictionary = DataLoader.get_entry("skills", "earth_cleave")
	_check(player.skill_targets(cleave, near).size() == 3, "扇形只取最近三个目标")
	_check(player.skill_targets(cleave, fourth).has(fourth), "扇形多目标上限时保留锁定目标")
	var before := int(GameState.player.mp)
	_check(player.cast_skill("earth_cleave", near), "Lv5 可施放裂地斩")
	_check(int(GameState.player.mp) == before - 15 and player.skill_cooldown("earth_cleave") == 4.0, "耗蓝与冷却只结算一次")
	_check(near.hits == 1 and upper.hits == 1 and lower.hits == 1 and fourth.hits == 0 and behind.hits == 0,
		"每个命中目标只受击一次，超额和背后不受击")
	_check(not player.cast_skill("earth_cleave", near) and int(GameState.player.mp) == before - 15,
		"冷却中不重复扣蓝")
	player.skill_cooldowns.clear()
	player._attack_cd = 0.0
	GameState.player.mp = 14
	_check(not player.cast_skill("earth_cleave", near) and int(GameState.player.mp) == 14, "蓝量不足不施放")
	GameState.player.mp = 100
	GameState.player.level = 4
	_check(not player.cast_skill("earth_cleave", near) and player.skill_cooldown("earth_cleave") == 0.0,
		"等级不足不进入冷却")
	GameState.player.level = 5
	near.is_dead = true
	_check(not player.cast_skill("earth_cleave", near) and int(GameState.player.mp) == 100,
		"目标失效不扣蓝")
	near.is_dead = false
	GameState.player.level = 10
	GameState.player.mp = 100
	player._attack_cd = 0.0
	_check(player.cast_skill("whirlwind"), "Lv10 无锁定目标可施放旋风斩")
	_check(int(GameState.player.mp) == 75 and player.skill_cooldown("whirlwind") == 6.0,
		"旋风斩耗蓝与冷却正确")
	_check(near.hits == 2 and upper.hits == 2 and lower.hits == 2 and fourth.hits == 1 and behind.hits == 1,
		"圆形范围内每只怪各受击一次")
	_check(not player.cast_skill("whirlwind") and int(GameState.player.mp) == 75,
		"旋风斩冷却阻止重复施放")
	player.skill_cooldowns.clear()
	player._attack_cd = 0.0
	var original_position := player.global_position
	var original_fourth := fourth.global_position
	fourth.global_position = original_position + Vector2(400, 0)
	player.select_target(fourth)
	var before_chase := int(GameState.player.mp)
	_check(player.request_skill("whirlwind"), "远处锁定目标的旋风斩接受追击指令")
	_check(player.manual_attack_active and int(GameState.player.mp) == before_chase
		and player.skill_cooldown("whirlwind") == 0.0, "追击开始时不提前耗蓝或进入冷却")
	_check(not player.cast_skill("whirlwind", fourth) and int(GameState.player.mp) == before_chase,
		"身边有其他怪时也不能提前命中远处锁定目标")
	_check(player._manual_attack_direction(0.016) != Vector2.ZERO and fourth.hits == 1,
		"未到技能范围继续接近目标")
	player.global_position = fourth.global_position - Vector2(80, 0)
	player._manual_attack_direction(0.016)
	_check(fourth.hits == 2 and int(GameState.player.mp) == before_chase - 25
		and not player.manual_attack_active, "进入范围后只施放一次并命中锁定目标")
	player.global_position = original_position
	fourth.global_position = original_fourth
	player.select_target(null)
	player.skill_cooldowns.clear()
	player._attack_cd = 0.0
	var pilot := AutoBattle.new()
	player.add_child(pilot)
	pilot.set_physics_process(false)
	_check(String(pilot._best_area_skill(near).get("id", "")) == "whirlwind",
		"自动战斗按实际圆形命中数优先旋风斩")
	GameState.player.mp = 20
	_check(String(pilot._best_area_skill(near).get("id", "")) == "earth_cleave",
		"蓝量不足时改选可用的裂地斩")
	GameState.player.mp = 100
	GameState.player.level = 4
	_check(pilot._best_area_skill(near).is_empty(), "未解锁时自动战斗回退普攻")
	GameState.player.level = 10
	player.global_position += Vector2(50, 0)
	pilot._target = near
	var before_auto := int(GameState.player.mp)
	pilot._tick(0.016)
	_check(int(GameState.player.mp) == before_auto - 25 and player.skill_cooldown("whirlwind") > 0.0,
		"自动战斗通过玩家统一入口施放范围技")
	var next_map_player := PlayerCharacter.new()
	add_child(next_map_player)
	next_map_player.set_physics_process(false)
	_check(next_map_player.skill_cooldown("whirlwind") > 0.0, "重建地图角色后冷却继续")
	GameState.player.level = 15
	GameState.player.mp = 100
	player._attack_cd = 0.0
	pilot._target = near
	_check(pilot._try_battle_focus(near), "自动战斗在有效近战目标前施放增益")
	_check(GameState.buff_remaining("battle_focus") > 0.0 and int(GameState.player.mp) == 70,
		"自动施放复用耗蓝和运行态")
	_check(not pilot._try_battle_focus(near) and int(GameState.player.mp) == 70, "持续期间不叠加")
	GameState.clear_buffs()
	player.skill_cooldowns.clear()
	_check(not pilot._try_battle_focus(null), "无目标不空放")
	near.global_position = player.global_position + Vector2(player.melee_range_px() + 100.0, 0)
	_check(not pilot._try_battle_focus(near), "追路期间不提前施放")
	near.global_position = player.global_position + Vector2(30, 0)
	GameState.player.mp = 29
	_check(not pilot._try_battle_focus(near), "缺蓝时继续保留普通攻击")
	GameState.player.mp = 100
	pilot._target = near
	pilot._tick(0.016)
	_check(GameState.buff_remaining("battle_focus") > 0.0 and player.skill_cooldown("battle_focus") == 30.0,
		"自动战斗实际决策优先施放增益")
	if _failures.is_empty():
		print("[SkillCombatTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)

func _enemy(at: Vector2) -> TestEnemy:
	var enemy := TestEnemy.new()
	add_child(enemy)
	enemy.global_position = at
	return enemy
