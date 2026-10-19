extends Node
## 第三章 21—30 敌人与三 Boss（31 §5 批次 3.2 准出）：
##   · 15 个模板可在运行世界生成，档次 / 尺寸正确；
##   · 三 Boss 的共享线 / 扇 / 圈预警动作由 Monster 驱动（进战首放 4 秒、
##     预警期间不结算伤害、预警结束按**锁定几何**结算）；
##   · 同一段只结算一次、一轮 A 招命中不超模板段数；
##   · 脱战 5 秒归位回满；复刷 / 再杀不重发首通奖励；bossSpawn 复刷 600 秒、墓碑等待、每图上限 1。

const STEP := 1.0 / 60.0
const ORIGIN := Vector2(1000.0, 1000.0)
const RESPAWN_SECONDS := 600
const NORMALS := ["c3_normal01", "c3_normal02", "c3_normal03", "c3_normal04",
	"c3_normal05", "c3_normal06", "c3_normal07", "c3_normal08"]
const ELITES := ["c3_elite01", "c3_elite02", "c3_elite03", "c3_elite04"]
const BOSSES := ["c3_boss01", "c3_boss02", "c3_boss03"]
const BOSS_MAP := {"c3_boss01": "c3_map02", "c3_boss02": "c3_map04", "c3_boss03": "c3_map05"}

## 战场桩：只提供 `_get_player()` 需要的 `is_dead` 与结算需要的 `apply_damage`。
class StubPlayer extends Node2D:
	var is_dead := false
	var hits := 0
	var hp := 999999
	func apply_damage(amount: int) -> int:
		hits += 1
		hp = maxi(0, hp - amount)
		return amount

var failures: Array[String] = []
var _arena: Node2D
var _player: StubPlayer

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterThreeCombatTest] " + message)

func _ready() -> void:
	GameState.reset_to_defaults()
	_arena = Node2D.new()
	add_child(_arena)
	_player = StubPlayer.new()
	_player.name = "StubPlayer"
	_player.add_to_group("player")
	add_child(_player)
	_test_templates_generate()
	_test_boss_warning_wiring()
	_test_retreat_and_reset()
	_test_first_clear_dedup()
	_test_respawn_config()
	print("[ChapterThreeCombatTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

## 15 模板都能实例化并读到正确档次；只有 Boss 装配共享动作组件。
func _test_templates_generate() -> void:
	check(NORMALS.size() == 8 and ELITES.size() == 4 and BOSSES.size() == 3, "本章模板共 15 个")
	for id in NORMALS + ELITES + BOSSES:
		GameState.current_map = String(BOSS_MAP.get(id, "c3_map01"))
		var m := _spawn_monster(id)
		var expected := "boss" if id in BOSSES else "elite" if id in ELITES else "normal"
		check(not m.template.is_empty(), "%s 有模板数据" % id)
		check(m._kind() == expected, "%s 档次为 %s" % [id, expected])
		check(is_equal_approx(m.radius, Monster.radius_for_kind(expected)), "%s 外观半径按档次" % id)
		if expected == "boss":
			check(m.boss_action != null and m.boss_action.has_a(), "%s 装配共享预警动作" % id)
			check(is_equal_approx(m.leash_range, Monster.BOSS_ARENA_TILES * Iso.TILE_W), "%s 首领场半径 18 格" % id)
		else:
			check(m.boss_action == null, "%s 不装配首领动作组件" % id)
		m.free()

## 三 Boss 由 Monster 驱动共享动作：首放前 / 预警期间不伤害，预警结束按锁定几何结算一次。
func _test_boss_warning_wiring() -> void:
	for id in BOSSES:
		GameState.current_map = String(BOSS_MAP[id])
		_player.hits = 0
		_player.global_position = ORIGIN + Vector2(240.0, 0.0)
		var boss := _spawn_monster(id)
		boss.ai_enabled = true
		boss.hp = boss.max_hp
		boss._update_boss(STEP)
		check(_player.hits == 0, "%s 首放前不发招、不伤害" % id)
		for _i in range(int(round(3.9 * 60.0))):
			boss._update_boss(STEP)
		check(not boss.boss_action.is_busy() and _player.hits == 0, "%s 进战 4 秒内不伤害" % id)
		_run_boss_until(boss, func() -> bool: return boss.boss_action.is_warning(), 2.0)
		check(boss.boss_action.is_warning(), "%s 4 秒后进入预警" % id)
		check(_player.hits == 0, "%s 预警期间不结算伤害" % id)
		# 进入预警后把玩家放进**锁定几何**内 —— 预警结束才结算。
		_player.global_position = _point_inside(boss.boss_action.geometry())
		_run_boss_until(boss, func() -> bool: return _player.hits >= 1, 2.0)
		check(_player.hits == 1, "%s 首段只结算一次" % id)
		# 同一段绝不重复结算；一轮 A 招总命中不超过模板段数。
		var per_segment := {}
		var last := _player.hits
		var expected_segments: int = (boss.template.get("bossSkill", {}) as Dictionary).get("segments", []).size()
		for _i in range(int(round(8.0 * 60.0))):
			boss._update_boss(STEP)
			var delta := _player.hits - last
			if delta > 0:
				var seg := boss.boss_action._seg
				per_segment[seg] = int(per_segment.get(seg, 0)) + delta
			last = _player.hits
			if not boss.boss_action.is_busy() and not per_segment.is_empty():
				break
		var repeats := false
		for key in per_segment:
			if int(per_segment[key]) > 1:
				repeats = true
		check(not repeats, "%s 同一段命中不超过一次" % id)
		check(_player.hits <= expected_segments, "%s 一轮 A 招命中不超段数 %d" % [id, expected_segments])
		boss.free()

## 脱战 5 秒归位：回场心、回满血、清二阶段与动作状态。
func _test_retreat_and_reset() -> void:
	GameState.current_map = "c3_map02"
	_player.hits = 0
	_player.global_position = ORIGIN + Vector2(200.0, 0.0)
	var boss := _spawn_monster("c3_boss01")
	boss.ai_enabled = true
	boss.hp = 1
	boss.boss_phase = 1
	boss.global_position = ORIGIN + Vector2(Monster.BOSS_ARENA_TILES * Iso.TILE_W * 1.5, 0.0)
	boss._update_boss(STEP)
	check(boss._boss_retreating, "离场心超 18 格进入脱战")
	for _i in range(int(round(5.1 * 60.0))):
		boss._update_boss(STEP)
	check(not boss._boss_retreating and boss.hp == boss.max_hp, "脱战 5 秒归位回满")
	check(boss.global_position.distance_to(boss.spawn_position) < 1.0, "归位回场心")
	check(boss.boss_phase == 0, "归位清零二阶段")
	check(_player.hits == 0, "脱战期间不再发招伤害")
	boss.free()

## 复刷 / 再杀同一首领不重发首通奖励（同怪物 id 只广播一次 boss_first_clear）。
func _test_first_clear_dedup() -> void:
	GameState.current_map = "c3_map02"
	var clears := [0]
	EventBus.boss_first_clear.connect(func(_id: String) -> void: clears[0] += 1)
	var first := _spawn_monster("c3_boss01")
	first._die()
	check(bool(GameState.first_clear.get("c3_boss01", false)), "首杀登记首通")
	check(clears[0] == 1, "首杀只发一次首通")
	var again := _spawn_monster("c3_boss01")
	again._die()
	check(clears[0] == 1, "复刷再杀不重发首通")

## bossSpawn 复刷 600 秒、墓碑等待、每图首领上限 1。
func _test_respawn_config() -> void:
	for id in BOSSES:
		var map_id := String(BOSS_MAP[id])
		var map_data := MapService.data_for(map_id)
		var boss: Variant = map_data.get("bossSpawn", null)
		check(boss is Dictionary and String((boss as Dictionary).get("monsterId", "")) == id,
			"%s 的 bossSpawn 指向 %s" % [map_id, id])
		check(is_equal_approx(float((boss as Dictionary).get("respawnTime", 0.0)), float(RESPAWN_SECONDS)),
			"%s 复刷 %d 秒" % [map_id, RESPAWN_SECONDS])
		check(bool((boss as Dictionary).get("tombstone", false)), "%s 首领点墓碑等待" % map_id)
		check(int(map_data.get("bossCap", -1)) == 1, "%s 首领上限 1" % map_id)

func _spawn_monster(id: String) -> Monster:
	var m := (load("res://scenes/entities/Monster.tscn") as PackedScene).instantiate() as Monster
	m.monster_id = id
	m.ai_enabled = false
	_arena.add_child(m)
	m.set_physics_process(false)
	m.position = ORIGIN
	m.spawn_position = ORIGIN
	return m

func _run_boss_until(boss: Monster, predicate: Callable, limit: float) -> void:
	var t := 0.0
	while t < limit:
		boss._update_boss(STEP)
		t += STEP
		if bool(predicate.call()):
			return
	push_warning("[ChapterThreeCombatTest] 等待条件超时")

## 在当前预警几何内取一点（line 取线段中点 / circle 取圆心 / fan 取朝向半程）。
func _point_inside(geo: Dictionary) -> Vector2:
	# `BossAction.geometry()` 自工程 55 起返回**地面空间**（纵向 ×2）；
	# 这里的返回值要喂给 `global_position`，必须先投影回屏幕坐标，否则玩家会被摆到两倍远的位置。
	var g := Vector2.ZERO
	match String(geo.get("kind", "")):
		"line":
			g = ((geo["from"] as Vector2) + (geo["to"] as Vector2)) * 0.5
		"circle":
			g = geo["center"] as Vector2
		"fan":
			g = (geo["center"] as Vector2) + (geo["dir"] as Vector2) * float(geo["radius"]) * 0.5
		_:
			return ORIGIN
	return Iso.from_ground(g)
