extends Node
## 法师挂机在实际距离、敌群与待拾取物下的施法顺序；覆盖低蓝解围和寻路受阻。

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

## 在实际空间距离下验证法师群攻、追击、低蓝与受阻回退。
func _ready() -> void:
	_test_cluster_rotation()
	_test_nearby_swarm_while_target_far()
	_test_cone_uses_nearby_anchor()
	_test_single_target_standoff()
	_test_low_mana_and_blocked_position()
	_test_blocked_swarm_still_fights()
	_test_loot_in_pickup_range_does_not_hold_combat()
	_test_loot_outside_pickup_range_keeps_priority()
	_test_low_mana_swarm_reserves_shield()
	GameState.reset_to_defaults()
	if _failures.is_empty():
		print("[MageAutoSkillsTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## 建立隔离法师及自动战斗节点，关闭引擎心跳以便逐次推进决策。
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

## 在指定世界像素坐标放置无攻击行为的可命中敌人。
func _enemy(point: Vector2) -> TestEnemy:
	var enemy := TestEnemy.new()
	add_child(enemy)
	enemy.global_position = point
	return enemy

## 双怪从远端接近后依次验证陨石、近距火焰与冰咆哮。
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

## 原目标在群攻射程外时，先清理玩家身边两只怪，且不丢失原追击目标。
func _test_nearby_swarm_while_target_far() -> void:
	var nodes := _setup()
	var player: PlayerCharacter = nodes.player
	var pilot: AutoBattle = nodes.pilot
	var target := _enemy(player.global_position + Vector2(8.0 * TILE, 0))
	var left := _enemy(player.global_position + Vector2(2.0 * TILE, -0.3 * TILE))
	var right := _enemy(player.global_position + Vector2(2.0 * TILE, 0.3 * TILE))
	pilot._target = target
	pilot._tick(0.016)
	_check(player.skill_cooldown("flame_burst") > 0.0 and left.hits > 0 and right.hits > 0,
		"锁定目标远离时应优先对身边两只怪施放自中心群攻")
	_check(target.hits == 0 and pilot._target == target and player.auto_move == Vector2.ZERO,
		"局部解围不能误伤远处目标、改选目标或继续追击移动")
	target.queue_free()
	left.queue_free()
	right.queue_free()
	player.queue_free()

## 自中心群攻都在冷却时，扇形技能须以身边怪为朝向锚点而非远处锁定目标。
func _test_cone_uses_nearby_anchor() -> void:
	var nodes := _setup()
	var player: PlayerCharacter = nodes.player
	var pilot: AutoBattle = nodes.pilot
	var target := _enemy(player.global_position + Vector2(5.8 * TILE, 0))
	var left := _enemy(player.global_position + Vector2(3.0 * TILE, -0.25 * TILE))
	var right := _enemy(player.global_position + Vector2(3.0 * TILE, 0.25 * TILE))
	player.skill_cooldowns["meteor"] = 10.0
	player.skill_cooldowns["flame_burst"] = 10.0
	pilot._target = target
	pilot._tick(0.016)
	_check(player.skill_cooldown("frost_roar") > 0.0 and left.hits > 0 and right.hits > 0,
		"远处锁定目标不可使近身冰咆哮误判可用却施放失败")
	_check(target.hits == 0 and pilot._target == target, "扇形施法后保持原追击目标")
	target.queue_free()
	left.queue_free()
	right.queue_free()
	player.queue_free()

## 单怪不消耗范围技能，保持法师的远程停步与雷电术分工。
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

## 低蓝时保护盾资源，近距进位受阻时也不拉黑原本可攻击目标。
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

## 临时拉黑只暂停重新寻路；身边两只怪仍应被群攻，不能因 BLOCKED 停战一秒。
func _test_blocked_swarm_still_fights() -> void:
	var nodes := _setup()
	var player: PlayerCharacter = nodes.player
	var pilot: AutoBattle = nodes.pilot
	var left := _enemy(player.global_position + Vector2(2.0 * TILE, -12))
	var right := _enemy(player.global_position + Vector2(2.0 * TILE, 12))
	pilot._blocked_t = 1.0
	pilot._target = null
	pilot._tick(0.016)
	_check(pilot._blocked_t < 1.0 and left.hits > 0 and right.hits > 0,
		"目标暂时受阻时仍能原地群攻解围")
	left.queue_free()
	right.queue_free()
	player.queue_free()

## 掉落已在 1.5 格拾取范围内时无需站到其中心；保护期内仍应继续战斗。
func _test_loot_in_pickup_range_does_not_hold_combat() -> void:
	var nodes := _setup()
	var player: PlayerCharacter = nodes.player
	var pilot: AutoBattle = nodes.pilot
	var left := _enemy(player.global_position + Vector2(2.0 * TILE, -12))
	var right := _enemy(player.global_position + Vector2(2.0 * TILE, 12))
	GameState.auto_pickup_on = true
	var drop := GroundItem.new()
	drop.item = {"kind": "coin", "amount": 1}
	drop.hold_time = 5.0
	add_child(drop)
	drop.global_position = player.global_position + Vector2(16, 0)
	pilot._loot = drop
	pilot._target = left
	pilot._tick(0.016)
	_check(pilot._loot == null and left.hits > 0 and right.hits > 0,
		"已进入自动拾取范围的待收取物不阻断群攻")
	drop.queue_free()
	left.queue_free()
	right.queue_free()
	player.queue_free()

## 范围外的可拾取物仍优先于敌群，防止解围改动反转 F/G 的既有拾取顺序。
func _test_loot_outside_pickup_range_keeps_priority() -> void:
	var nodes := _setup()
	var player: PlayerCharacter = nodes.player
	var pilot: AutoBattle = nodes.pilot
	var left := _enemy(player.global_position + Vector2(2.0 * TILE, -12))
	var right := _enemy(player.global_position + Vector2(2.0 * TILE, 12))
	GameState.auto_pickup_on = true
	var drop := GroundItem.new()
	drop.item = {"kind": "coin", "amount": 1}
	drop.hold_time = 5.0
	add_child(drop)
	drop.global_position = player.global_position + Vector2(160, 0)
	pilot._loot = drop
	pilot._target = left
	pilot._tick(0.016)
	_check(pilot.current_state() == AutoBattle.State.PATH_TO_LOOT and player.auto_move.length() > 0.0
			and left.hits == 0 and right.hits == 0,
		"拾取范围外仍先接近可收取物，再处理敌群")
	drop.queue_free()
	left.queue_free()
	right.queue_free()
	player.queue_free()

## 低蓝保盾期间三怪贴身可临时群攻，但必须为下一次开盾留足法力。
func _test_low_mana_swarm_reserves_shield() -> void:
	var nodes := _setup()
	var player: PlayerCharacter = nodes.player
	var pilot: AutoBattle = nodes.pilot
	var enemies: Array[TestEnemy] = []
	for offset in [Vector2(2.0 * TILE, -18), Vector2(2.0 * TILE, 0), Vector2(2.0 * TILE, 18)]:
		enemies.append(_enemy(player.global_position + offset))
	pilot._target = enemies[0]
	GameState.player.mp = int(GameState.max_mp() * 0.2)
	pilot._tick(0.016)
	_check(enemies[0].hits > 0 and enemies[1].hits > 0 and enemies[2].hits > 0,
		"低蓝但盾有效、三怪贴身且预留开盾费用时允许群攻解围")
	player._attack_cd = 0.0
	player.skill_cooldowns.clear()
	var shield_cost := GameState.skill_mana_cost(SkillProgression.current("magic_shield"))
	var cheapest_area := GameState.skill_mana_cost(SkillProgression.current("flame_burst"))
	GameState.player.mp = shield_cost + cheapest_area - 1
	var hits_before := enemies[0].hits + enemies[1].hits + enemies[2].hits
	pilot._tick(0.016)
	var hits_after := enemies[0].hits + enemies[1].hits + enemies[2].hits
	_check(hits_after <= hits_before + 1 and player.skill_cooldown("flame_burst") == 0.0
			and player.skill_cooldown("meteor") == 0.0 and player.skill_cooldown("frost_roar") == 0.0,
		"低蓝解围不得花掉预留的下一次开盾法力，允许不耗蓝的单体普攻")
	for enemy in enemies:
		enemy.queue_free()
	player.queue_free()

## 记录失败原因以让隔离运行器得到可靠退出码。
func _check(ok: bool, reason: String) -> void:
	if not ok:
		_failures.append(reason)
		push_error("[MageAutoSkillsTest] " + reason)
