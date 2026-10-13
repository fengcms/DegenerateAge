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
