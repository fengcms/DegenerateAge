extends Node
## 法师挂机在实际距离和敌群位置下的施法顺序；不依赖理论 CD 模型。

const TILE := 64.0

class TestEnemy extends Node2D:
	var is_dead := false
	var hits := 0
	func _ready() -> void:
		add_to_group("enemies")
	func get_defense() -> float:
		return 0.0
	func get_dodge() -> float:
		return 0.0
	func take_hit(_result: Dictionary, _from: Node = null) -> void:
		hits += 1

var _failures: Array[String] = []

func _ready() -> void:
	_test_cluster_rotation()
	_test_single_target_standoff()
	_test_low_mana_and_blocked_position()
	GameState.reset_to_defaults()
	if _failures.is_empty():
		print("[MageAutoSkillsTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _setup() -> Dictionary:
	GameState.reset_to_defaults("mage")
	GameState.current_map = "wild_trial"
	GameState.player.level = 40
	GameState.player.mp = GameState.max_mp()
	GameState.player.hp = GameState.max_hp()
	var player := (load("res://scenes/entities/Player.tscn") as PackedScene).instantiate() as PlayerCharacter
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(2000, 2000)
	var pilot := player.get_node("AutoPilot") as AutoBattle
	pilot.set_physics_process(false)
	GameState.start_buff("magic_shield")
	return {"player": player, "pilot": pilot}

func _enemy(point: Vector2) -> TestEnemy:
	var enemy := TestEnemy.new()
	add_child(enemy)
	enemy.global_position = point
	return enemy

func _test_cluster_rotation() -> void:
	var nodes := _setup()
	var player: PlayerCharacter = nodes.player
	var pilot: AutoBattle = nodes.pilot
	var target := _enemy(player.global_position + Vector2(5.8 * TILE, 0))
	var partner := _enemy(target.global_position + Vector2(0, 16))
	pilot._target = target
	pilot._tick(0.016)
	_check(player.skill_cooldown("meteor") > 0.0 and target.hits > 0 and partner.hits > 0,
		"远距双怪先使用实际能命中的陨石术")
	player._attack_cd = 0.0
	pilot._tick(0.016)
	_check(player.auto_move.length() > 0.0 and pilot._target == target,
		"陨石术冷却后，为近距范围技接近敌群且保持原目标")
	var cast_point: Vector2 = pilot._mage_position_point
	_check(cast_point.is_finite() and player.global_position.distance_to(cast_point) > TILE,
		"近距施法位是可检查的有限坐标")
	player.global_position = cast_point
	player._attack_cd = 0.0
	pilot._tick(0.016)
	_check(player.skill_cooldown("flame_burst") > 0.0, "到位后使用火焰喷发")
	player._attack_cd = 0.0
	player.skill_cooldowns["meteor"] = 10.0
	player.skill_cooldowns["flame_burst"] = 10.0
	pilot._tick(0.016)
	_check(player.skill_cooldown("frost_roar") > 0.0, "其他范围技冷却时使用冰咆哮")
	target.queue_free()
	partner.queue_free()
	player.queue_free()

func _test_single_target_standoff() -> void:
	var nodes := _setup()
	var player: PlayerCharacter = nodes.player
	var pilot: AutoBattle = nodes.pilot
	var target := _enemy(player.global_position + Vector2(5.8 * TILE, 0))
	pilot._target = target
	pilot._tick(0.016)
	_check(player.skill_cooldown("lightning") > 0.0 and player.auto_move == Vector2.ZERO,
		"单怪保持远程距离并使用雷电术，不为范围技贴近")
	_check(player.skill_cooldown("flame_burst") == 0.0 and player.skill_cooldown("frost_roar") == 0.0
		and player.skill_cooldown("meteor") == 0.0, "单怪不浪费范围技能")
	target.queue_free()
	player.queue_free()

func _test_low_mana_and_blocked_position() -> void:
	var nodes := _setup()
	var player: PlayerCharacter = nodes.player
	var pilot: AutoBattle = nodes.pilot
	var target := _enemy(player.global_position + Vector2(5.8 * TILE, 0))
	var partner := _enemy(target.global_position + Vector2(0, 16))
	pilot._target = target
	player.skill_cooldowns["meteor"] = 10.0
	GameState.player.mp = int(GameState.max_mp() * 0.2)
	pilot._tick(0.016)
	_check(player.auto_move == Vector2.ZERO and player.skill_cooldown("flame_burst") == 0.0,
		"低蓝保盾时不为近距范围技进位或施放技能")
	GameState.player.mp = GameState.max_mp()
	pilot._mana_saver = false
	player._attack_cd = 0.0
	# 模拟被动态碰撞挡住：连续尝试但位置不变；可攻击的目标不能因此进黑名单。
	for _i in range(7):
		pilot._tick(0.31)
	_check(pilot._target == target and pilot.blacklist_size() == 0 and pilot._mage_position_retry_t > 0.0,
		"近距施法位卡住时回退远程攻击，不拉黑原目标")
	target.queue_free()
	partner.queue_free()
	player.queue_free()

func _check(ok: bool, reason: String) -> void:
	if not ok:
		_failures.append(reason)
		push_error("[MageAutoSkillsTest] " + reason)
