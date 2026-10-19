extends Node
## E1（工程文档 30 §4，31 §5 3.2）：共享 Boss 线 / 扇 / 圈预警动作组件回归。
##
## 覆盖：进战首放延迟、每段只结算一次、段间顺序与三种形态几何、B 招环击与 12 秒复现、
## 「未执行动作不伤害」、「同段只命中一次」，以及首领脱战 5 秒归位回满。

const STEP := 1.0 / 60.0
const ORIGIN := Vector2(2000.0, 2000.0)
const FACING := Vector2.RIGHT

var failures: Array[String] = []

## 战场桩：只提供 `_get_player()` 需要的 `is_dead` 与结算需要的 `apply_damage`。
class StubPlayer extends Node2D:
	var is_dead := false
	var hp := 100000
	func apply_damage(amount: int) -> int:
		hp = maxi(0, hp - amount)
		return amount

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		print("[BossAction] 失败：", message)

func _skill(id: String) -> Dictionary:
	var tpl: Variant = DataLoader.get_entry("monsters", id)
	return (tpl as Dictionary).get("bossSkill", {}) if tpl is Dictionary else {}

## 推进若干秒；每次结算把 `{c: 系数, m: 招式}` 记入 `log`。
func _advance(action: BossAction, seconds: float, ratio: float, log: Array) -> void:
	var steps := int(round(seconds * 60.0))
	for _i in range(steps):
		action.update(STEP, ORIGIN, FACING, true, ratio,
			func(c: float) -> void: log.append({"c": c, "m": action.move}))

## 推进到条件成立（上限 `limit` 秒）；用于避开浮点边界。
func _run_until(action: BossAction, predicate: Callable, ratio: float, log: Array, limit := 20.0) -> void:
	var t := 0.0
	while t < limit:
		action.update(STEP, ORIGIN, FACING, true, ratio,
			func(c: float) -> void: log.append({"c": c, "m": action.move}))
		t += STEP
		if bool(predicate.call()):
			return
	push_warning("[BossAction] 等待条件超时")

func _count_move(log: Array, move: int) -> int:
	var n := 0
	for entry in log:
		if int((entry as Dictionary).get("m", 0)) == move:
			n += 1
	return n

func _ready() -> void:
	GameState.reset_to_defaults()
	_test_iso_ground_primitive()
	_test_line_boss()
	_test_circle_boss()
	_test_fan_boss()
	_test_phase_b()
	_test_retreat_and_no_damage()
	print("[BossAction] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

## 地面几何原语（工程 53 R1）：2:1 椭圆比例、包含判定、环带、投影往返。
## 这里刻意**不引用** `BossAction.COMPENSATE`，用 `sqrt(2.0)` 直写 —— 常量写错时本组必须红。
func _test_iso_ground_primitive() -> void:
	var c := Vector2(100.0, 200.0)
	var r := 100.0
	var pts := Iso.ground_ellipse(c, r, 32)
	var max_dx := 0.0
	var max_dy := 0.0
	for p in pts:
		max_dx = maxf(max_dx, absf(p.x - c.x))
		max_dy = maxf(max_dy, absf(p.y - c.y))
	check(pts.size() == 32, "椭圆点集 32 点")
	check(absf(max_dx / max_dy - 2.0) < 0.01, "地面圆投影为 2:1 椭圆")
	check(is_equal_approx(Iso.GROUND_SQUASH, 0.5), "GROUND_SQUASH = 0.5（与 64×32 瓦片一致）")
	# 包含判定：横向 99 在内、纵向 99 在外 —— 漏掉 `to_ground` 这条必红
	check(Iso.ground_contains(c, r, c + Vector2(99.0, 0.0)), "横向 99 在地面圆内")
	check(not Iso.ground_contains(c, r, c + Vector2(0.0, 99.0)), "纵向 99 在地面圆外")
	check(is_equal_approx(Iso.ground_distance(c, c + Vector2(0.0, 99.0)), 198.0),
		"纵向屏幕距离 99 = 地面距离 198")
	# 环带：圆心不在、环中间在、纵向 60px（地面 120）已在环外
	check(not Iso.ground_ring_contains(c, 50.0, 100.0, c), "圆心不在环带内")
	check(Iso.ground_ring_contains(c, 50.0, 100.0, c + Vector2(75.0, 0.0)), "环带中段在内")
	check(not Iso.ground_ring_contains(c, 50.0, 100.0, c + Vector2(0.0, 60.0)),
		"纵向 60px = 地面 120 已在环外")
	check(Iso.to_ground(Iso.from_ground(Vector2(3.0, 7.0))).is_equal_approx(Vector2(3.0, 7.0)),
		"地面坐标往返无损")
	# 2:1 菱形：横向对角线是纵向的两倍
	var diamond := Iso.ground_diamond(c, 40.0)
	check(is_equal_approx(absf(diamond[1].x - diamond[3].x), 80.0), "菱形横向对角线 80")
	check(is_equal_approx(absf(diamond[2].y - diamond[0].y), 40.0), "菱形纵向对角线 40（2:1）")

## c3_boss01：双平行线，先左后右。
func _test_line_boss() -> void:
	var action := BossAction.new(_skill("c3_boss01"))
	var log: Array = []
	check(action.has_a() and action.shape == "line", "c3_boss01 装配线形 A 招")
	_advance(action, 3.9, 1.0, log)
	check(not action.is_busy() and log.is_empty(), "进战 4 秒内不预警、不结算")
	_run_until(action, func() -> bool: return action.is_busy(), 1.0, log)
	check(action.is_warning(), "4 秒后进入首段预警")
	check(log.is_empty(), "预警期间不结算伤害")
	var geo := action.geometry()
	check(String(geo.get("kind", "")) == "line", "首段几何为线")
	check(action.hits(ORIGIN + Vector2(100.0, -160.0)), "左线覆盖其带内")
	check(not action.hits(ORIGIN), "两线之间留安全通道")
	_run_until(action, func() -> bool: return log.size() == 1, 1.0, log)
	check(is_equal_approx(float((log[0] as Dictionary).c), 1.15), "首段系数 1.15")
	check(not action.is_warning(), "段间只间隔，不叠加预警")
	_run_until(action, func() -> bool: return action.is_warning(), 1.0, log)
	check(action.hits(ORIGIN + Vector2(100.0, 160.0)), "第二段为右线")
	check(not action.hits(ORIGIN + Vector2(100.0, -160.0)), "先左后右，左线已结束")
	_run_until(action, func() -> bool: return log.size() == 2, 1.0, log)
	check(log.size() == 2, "一轮 A 招恰好两段")
	_run_until(action, func() -> bool: return not action.is_busy(), 2.0, log)
	check(not action.is_busy(), "结束后回到空闲（含 0.8 秒硬直）")

## c3_boss02：三处沙圈，中心相距至少 6 格。
func _test_circle_boss() -> void:
	var action := BossAction.new(_skill("c3_boss02"))
	var log: Array = []
	check(action.shape == "circle", "c3_boss02 装配圈形 A 招")
	_run_until(action, func() -> bool: return action.is_busy(), 10.0, log)
	var first := action.geometry()
	check(String(first.get("kind", "")) == "circle", "沙圈几何为圆")
	check(action.hits(ORIGIN + Vector2(0.0, -256.0)), "首圈带内结算")
	check(not action.hits(ORIGIN + Vector2(0.0, 256.0)), "圈外安全")
	var centers: Array = []
	centers.append(first.get("center", Vector2.ZERO))
	_run_until(action, func() -> bool: return log.size() == 1 and action.is_warning(), 1.5, log)
	var second := action.geometry()
	centers.append(second.get("center", Vector2.ZERO))
	_run_until(action, func() -> bool: return log.size() == 2 and action.is_warning(), 1.5, log)
	var third := action.geometry()
	centers.append(third.get("center", Vector2.ZERO))
	check(is_equal_approx((centers[0] as Vector2).distance_to(centers[1] as Vector2), 512.0)
		or (centers[0] as Vector2).distance_to(centers[1] as Vector2) > 384.0, "相邻沙圈中心相距至少 6 格")
	check((centers[1] as Vector2).distance_to(centers[2] as Vector2) > 384.0, "二三圈同样拉开")
	_run_until(action, func() -> bool: return log.size() == 3, 3.0, log)
	check(log.size() == 3, "一轮 A 招恰好三段")

## c3_boss03：半径 6 格、70 度扇阵，按 0/120/240 度轮转。
func _test_fan_boss() -> void:
	var action := BossAction.new(_skill("c3_boss03"))
	var log: Array = []
	check(action.shape == "fan", "c3_boss03 装配扇形 A 招")
	_run_until(action, func() -> bool: return action.is_busy(), 10.0, log)
	var geo := action.geometry()
	check(String(geo.get("kind", "")) == "fan", "扇阵几何为扇")
	check(is_equal_approx(float(geo.get("radius", 0.0)), 384.0 * sqrt(2.0)),
		"扇半径 6 格（地面半径 = 屏幕半径 ×√2，等面积）")
	check(action.hits(ORIGIN + Vector2(192.0, 0.0)), "首扇正前方命中")
	check(not action.hits(ORIGIN + Vector2(-192.0, 0.0)), "扇外不命中")
	_run_until(action, func() -> bool: return log.size() == 1 and action.is_warning(), 1.5, log)
	# `dir` 在地面空间；`from_ground` 还原成屏幕指向后才与设计角度可比。
	var dir2: Vector2 = action.geometry().get("dir", Vector2.ZERO)
	var screen_dir := Iso.from_ground(dir2).normalized()
	check(absf(screen_dir.angle_to(Vector2.from_angle(deg_to_rad(120.0)))) < 0.01,
		"第二扇屏幕朝向转到 120 度")
	check(action.hits(ORIGIN + screen_dir * 100.0), "第二扇中线命中")
	check(not action.hits(ORIGIN + Vector2(100.0, 0.0)), "第二扇不再覆盖 0 度方向")
	_run_until(action, func() -> bool: return log.size() == 3, 3.0, log)
	check(log.size() == 3, "一轮 A 招恰好三段")

## B 招：50% 血触发环击，中心 / 圈外可避，每 12 秒复现。
func _test_phase_b() -> void:
	var action := BossAction.new(_skill("c3_boss01"))
	var log: Array = []
	check(action.has_b, "c3_boss01 配置 B 招")
	_advance(action, 0.05, 0.5, log)
	check(action.move == BossAction.Move.B and action.is_warning(), "50% 血进入环击预警")
	var geo := action.geometry()
	check(String(geo.get("kind", "")) == "ring", "B 招几何为环击")
	var inner := float(geo.get("inner", 0.0))
	var outer := float(geo.get("radius", 0.0))
	# 等面积补偿：内 128×√2 = 181.02、外 320×√2 = 452.55（椭圆面积仍 = πr²）
	check(is_equal_approx(inner, 128.0 * sqrt(2.0)), "内圈 2 格可避（×√2）")
	check(is_equal_approx(outer, 320.0 * sqrt(2.0)), "外半径 5 格（×√2）")
	check(action.hits(ORIGIN + Vector2(0.0, 192.0)), "环带内结算")
	check(not action.hits(ORIGIN), "圆心安全")
	# 边界两侧各 1px 双向断言：防「恒真」/「恒假」的假绿
	check(action.hits(ORIGIN + Vector2(inner + 1.0, 0.0)), "内圈外侧 1px 命中")
	check(not action.hits(ORIGIN + Vector2(inner - 1.0, 0.0)), "内圈内侧 1px 不命中")
	check(action.hits(ORIGIN + Vector2(outer - 1.0, 0.0)), "外圈内侧 1px 命中")
	check(not action.hits(ORIGIN + Vector2(outer + 1.0, 0.0)), "圈外 1px 不命中")
	# 纵向：地面距离是屏幕距离的 2 倍，椭圆的纵向半轴只有 outer×0.5。
	# 站在这条「看得见的边界」外侧必须不命中 —— 这条专门咬「只改画、不改判」的假修。
	check(not action.hits(ORIGIN + Vector2(0.0, outer * 0.5 + 2.0)), "纵向可见圈外 2px 不命中")
	check(action.hits(ORIGIN + Vector2(0.0, outer * 0.5 - 2.0)), "纵向可见圈内 2px 命中")
	_run_until(action, func() -> bool: return _count_move(log, BossAction.Move.B) == 1, 0.5, log)
	check(_count_move(log, BossAction.Move.A) == 0, "B 率先进场，与 A 互斥不同时")
	check(is_equal_approx(float((log[0] as Dictionary).c), 1.3), "B 招系数 1.3")
	_run_until(action, func() -> bool: return _count_move(log, BossAction.Move.B) == 2, 0.5, log)
	check(_count_move(log, BossAction.Move.B) == 2, "B 招每 12 秒复现")

## 首领装配 + 脱战归位回满 + 首放前不伤害。
func _test_retreat_and_no_damage() -> void:
	GameState.current_map = "c3_map02"
	var stub := StubPlayer.new()
	stub.name = "StubPlayer"
	add_child(stub)
	stub.add_to_group("player")
	stub.global_position = Vector2(1064.0, 1000.0)
	var boss := (load("res://scenes/entities/Monster.tscn") as PackedScene).instantiate() as Monster
	boss.monster_id = "c3_boss01"
	boss.spawn_level = 25
	boss.ai_enabled = true
	boss.position = Vector2(1000.0, 1000.0)
	add_child(boss)
	boss.set_physics_process(false)
	boss.spawn_position = Vector2(1000.0, 1000.0)
	check(boss.boss_action != null, "c3 首领装配共享动作组件")
	check(is_equal_approx(boss.leash_range, 18.0 * Iso.TILE_W), "首领场参考半径 18 格")
	var hp := stub.hp
	for _i in range(int(round(3.9 * 60.0))):
		boss._update_boss_action(STEP)
	check(not boss.boss_action.is_busy() and stub.hp == hp, "首放前不发招、不伤害")
	# 锁定朝向后横向位移会被线带命中（每段只结算一次）。
	for _i in range(int(round(1.1 * 60.0))):
		boss._update_boss_action(STEP)
	check(boss.boss_action.is_warning(), "4 秒后进入预警")
	stub.global_position = Vector2(1064.0, 840.0)
	for _i in range(int(round(1.1 * 60.0))):
		boss._update_boss_action(STEP)
	check(stub.hp < hp, "预警结束结算位移后的线带命中")
	# 脱战：离场心超过 18 格 → 5 秒后归位回满。
	boss.hp = 1
	boss.boss_phase = 1
	boss.global_position = Vector2(2400.0, 1000.0)
	boss._update_boss_action(STEP)
	check(boss._boss_retreating, "离场心超 18 格进入脱战")
	for _i in range(int(round(5.1 * 60.0))):
		boss._update_boss_action(STEP)
	check(not boss._boss_retreating and boss.hp == boss.max_hp, "脱战 5 秒归位回满")
	check(boss.global_position.distance_to(boss.spawn_position) < 1.0, "归位回场心")
	check(boss.boss_phase == 0, "归位清零二阶段")
	boss.queue_free()
	stub.queue_free()
