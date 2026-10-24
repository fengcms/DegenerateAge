extends Node
## 工程 103 怪物重叠验收：追击与攻击两个阶段都必须保持同类最小间距。
## 软分离只改移动决策，不改碰撞层 —— 玩家仍可穿过怪群，Boss 是不可推动的锚点。
## 断的是「多只怪收敛到同一像素点」这件事本身，不是配置里有没有分离常数。
## 🔴 工程 103-b：间距判据必须用 `separation_radius`（画面可见半宽），不是玩法 `radius`。
##    上一轮用 `radius` 派生阈值，于是「69px 的身体只拉开 23px」也会判为通过。

const KEEP_RATIO := 0.7   # 软分离不承诺绝对不重叠：允许临时挤压到最小间距的 70%
## 打金图普通怪：static_atlas 单帧 80×80，alpha 包围盒实测可见体宽 69px ⇒ 半宽 34.5。
const GOLD_FIELD_ID := "c6_normal01"
const GOLD_FIELD_HALF_WIDTH := 34.5
var failures: Array[String] = []

func _ready() -> void:
	GameState.reset_to_defaults()
	await _test_chase_spacing()
	await _test_attack_spacing()
	await _test_boss_anchor()
	await _test_visible_body_spacing()
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
	_check(is_equal_approx(boss.separation_radius, boss.radius),
		"Boss 只做锚点：分离半径应等于玩法半径 %.1f，实际 %.1f" % [boss.radius, boss.separation_radius])
	for wolf in wolves:
		var gap := wolf.global_position.distance_to(boss.global_position)
		# Boss 不按美术体宽计间距：普通怪按自身可见半宽 + Boss 玩法半径就够了。
		_check(gap >= (wolf.separation_radius + boss.radius) * Monster.SEPARATION_KEEP * KEEP_RATIO,
			"普通怪被 Boss 挤开：间距 %.1f" % gap)
	_cleanup(player, wolves + [boss])

## 工程 103-b：打金图怪物必须按「可见体宽」分离，而不是按玩法半径。
## 同时锁定近战射程补偿：这类怪模板写 range=1.0，装配后应为 1.25 格（80px）。
func _test_visible_body_spacing() -> void:
	var player := _add_player()
	var first := _spawn_gold_field(Vector2(40.0, 0.0))
	_check(absf(first.separation_radius - GOLD_FIELD_HALF_WIDTH) <= 2.0,
		"%s 的分离半径应取自可见体宽 %.1f，实际 %.1f" % [GOLD_FIELD_ID, GOLD_FIELD_HALF_WIDTH, first.separation_radius])
	_check(first.separation_radius > Monster.RADIUS * 2.0,
		"分离半径必须大于玩法半径的两倍（否则画面上仍重叠）：%.1f" % first.separation_radius)
	_check(is_equal_approx(first.attack_range_px, Monster.MELEE_RANGE_FLOOR * Iso.TILE_W),
		"近战射程应抬到 %.2f 格（%.0fpx），实际 %.1fpx" % [
			Monster.MELEE_RANGE_FLOOR, Monster.MELEE_RANGE_FLOOR * Iso.TILE_W, first.attack_range_px])
	var second := _spawn_gold_field(Vector2(40.0, 0.0))
	for _i in range(150):
		await get_tree().physics_frame
	var gap := first.global_position.distance_to(second.global_position)
	_check(gap >= (first.separation_radius + second.separation_radius) * Monster.SEPARATION_KEEP * KEEP_RATIO,
		"打金图怪按体宽分离：间距 %.1f" % gap)
	_cleanup(player, [first, second])

func _spawn_gold_field(at: Vector2) -> Monster:
	var monster := (load("res://scenes/entities/Monster.tscn") as PackedScene).instantiate() as Monster
	monster.monster_id = GOLD_FIELD_ID
	monster.ai_enabled = true
	monster.position = at
	monster.spawn_position = at
	add_child(monster)
	monster.attack_power = 0.0
	return monster

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
			var min_dist := (a.separation_radius + b.separation_radius) * Monster.SEPARATION_KEEP * KEEP_RATIO
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
