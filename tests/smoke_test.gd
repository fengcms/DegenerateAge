extends Node
## 无头冒烟测试（M1）。断言关键不变量，失败则以非 0 退出码结束。
##
## 运行（两步：先导入扫描，再跑测试）：
##   GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##   "$GODOT" --headless --path . --import
##   "$GODOT" --headless --path . res://tests/SmokeTest.tscn
##
## 说明：--import 用于注册 class_name 全局类（Iso / IsoGround / PlayerCharacter /
## Combat / Monster / MonsterSpawner / DamageNumber / Fx）；换机或新增 class_name 后需先跑一次。

var _failures: Array[String] = []

func _ready() -> void:
	_test_data_validation()
	_test_iso_math()
	_test_stats()
	_test_combat()
	await _test_single_resolution()
	await _test_monster_chase()
	await _test_monster_attacks_player()
	await _test_death_settles_once()
	await _test_spawner()
	await _test_world()
	_finish()

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _test_data_validation() -> void:
	var report: Array[String] = DataLoader.validate_all()
	_expect(report.is_empty(), "数据校验未通过：%s" % [report])

func _test_iso_math() -> void:
	# 往返转换
	var cell := Vector2i(7, 3)
	var back := Iso.world_to_grid(Iso.grid_to_world(cell))
	_expect(is_equal_approx(back.x, float(cell.x)) and is_equal_approx(back.y, float(cell.y)),
		"等距坐标往返失败：%s -> %s" % [cell, back])
	# 公式抽查（文档 7.1：tileW=64, tileH=32）
	_expect(is_equal_approx(Iso.grid_to_world(Vector2i(1, 0)).x, 32.0), "col+1 应使 screenX +32")
	_expect(is_equal_approx(Iso.grid_to_world(Vector2i(0, 1)).x, -32.0), "row+1 应使 screenX −32")
	_expect(is_equal_approx(Iso.grid_to_world(Vector2i(1, 1)).y, -32.0), "col+row 增大应使 screenY 更小")

# ---- M1-3：属性派生与数值广播 ----
func _test_stats() -> void:
	GameState.reset_to_defaults()
	# 4.3 / 4.4：L1（攻12/防5）→ HP 102、MP 35
	_expect(GameState.max_hp() == 102, "L1 最大生命应为 102，实际 %d" % GameState.max_hp())
	_expect(GameState.max_mp() == 35, "L1 最大法力应为 35，实际 %d" % GameState.max_mp())
	_expect(int(GameState.player.hp) == GameState.max_hp(), "初始当前 HP 应等于上限")

	# 数值变更应经 EventBus 广播（HUD 实时刷新链路）
	var hp_sig := [0, 0]
	EventBus.player_hp_changed.connect(func(c, m): hp_sig[0] = c; hp_sig[1] = m)
	GameState.damage_player(15)
	_expect(hp_sig[0] == 87 and hp_sig[1] == 102, "扣血应广播 87/102，实际 %s" % [hp_sig])

	var gold_sig := [0]
	EventBus.gold_changed.connect(func(v): gold_sig[0] = v)
	GameState.add_gold(50)
	_expect(gold_sig[0] == 50, "金币变更应广播，实际 %d" % gold_sig[0])
	GameState.reset_to_defaults()

# ---- M1-4：伤害公式（3.2 / 3.5 / 3.8）----
func _test_combat() -> void:
	# 基础伤害：atk12 / def2 / 系数1.0 → floor(12 − 2×0.5) = 11
	var r := Combat.resolve(12.0, 2.0, 1.0, 0.0, 1.5, 0.0)
	_expect(not r.miss and int(r.damage) == 11 and not r.critical,
		"普攻基础伤害应为 11/非暴击，实际 %s" % [r])
	# 暴击：floor(11 × 1.5) = 16（crit_chance=1 必暴）
	var rc := Combat.resolve(12.0, 2.0, 1.0, 1.0, 1.5, 0.0)
	_expect(rc.critical and int(rc.damage) == 16, "暴击伤害应为 16，实际 %s" % [rc])
	# 概率 Miss（3.5）：dodge50 → 50%；封顶 75%
	_expect(is_equal_approx(Combat.miss_chance(50.0), 0.5), "闪避 50 → Miss 应为 50%")
	_expect(is_equal_approx(Combat.miss_chance(1000.0), 0.75), "Miss 应封顶 75%")
	# 伤害下限 ≥1（3.2 约束）
	var rmin := Combat.resolve(1.0, 999.0, 1.0, 0.0, 1.5, 0.0)
	_expect(int(rmin.damage) == 1, "伤害下限应为 1，实际 %d" % int(rmin.damage))
	# 技能系数（3.3）：裂地斩 1.4 → floor(12 × 1.4 − 1) = 15
	var rs := Combat.resolve(12.0, 2.0, 1.4, 0.0, 1.5, 0.0)
	_expect(int(rs.damage) == 15, "裂地斩(1.4) 伤害应为 15，实际 %d" % int(rs.damage))

# ---- T04：单次命中只结算一次 ----
func _test_single_resolution() -> void:
	var monster = load("res://scenes/entities/Monster.tscn").instantiate()
	monster.monster_id = "training_dummy"   # hpBase 50 / defense 0
	add_child(monster)
	await get_tree().process_frame

	var hp0: int = int(monster.get("hp"))
	_expect(hp0 == 50, "木桩初始 HP 应为 50，实际 %d" % hp0)

	var res := Combat.resolve(12.0, monster.get_defense(), 1.0, 0.0, 1.5, 0.0)
	monster.take_hit(res, null)
	_expect(int(monster.get("hp")) == hp0 - int(res.damage),
		"单次命中应只扣一次血：%d -> %d（伤害 %d）" % [hp0, int(monster.get("hp")), int(res.damage)])

	monster.queue_free()
	await get_tree().process_frame

# ---- M1-5：怪物 AI 追击（7.9）----
func _test_monster_chase() -> void:
	GameState.reset_to_defaults()
	var player = load("res://scenes/entities/Player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector2.ZERO

	var wolf = load("res://scenes/entities/Monster.tscn").instantiate()
	wolf.monster_id = "wolf_corrupted"
	wolf.spawn_level = 2
	wolf.ai_enabled = true
	wolf.position = Vector2(160.0, 0.0)     # 在仇恨半径内、攻击范围外
	wolf.spawn_position = Vector2(160.0, 0.0)
	add_child(wolf)
	await get_tree().physics_frame

	var d0: float = wolf.global_position.distance_to(player.global_position)
	for _i in range(20):
		await get_tree().physics_frame
	var d1: float = wolf.global_position.distance_to(player.global_position)
	_expect(d1 < d0, "怪物应朝玩家追击：距离 %0.1f -> %0.1f" % [d0, d1])
	_expect(wolf.state == wolf.State.CHASE or wolf.state == wolf.State.ATTACK,
		"怪物应处于追击/攻击态，实际 %d" % wolf.state)

	player.queue_free()
	wolf.queue_free()
	await get_tree().physics_frame

# ---- M1-5：怪物攻击玩家（3.1 敌我对等）----
func _test_monster_attacks_player() -> void:
	GameState.reset_to_defaults()
	var player = load("res://scenes/entities/Player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector2.ZERO

	var wolf = load("res://scenes/entities/Monster.tscn").instantiate()
	wolf.monster_id = "wolf_corrupted"
	wolf.spawn_level = 2
	wolf.ai_enabled = true
	wolf.position = Vector2(40.0, 0.0)      # 在普攻范围内（1 格 = 64px）
	wolf.spawn_position = Vector2(40.0, 0.0)
	add_child(wolf)

	var hp0: int = int(GameState.player.hp)
	for _i in range(15):
		await get_tree().physics_frame
	_expect(int(GameState.player.hp) < hp0,
		"怪物应攻击玩家并扣血：%d -> %d" % [hp0, int(GameState.player.hp)])
	_expect(GameState.player.hp == hp0 - 5,
		"野狼(攻8) 打玩家(防5) 应为 5 点伤害，实际 %d" % [hp0 - int(GameState.player.hp)])

	# 玩家无敌帧内不应被连续命中（3.4）
	var hp_a: int = int(GameState.player.hp)
	player.apply_damage(5)   # 立即再打一次应被无敌帧挡下
	_expect(int(GameState.player.hp) == hp_a, "无敌帧内不应再次扣血")

	player.queue_free()
	wolf.queue_free()
	await get_tree().physics_frame

# ---- M1-5：死亡结算仅一次（3.1）----
func _test_death_settles_once() -> void:
	GameState.reset_to_defaults()
	var wolf = load("res://scenes/entities/Monster.tscn").instantiate()
	wolf.monster_id = "wolf_corrupted"
	wolf.spawn_level = 2
	add_child(wolf)
	await get_tree().process_frame

	var gold0: int = GameState.gold
	var lethal := Combat.resolve(9999.0, wolf.get_defense(), 1.0, 1.0, 1.0, 0.0)
	wolf.take_hit(lethal, null)
	_expect(bool(wolf.is_dead), "致命伤害后怪物应死亡")
	_expect(GameState.gold - gold0 == 6, "击杀野狼应结算金币 6，实际 %d" % [GameState.gold - gold0])

	var gold1: int = GameState.gold
	wolf.take_hit(lethal, null)   # 已是死亡态，不应再结算
	_expect(GameState.gold == gold1, "死亡结算应仅一次")

	wolf.queue_free()
	await get_tree().process_frame

# ---- M1-5：怪物点生成与刷新（7.9）----
func _test_spawner() -> void:
	var sp := MonsterSpawner.new()
	add_child(sp)
	sp.setup(null, null)
	sp.spawn_from_specs([
		{"monsterId": "wolf_corrupted", "level": 2, "count": 3, "respawnTime": 1.0, "ai": true},
	])
	await get_tree().process_frame
	_expect(sp.point_count() == 3, "应登记 3 个怪物点，实际 %d" % sp.point_count())
	_expect(sp.alive_count() == 3, "应生成 3 个存活怪物，实际 %d" % sp.alive_count())

	# 击杀一只后应按 respawnTime 重生
	var first: Node = sp.get_child(0)
	first.take_hit(Combat.resolve(9999.0, 0.0, 1.0, 1.0, 1.0, 0.0), null)
	await get_tree().process_frame
	_expect(sp.alive_count() == 2, "击杀后存活数应为 2，实际 %d" % sp.alive_count())

	# 注意：无头模式不锁帧，单帧 delta 极小，故按真实时间等待而非帧数
	await get_tree().create_timer(1.4).timeout
	_expect(sp.alive_count() == 3, "刷新时间到达后应回到 3 只，实际 %d" % sp.alive_count())

	sp.queue_free()
	await get_tree().process_frame

func _test_world() -> void:
	var game: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame

	var ground: Node = game.get_node_or_null("Ground")
	var player: Node = game.get_node_or_null("Entities/Player")
	_expect(ground != null, "未找到 Ground 节点")
	_expect(player != null, "未找到 Player 节点")
	if ground == null or player == null:
		return

	var center: Vector2 = ground.get_map_center_world()
	_expect(player.global_position.is_equal_approx(center),
		"玩家未出生在地图中心：pos=%s center=%s" % [player.global_position, center])

	var bounds: Rect2 = ground.get_world_bounds()
	_expect(bounds.size.x > 0.0 and bounds.size.y > 0.0, "地图包围盒非法：%s" % [bounds])

	var boundary: Node = ground.get_node_or_null("Boundary")
	_expect(boundary != null, "未生成边界碰撞体")
	if boundary != null:
		_expect(boundary.get_child_count() == 4, "边界墙应为 4 段，实际 %d" % boundary.get_child_count())

	# M1-5：怪物生成器已按测试怪物点生成 3 个怪物（2 野狼 + 1 木桩）
	var spawner: Node = game.get_node_or_null("Spawner")
	_expect(spawner != null, "未找到 Spawner 节点")
	if spawner != null:
		_expect(spawner.get_child_count() == 3,
			"应生成 3 个怪物，实际 %d" % spawner.get_child_count())

	# HUD 伤害飘字层分组
	var dn: Node = game.get_node_or_null("DamageNumbers")
	_expect(dn != null and dn.is_in_group("damage_numbers"), "DamageNumbers 节点缺少分组标记")

func _finish() -> void:
	if _failures.is_empty():
		print("[SmokeTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("[SmokeTest] 失败：", f)
		get_tree().quit(1)
