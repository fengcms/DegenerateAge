extends Node
## 工程 103 怪物重叠验收：追击与攻击两个阶段都必须保持同类最小间距。
## 软分离只改移动决策，不改碰撞层 —— 玩家仍可穿过怪群，Boss 是不可推动的锚点。
## 断的是「多只怪收敛到同一像素点」这件事本身，不是配置里有没有分离常数。

const KEEP_RATIO := 0.7   # 软分离不承诺绝对不重叠：允许临时挤压到最小间距的 70%
var failures: Array[String] = []

func _ready() -> void:
	GameState.reset_to_defaults()
	await _test_chase_spacing()
	await _test_attack_spacing()
	await _test_boss_anchor()
	print("[MonsterCrowdTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

## 同侧挤成一列追击：跑满 4 秒后任意两只必须已经摊开。
func _test_chase_spacing() -> void:
	var player := _add_player()
	var starts: Array[Vector2] = []
	for i in range(5):
		starts.append(Vector2(200.0 + i * 1.5, (i - 2) * 1.5))
	var wolves := _spawn_wolves(starts)
	for _i in range(240):
		await get_tree().physics_frame
	_check_apart(wolves, "追击")
	for wolf in wolves:
		_check(wolf.state == Monster.State.CHASE or wolf.state == Monster.State.ATTACK,
			"追击中的怪应处于 CHASE/ATTACK，实际 %d" % wolf.state)
	_check(wolves[0].collision_mask == 1, "怪物仍只与地形层碰撞（玩家可穿过怪群）")
	_cleanup(player, wolves)

## 五只怪从同一像素点起步且已经够得到玩家：站桩输出期间也必须被推开。
func _test_attack_spacing() -> void:
	var player := _add_player()
	var starts: Array[Vector2] = []
	for _i in range(5):
		starts.append(Vector2(40.0, 0.0))
	var wolves := _spawn_wolves(starts)
	for _i in range(120):
		await get_tree().physics_frame
	_check_apart(wolves, "攻击")
	for wolf in wolves:
		_check(wolf.state == Monster.State.ATTACK, "够得到玩家的怪应进入 ATTACK，实际 %d" % wolf.state)
	_cleanup(player, wolves)

## Boss 不可被推动，但普通怪不能叠进 Boss 身体里。
func _test_boss_anchor() -> void:
	var player := _add_player()
	var boss := (load("res://scenes/entities/Monster.tscn") as PackedScene).instantiate() as Monster
	boss.monster_id = "boss_corrupted_beast"
	boss.ai_enabled = false
	boss.position = Vector2(60.0, 0.0)
	boss.spawn_position = boss.position
	add_child(boss)
	var anchor := boss.global_position
	var wolves := _spawn_wolves([Vector2(60.0, 0.0), Vector2(60.0, 0.0)])
	for _i in range(120):
		await get_tree().physics_frame
	_check(boss.global_position.distance_to(anchor) < 0.01, "Boss 不应被同类推动")
	for wolf in wolves:
		var gap := wolf.global_position.distance_to(boss.global_position)
		_check(gap >= (wolf.radius + boss.radius) * Monster.SEPARATION_KEEP * KEEP_RATIO,
			"普通怪被 Boss 挤开：间距 %.1f" % gap)
	_cleanup(player, wolves + [boss])

func _add_player() -> PlayerCharacter:
	var player := (load("res://scenes/entities/Player.tscn") as PackedScene).instantiate() as PlayerCharacter
	player.position = Vector2.ZERO
	add_child(player)
	return player

## 统一关掉攻击力：本用例只看站位，不结算伤害（否则五只怪会把玩家打死）。
func _spawn_wolves(starts: Array[Vector2]) -> Array[Monster]:
	var out: Array[Monster] = []
	for p in starts:
		var wolf := (load("res://scenes/entities/Monster.tscn") as PackedScene).instantiate() as Monster
		wolf.monster_id = "wolf_corrupted"
		wolf.spawn_level = 2
		wolf.ai_enabled = true
		wolf.position = p
		wolf.spawn_position = p
		add_child(wolf)
		wolf.attack_power = 0.0
		out.append(wolf)
	return out

func _check_apart(wolves: Array[Monster], phase: String) -> void:
	for i in range(wolves.size()):
		for j in range(i + 1, wolves.size()):
			var a := wolves[i]
			var b := wolves[j]
			var min_dist := (a.radius + b.radius) * Monster.SEPARATION_KEEP * KEEP_RATIO
			var dist := a.global_position.distance_to(b.global_position)
			_check(dist >= min_dist, "%s期同类重叠：%d 与 %d 间距 %.1f < %.1f" % [phase, i, j, dist, min_dist])

func _cleanup(player: Node2D, monsters: Array) -> void:
	player.queue_free()
	for node in monsters:
		if is_instance_valid(node):
			node.queue_free()
	for _i in range(2):
		await get_tree().physics_frame

## 将实际物理行为失败记录为非零退出码，避免只检查配置值。
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[MonsterCrowdTest] " + message)
