extends Node
## R4 能力回归：穿防 / 多段 / 破甲 / 单体语义 / 自动战斗评分。
##
## 存在的理由：`skills.json` 里 `defensePierce` / `hits` / `debuff` 三个字段在 R4 之前
## **引擎一个都不认识**。只把 id 加进可装备列表，玩家会看到「忽视 30% 防御、共 3 段」的描述，
## 实际一击只结算一次、防御一分不少 —— 这比没有技能更糟。本场景守住「描述即行为」。

## 记录受击的假敌人；`apply_armor_break` 只记录调用，Monster 侧实现由第 4 组单独验证。
class DummyEnemy extends Node2D:
	var is_dead := false
	var hits := 0
	var total := 0
	var last_damage := 0
	var defense := 0.0
	var break_calls := 0
	var break_duration := 0.0
	var die_after := 0

	func _ready() -> void:
		add_to_group("enemies")

	func get_defense() -> float:
		return defense

	func get_dodge() -> float:
		return 0.0

	func apply_armor_break(duration: float) -> void:
		break_calls += 1
		break_duration = duration

	func take_hit(result: Dictionary, _from: Node = null) -> void:
		if is_dead:
			return
		hits += 1
		last_damage = int(result.get("damage", 0))
		total += last_damage
		if die_after > 0 and hits >= die_after:
			is_dead = true

var failures: Array[String] = []

var _player: PlayerCharacter

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "wild_trial"
	GameState.player.attack = 200
	GameState.player.criticalChance = 0.0
	GameState.player.mp = 1000
	# 装备加成会影响攻击基线；清空后 `effective_attack_power()` 只由上面两个显式值决定。
	GameState.equipment = {}
	_player = PlayerCharacter.new()
	add_child(_player)
	_player.set_physics_process(false)
	_player.global_position = Vector2(2000, 2000)

	_check_pierce()
	_check_armor_break_state()
	_check_multi_hit()
	_check_single_shape()
	_check_auto_battle()
	_check_wiring()

	_finish()

## ① 穿防：同一攻击力、同一高防目标，`armor_break` 必须按 ×(1−0.3) 的防御结算。
func _check_pierce() -> void:
	GameState.player.level = 25
	GameState.player.mp = 1000
	_player.skill_cooldowns.clear()
	_player._attack_cd = 0.0
	var defense := 200.0
	var enemy := _dummy(_player.global_position + Vector2(60, 0), defense)
	var power := _player.effective_attack_power()
	var pierced := maxi(1, int(floorf(power * 2.0 - defense * 0.7 * 0.5)))
	var plain := maxi(1, int(floorf(power * 2.0 - defense * 0.5)))
	# 用例自身必须有区分度：两式相等时下面那条断言是假绿。
	_check(pierced > plain, "穿防样本无区分度（攻 %.0f / 防 %.0f）：%d 对 %d" % [power, defense, pierced, plain])
	_check(_player.cast_skill("armor_break", enemy), "Lv25 应可施放破甲重击")
	_check(enemy.last_damage == pierced,
		"破甲重击应按忽视 30%% 防御结算：实际 %d，期望 %d（未生效会是 %d）" % [enemy.last_damage, pierced, plain])
	_check(enemy.break_calls == 1 and is_equal_approx(enemy.break_duration, 5.0),
		"命中后应给目标挂 5 秒破甲：调用 %d 次 / %.1f 秒" % [enemy.break_calls, enemy.break_duration])
	enemy.global_position = _player.global_position + Vector2(2000, 0)

## ② 破甲状态机：默认不触发、期间 ×0.7、到期恢复、重复命中取较长时长。
func _check_armor_break_state() -> void:
	var monster := Monster.new()
	monster.defense_power = 100.0
	_check(is_equal_approx(monster.get_defense(), 100.0), "未破甲时防御应保持模板值")
	monster.tick_status(1.0)
	_check(is_equal_approx(monster.get_defense(), 100.0), "没有破甲时计时不应改变防御")
	monster.apply_armor_break(5.0)
	_check(is_equal_approx(monster.get_defense(), 70.0),
		"破甲期间防御应 ×0.7，实际 %.1f" % monster.get_defense())
	monster.tick_status(2.0)
	_check(is_equal_approx(monster.armor_break_remaining(), 3.0) and is_equal_approx(monster.get_defense(), 70.0),
		"破甲未到期应继续生效（剩余 %.2f）" % monster.armor_break_remaining())
	monster.tick_status(3.5)
	_check(is_equal_approx(monster.armor_break_remaining(), 0.0) and is_equal_approx(monster.get_defense(), 100.0),
		"破甲到期后防御应恢复原值，实际 %.1f" % monster.get_defense())
	monster.apply_armor_break(2.0)
	monster.apply_armor_break(5.0)
	_check(is_equal_approx(monster.armor_break_remaining(), 5.0),
		"重复命中取较长时长，不叠加也不缩短：%.2f" % monster.armor_break_remaining())
	monster.free()

## ③ 多段：3 段独立结算、只扣一次蓝、只设一次攻击间隔；目标半途死亡即收手。
func _check_multi_hit() -> void:
	GameState.player.level = 40
	GameState.player.mp = 1000
	_player.skill_cooldowns.clear()
	_player._attack_cd = 0.0
	var target := _dummy(_player.global_position + Vector2(60, 0), 0.0)
	_check(_player.cast_skill("spirit_storm", target), "Lv40 应可施放灵刃风暴")
	_check(target.hits == 3, "灵刃风暴应结算 3 段，实际 %d 段" % target.hits)
	_check(int(GameState.player.mp) == 1000 - 60, "3 段只扣一次蓝，实际剩余 %d" % int(GameState.player.mp))
	_check(is_equal_approx(_player._attack_cd, _player.effective_attack_interval()),
		"3 段只设一次攻击间隔，实际 %.3f" % _player._attack_cd)
	target.global_position = _player.global_position + Vector2(2000, 0)

	GameState.player.mp = 1000
	_player.skill_cooldowns.clear()
	_player._attack_cd = 0.0
	var fragile := _dummy(_player.global_position + Vector2(60, 0), 0.0)
	fragile.die_after = 2
	_check(_player.cast_skill("spirit_storm", fragile), "第 2 段死亡前施放仍应成功")
	_check(fragile.hits == 2, "目标第 2 段死亡后不应再吃第 3 段，实际 %d 段" % fragile.hits)
	fragile.global_position = _player.global_position + Vector2(2000, 0)

## ④ 单体语义：`shape=single` 只命中显式目标（否则破甲重击会变成隐形势 AoE）。
func _check_single_shape() -> void:
	var near := _dummy(_player.global_position + Vector2(30, 0), 0.0)
	var aside := _dummy(_player.global_position + Vector2(0, 45), 0.0)
	var skill: Dictionary = DataLoader.get_entry("skills", "armor_break")
	var picked := _player.skill_targets(skill, near)
	_check(picked.size() == 1 and picked[0] == near,
		"单体技能只应命中显式目标，实际命中 %d 个" % picked.size())
	_check(_player.skill_targets(skill, aside).size() == 1,
		"换一个显式目标仍只命中一个")
	near.global_position = _player.global_position + Vector2(2000, 0)
	aside.global_position = _player.global_position + Vector2(0, 2000)

## ⑤ 自动战斗评分：多段按「命中数 × 总系数」参评，单体技能走独立路径。
func _check_auto_battle() -> void:
	_check(is_equal_approx(AutoBattle.skill_value(DataLoader.get_entry("skills", "spirit_storm")), 3.0),
		"灵刃风暴价值应为单段 1.0 × 3 段 = 3.0")
	_check(is_equal_approx(AutoBattle.skill_value(DataLoader.get_entry("skills", "earth_cleave")), 1.4),
		"单段技能价值应等于系数")
	var pilot := AutoBattle.new()
	_player.add_child(pilot)
	pilot.set_physics_process(false)
	GameState.player.level = 40
	GameState.player.mp = 1000
	_player.skill_cooldowns.clear()
	_player._attack_cd = 0.0
	var first := _dummy(_player.global_position + Vector2(40, 0), 0.0)
	var second := _dummy(_player.global_position + Vector2(-40, 0), 0.0)
	var third := _dummy(_player.global_position + Vector2(0, 50), 0.0)
	_check(String(pilot._best_area_skill(first).get("id", "")) == "spirit_storm",
		"3 目标时应按总系数选灵刃风暴，实际 %s" % String(pilot._best_area_skill(first).get("id", "")))
	GameState.player.level = 25
	_check(String(pilot._best_single_skill(first).get("id", "")) == "armor_break",
		"单体目标应选破甲重击，实际 %s" % String(pilot._best_single_skill(first).get("id", "")))
	GameState.player.level = 24
	_check(pilot._best_single_skill(first).is_empty(), "未解锁时单体路径应回退普攻")
	for d in [first, second, third]:
		(d as Node2D).global_position = _player.global_position + Vector2(2000, 0)
	pilot.queue_free()

## ⑥ 接线：可装备列表与数据全量一致（少一条就等于玩家永远拖不进）。
## 工程 98：口径从「一个固定 6 条表」升级为「两职业并集」——
## 这里同时断「并集 == skills.json 全量」与「每个职业各 6 条且不含他职业技能」，
## 只断前者会让「两条法师技能误挂到武士名下」照样全绿。
func _check_wiring() -> void:
	var skills: Variant = DataLoader.get_table("skills")
	var expected := 0
	if skills is Array:
		expected = (skills as Array).size()
	_check(HotbarConfig.ACTIVE_SKILLS.size() == expected,
		"可装备技能应覆盖 skills.json 全量 %d 条，实际 %d" % [expected, HotbarConfig.ACTIVE_SKILLS.size()])
	var union: Array = []
	for class_id in PlayerClass.ids():
		var list := HotbarConfig.active_skills(String(class_id))
		_check(list.size() == 6, "%s 应有 6 条技能（含普攻），实际 %d" % [String(class_id), list.size()])
		for sid in list:
			if not union.has(sid):
				union.append(sid)
	union.sort()
	var declared: Array = HotbarConfig.ACTIVE_SKILLS.duplicate()
	declared.sort()
	_check(union == declared, "各职业技能并集应与 ACTIVE_SKILLS 完全一致")
	_check(not HotbarConfig.usable_skill("meteor", "warrior"), "武士不得使用法师技能")
	_check(not HotbarConfig.usable_skill("spirit_storm", "mage"), "法师不得使用武士技能")
	_check(HotbarConfig.valid_entry({"kind": "skill", "id": "armor_break"}), "破甲重击应可拖入快捷栏")
	_check(HotbarConfig.valid_entry({"kind": "skill", "id": "spirit_storm"}), "灵刃风暴应可拖入快捷栏")
	_check(HotbarConfig.valid_entry({"kind": "skill", "id": "meteor"}), "陨石术应可拖入快捷栏")

func _dummy(at: Vector2, defense: float) -> DummyEnemy:
	var enemy := DummyEnemy.new()
	add_child(enemy)
	enemy.global_position = at
	enemy.defense = defense
	return enemy

func _finish() -> void:
	if failures.is_empty():
		print("[SkillCapabilityTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("[SkillCapabilityTest] " + failure)
		print("[SkillCapabilityTest] ", failures)
		get_tree().quit(1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
