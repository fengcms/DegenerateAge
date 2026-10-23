extends Node
## 工程 98 第二层：远程普攻契约。
##
## 守两件事：
##   ① **射程上限**：4 格能打到、4.1 格打不到。写死 `melee_range_px()` 的职业化会在这里露馅。
##   ② **伤害即时结算**：投射物只是视觉。若有人把结算挂到「弹道命中」，
##      怪物死亡期间的那次攻击会白扔，且 `hits` 会在飞行途中一直是 0 —— 本文件断的就是这个。

const TILE := 64.0

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

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[MageRangedTest] " + label)

func _ready() -> void:
	_test_range_values()
	_test_hit_boundary()
	var player := _make_player("mage")
	await _test_projectile_visual(player)
	if failures.is_empty():
		print("[MageRangedTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[MageRangedTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

func _make_player(class_id: String) -> PlayerCharacter:
	GameState.reset_to_defaults(class_id)
	GameState.current_map = "wild_trial"
	GameState.player.level = 40
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(2000, 2000)
	return player

func _enemy(at: Vector2) -> TestEnemy:
	var enemy := TestEnemy.new()
	add_child(enemy)
	enemy.global_position = at
	return enemy

# ---- 射程 ----

func _test_range_values() -> void:
	check(is_equal_approx(PlayerClass.attack_range("mage"), 4.0), "法师普攻射程应为 4 格")
	check(is_equal_approx(PlayerClass.attack_range("warrior"), 1.0), "武士普攻射程应为 1 格")
	var mage := _make_player("mage")
	check(is_equal_approx(mage.attack_range_px(), 4.0 * TILE),
		"法师 attack_range_px 应为 %.0f，实际 %.0f" % [4.0 * TILE, mage.attack_range_px()])
	check(is_equal_approx(mage.melee_range_px(), mage.attack_range_px()),
		"melee_range_px 必须退化为 attack_range_px 的别名（4 处调用点仍在用它）")
	# 自动战斗的停步距离 = 射程 − STOP_GAP，必须明显大于近战，否则法师会贴身放技能。
	check(mage.attack_range_px() - AutoBattle.STOP_GAP > 3.5 * TILE,
		"法师的自动战斗停步距离必须仍在 3.5 格以上")
	mage.queue_free()
	var warrior := _make_player("warrior")
	check(is_equal_approx(warrior.attack_range_px(), TILE), "武士 attack_range_px 必须仍是 1 格（64px）")
	warrior.queue_free()

## 3.9 格能打、4.1 格打不到 —— 两侧夹逼，只断「能打」会被「射程被调到 10 格」骗过。
func _test_hit_boundary() -> void:
	var player := _make_player("mage")
	var inside := _enemy(player.global_position + Vector2(3.9 * TILE, 0))
	var outside := _enemy(player.global_position + Vector2(4.1 * TILE, 0))
	check(player.try_auto_attack(inside), "3.9 格必须在射程内（能出手）")
	check(inside.hits == 1, "3.9 格目标应已受击一次")
	player._attack_cd = 0.0
	check(not player.try_auto_attack(outside), "4.1 格必须打不到（射程是 4 格，不是无限）")
	check(outside.hits == 0, "4.1 格目标不应受击")
	player.queue_free()
	inside.queue_free()
	outside.queue_free()

# ---- 投射物 = 纯视觉 ----

func _count_projectiles() -> int:
	var n := 0
	for child in get_children():
		var script: Variant = child.get_script()
		if script is Script and String((script as Script).resource_path).ends_with("player_projectile.gd"):
			n += 1
	return n

func _test_projectile_visual(player: PlayerCharacter) -> void:
	var target := _enemy(player.global_position + Vector2(3.0 * TILE, 0))
	var before := _count_projectiles()
	check(player.try_auto_attack(target), "法师 3 格内应能普攻")
	check(_count_projectiles() == before + 1, "远程普攻必须产生 1 个投射物节点（视觉）")
	# 🔴 关键断言：伤害在**发动当帧**就已结算，不等弹道飞完。
	check(target.hits == 1 and target.damage > 0, "普攻伤害必须即时结算（不等投射物命中）")
	await get_tree().process_frame
	check(target.hits == 1, "投射物飞行期间不得二次结算（一次攻击只掉一次血）")
	player._attack_cd = 0.0
	var warrior := _make_player("warrior")
	var dummy := _enemy(warrior.global_position + Vector2(0.5 * TILE, 0))
	var before_w := _count_projectiles()
	check(warrior.try_auto_attack(dummy), "武士近战普攻应正常")
	check(_count_projectiles() == before_w, "武士不得产生投射物节点（近战路径逐位不变）")
