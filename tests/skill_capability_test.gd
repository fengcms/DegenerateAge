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
	## 工程 107：幅度也由数据给，mock 必须一起接住 —— 少一个形参就是运行时
	## `Invalid call ... Expected 1 argument(s)`，整条用例链静默报废（只报「未输出完成标记」）。
	var break_scale := -1.0
	var die_after := 0

	func _ready() -> void:
		add_to_group("enemies")

	func get_defense() -> float:
		return defense

	func get_dodge() -> float:
		return 0.0

	func apply_armor_break(duration: float, scale: float = 0.7) -> void:
		break_calls += 1
		break_duration = duration
		break_scale = scale

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
	_check_circle_cap()

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
	# 系数与穿防比例**从数据取**：这两个值是平衡参数，写死会让每次调数值都红一遍，
	# 而这条用例要守的是「defensePierce 有没有真的参与结算」。另配 `pierce > 0` 与
	# `pierced > plain` 两条绝对判据，防止「数据把穿防改成 0 时本用例照样绿」。
	var spec: Dictionary = SkillProgression.current("armor_break")
	var coeff := float(spec.get("coefficient", 0.0))
	var pierce := float(spec.get("defensePierce", 0.0))
	_check(pierce > 0.0 and coeff > 0.0,
		"数据应有正系数与正穿防比例（系数 %.2f / 穿防 %.2f）" % [coeff, pierce])
	var pierced := maxi(1, int(floorf(power * coeff - defense * (1.0 - pierce) * 0.5)))
	var plain := maxi(1, int(floorf(power * coeff - defense * 0.5)))
	# 用例自身必须有区分度：两式相等时下面那条断言是假绿。
	_check(pierced > plain, "穿防样本无区分度（攻 %.0f / 防 %.0f）：%d 对 %d" % [power, defense, pierced, plain])
	_check(_player.cast_skill("armor_break", enemy), "Lv25 应可施放破甲重击")
	_check(enemy.last_damage == pierced,
		"破甲重击应按忽视 %.0f%% 防御结算：实际 %d，期望 %d（未生效会是 %d）" % [pierce * 100.0, enemy.last_damage, pierced, plain])
	# 工程 107：破甲时长与幅度都从数据下发（1 阶 6.0 秒 / 0.70），不再是写死常量。
	var want_dur := float((spec.get("debuff", {}) as Dictionary).get("duration", 0.0))
	var want_scale := float((spec.get("debuff", {}) as Dictionary).get("defenseScale", 0.7))
	_check(want_dur > 0.0 and want_scale > 0.0 and want_scale < 1.0,
		"数据应有正时长且幅度在 (0,1) 内（时长 %.1f / 保留 %.2f）" % [want_dur, want_scale])
	_check(enemy.break_calls == 1 and is_equal_approx(enemy.break_duration, want_dur),
		"命中后应给目标挂 %.1f 秒破甲（读自数据）：调用 %d 次 / %.1f 秒" % [want_dur, enemy.break_calls, enemy.break_duration])
	_check(is_equal_approx(enemy.break_scale, want_scale),
		"破甲幅度应随数据下发（%.2f）：实际 %.2f（传丢会退回缺省 0.70）" % [want_scale, enemy.break_scale])
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
	# 工程 107：幅度可被数据覆盖（破甲重击 5 阶 0.58），三条语义各断一次。
	monster.apply_armor_break(5.0, 0.58)
	_check(is_equal_approx(monster.get_defense(), 58.0),
		"显式幅度应生效（0.58 ⇒ 58.0），实际 %.1f" % monster.get_defense())
	monster.apply_armor_break(5.0, 0.7)
	_check(is_equal_approx(monster.get_defense(), 58.0),
		"弱幅度不得覆盖强幅度（否则谁最后打谁说了算，玩家无法预期）：实际 %.1f" % monster.get_defense())
	monster.tick_status(99.0)
	_check(is_equal_approx(monster.get_defense(), 100.0), "长期计时后破甲应自然到期")
	monster.apply_armor_break(5.0)
	_check(is_equal_approx(monster.get_defense(), 70.0),
		"新一次破甲应回到缺省幅度（0.7 ⇒ 70.0），实际 %.1f" % monster.get_defense())
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
	# 工程 107：武士耗蓝改成百分比，写死 60 会随蓝池漂移。这里守的是**次数**（3 段只扣一次），
	# 所以用 `skill_mana_cost` 当单位是刻意的 —— 另配 `cost > 0` 防止「耗蓝被改成 0 照样绿」。
	var storm_cost := GameState.skill_mana_cost(SkillProgression.current("spirit_storm"))
	_check(storm_cost > 0, "灵刃风暴耗蓝应大于 0，实际 %d" % storm_cost)
	_check(1000 - int(GameState.player.mp) == storm_cost,
		"3 段只扣一次蓝（单次口径 %d），实际扣了 %d" % [storm_cost, 1000 - int(GameState.player.mp)])
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
	# 单段技能的价值 = 单段系数（这是同一性断言，系数必须从数据取；写死会在每次调数值时误红）。
	var cleave_coeff := float(DataLoader.get_entry("skills", "earth_cleave").get("coefficient", 0.0))
	_check(cleave_coeff > 0.0, "裂地斩系数应为正数")
	_check(is_equal_approx(AutoBattle.skill_value(DataLoader.get_entry("skills", "earth_cleave")), cleave_coeff),
		"单段技能价值应等于系数（%.2f）" % cleave_coeff)
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

## ⑦ 圆形上限（工程 107 B2-b）：灵刃风暴 maxTargets 8，旋风斩缺省不限。
## 守的是「circle 分支也开始吃 maxTargets 了」—— 107 之前该分支根本不读这个字段，
## 写进数据也不生效且零报错，属于「配了等于没配」的静默失效。
## 两个方向都要断：写上限必须停在上限，**没写必须仍然不限**（否则旧技能被偷偷削）。
func _check_circle_cap() -> void:
	# 前一组把等级压到 24 验证「未解锁回退普攻」，这里必须拉回 40 —— 否则
	# `SkillProgression.current()` 返回空字典，上限读成 0，用例会以「构造前提不成立」失败
	# （而这个失败指向的是等级，不是上限逻辑）。
	GameState.player.level = 40
	var center := _player.global_position
	var swarm: Array[Node2D] = []
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		swarm.append(_dummy(center + Vector2(cos(angle), sin(angle)) * 100.0, 0.0))
	var storm: Dictionary = SkillProgression.current("spirit_storm")
	var cap := int(storm.get("maxTargets", 0))
	_check(cap > 0 and cap < swarm.size(),
		"构造前提：灵刃风暴应有上限且小于样本数（上限 %d / 样本 %d）" % [cap, swarm.size()])
	_check(_player.skill_targets(storm, null).size() == cap,
		"配了上限的圆形技能应停在 %d 只，实际 %d" % [cap, _player.skill_targets(storm, null).size()])
	var whirl: Dictionary = SkillProgression.current("whirlwind")
	_check(not whirl.has("maxTargets"), "构造前提：旋风斩不应配 maxTargets（缺省即不限）")
	_check(_player.skill_targets(whirl, null).size() == swarm.size(),
		"未配上限的圆形技能必须命中全部 %d 只，实际 %d" % [swarm.size(), _player.skill_targets(whirl, null).size()])
	for e in swarm:
		e.global_position = center + Vector2(5000, 0)

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
