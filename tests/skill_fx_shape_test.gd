extends Node
## 工程 105 守门：单体技能不得绘制范围提示，雷电术走专属落雷特效。
##
## 背景：`skill_range_fx` 原来只有 `if shape == "cone"` 一个分支，其余全落进 `else`
## 画地面圆盘。雷电术 `shape = "single"`、`range = 6.5` ⇒ **半径 416px、横向占屏幕 65%**
## 的大椭圆（工程 105 §1.2）。「范围提示」的语义是「这一片都会被打」，单体画它 = 误导玩家。
##
## 守四件事：
##   A  `single` 一次地面几何都不画（逻辑层 `draws_ground` + 行为层 `ground_draws`）
##   B  `circle` / `cone` 仍照常绘制 —— 防止一刀切把真 AoE 的提示也删了
##   C  雷电术按 `skills.json` 的 `fx` 分派：产生落雷节点、**不产生**飞行投射物
##   D  未知 `shape` 不画 —— 防止 `else` 兜底复活（坑清单第 64 条同构）

const TILE := 64.0
const RangeFxScript := preload("res://scripts/systems/skill_range_fx.gd")

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

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[SkillFxShapeTest] " + label)

func _ready() -> void:
	await _test_single_draws_nothing()
	await _test_area_shapes_still_draw()
	_test_thunder_data()
	await _test_thunder_dispatch()
	await _test_unknown_shape_draws_nothing()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[SkillFxShapeTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[SkillFxShapeTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- A：single 不画 ----

func _test_single_draws_nothing() -> void:
	# 逻辑层：纯函数，不依赖渲染，任何环境都可靠。
	check(not RangeFxScript.draws_ground("single"),
		"逻辑层：single 必须被判为「不绘制地面几何」")
	# 行为层：真跑一次 `_draw`，数它到底发出了几次几何绘制。
	var fx := _make_range_fx("single")
	await get_tree().process_frame
	await get_tree().process_frame
	# 🔴 这一条是 A 组的前提，不是凑数：headless 若不触发 `_draw`，下面的
	# `ground_draws == 0` 会静默假绿。它红了说明判据要换，而不是把断言删掉。
	check(int(fx.draw_calls) > 0,
		"行为层前提：single 的 _draw 必须真的被执行过（否则 ground_draws 断言无意义）")
	check(int(fx.ground_draws) == 0,
		"single 一次地面几何都不得绘制，实际 %d 次" % int(fx.ground_draws))
	fx.queue_free()
	await get_tree().process_frame

# ---- B：circle / cone 照旧 ----

func _test_area_shapes_still_draw() -> void:
	for shape_id in ["circle", "cone"]:
		check(RangeFxScript.draws_ground(shape_id),
			"逻辑层：%s 必须仍被判为「要绘制地面几何」" % shape_id)
		var fx := _make_range_fx(shape_id)
		await get_tree().process_frame
		await get_tree().process_frame
		check(int(fx.ground_draws) > 0,
			"%s 必须照常绘制地面几何（否则真 AoE 的范围提示被一刀切删掉了），实际 %d 次" % [
				shape_id, int(fx.ground_draws)])
		fx.queue_free()
		await get_tree().process_frame

# ---- C：雷电术走数据驱动分派 ----

## 数据层：分派键必须真的在 `skills.json` 里，而不是靠代码里写死技能 id。
## 用 `DataLoader.get_entry` 直接读原始数据，**不经过** `SkillProgression.current` ——
## 后者按 `GameState.skill_rank` 过滤（未解锁返回空字典），会让这条断言依赖玩家状态。
func _test_thunder_data() -> void:
	var raw: Variant = DataLoader.get_entry("skills", "lightning")
	check(raw is Dictionary, "雷电术必须在 skills.json 里存在")
	if not (raw is Dictionary):
		return
	var skill: Dictionary = raw
	check(String(skill.get("fx", "")) == "thunder",
		"雷电术必须在 skills.json 标 fx=thunder，实际「%s」" % String(skill.get("fx", "")))
	check(String(skill.get("shape", "")) == "single",
		"雷电术必须是单体（shape=single），实际「%s」" % String(skill.get("shape", "")))
	# 射程变了，落雷高度（BOLT_HEIGHT）也要重新评估 —— 这里只守住「别静默改小」。
	var reach := float(skill.get("range", 1.0)) * Iso.TILE_W
	check(reach > 6.0 * TILE,
		"雷电术射程应仍在 6 格以上（%.0fpx）；射程变了这条要重新评估落雷高度" % reach)

func _test_thunder_dispatch() -> void:
	var player := _make_player("mage")
	var enemy := _enemy(player.global_position + Vector2(3.0 * TILE, 0))
	var before_thunder := _count_children("thunder_fx.gd")
	var before_bolt := _count_children("player_projectile.gd")
	check(player.cast_skill("lightning", enemy), "雷电术应能在射程内施放成功")
	check(_count_children("thunder_fx.gd") == before_thunder + 1,
		"雷电术必须生成 1 个落雷节点，实际新增 %d 个" % [
			_count_children("thunder_fx.gd") - before_thunder])
	check(_count_children("player_projectile.gd") == before_bolt,
		"雷电术不得再生成飞行投射物（雷电是瞬时天降，不是「扔一颗球」）")
	# 落雷必须落在**目标身上**，不是玩家脚下，也不是世界原点。
	var thunder := _find_child("thunder_fx.gd")
	check(thunder != null, "应能找到落雷节点")
	if thunder != null:
		check((thunder as Node2D).global_position.distance_to(enemy.global_position) < 1.0,
			"落雷原点必须对齐目标位置，实际偏差 %.1fpx" % [
				(thunder as Node2D).global_position.distance_to(enemy.global_position)])
	player.queue_free()
	enemy.queue_free()
	await get_tree().process_frame

# ---- D：未知形状不得兜底成圆 ----

func _test_unknown_shape_draws_nothing() -> void:
	check(not RangeFxScript.draws_ground("line"),
		"逻辑层：未识别的 shape 必须被判为「不绘制」")
	var fx := _make_range_fx("line")
	await get_tree().process_frame
	await get_tree().process_frame
	check(int(fx.draw_calls) > 0, "行为层前提：未知形状的 _draw 也必须真的被执行过")
	check(int(fx.ground_draws) == 0,
		"未识别的 shape 不得绘制任何地面几何（否则 else 兜底复活），实际 %d 次" % int(fx.ground_draws))
	fx.queue_free()
	await get_tree().process_frame

# ---- 夹具 ----

func _make_range_fx(shape_id: String) -> Node2D:
	var fx := RangeFxScript.new() as Node2D
	fx.shape = shape_id
	# 用雷电术的真实半径（6.5 格）作夹具：这正是当初画出 416px 椭圆的那个值，
	# 用 1 格会因为「圈太小看不出问题」而失去守门意义。
	fx.radius = 6.5 * TILE
	add_child(fx)
	return fx

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

func _count_children(script_tail: String) -> int:
	var n := 0
	for child in get_children():
		if _is_script(child, script_tail):
			n += 1
	return n

func _find_child(script_tail: String) -> Node:
	for child in get_children():
		if _is_script(child, script_tail):
			return child
	return null

func _is_script(node: Node, script_tail: String) -> bool:
	var script: Variant = node.get_script()
	return script is Script and String((script as Script).resource_path).ends_with(script_tail)
