extends Node
## 工程 98/103：法师攻击法术按加权容量计费、魔法盾按新最大法力计费。
##
## 为什么不能沿用武士的固定蓝耗：装备把蓝池堆到 15 万，武士的 15—60 点蓝耗等于免费。
## 法师若也写固定值，「高蓝」就只是数字，魔法盾也就没有压力。
##
## 守三件事：
##   ① 唯一口径 `GameState.skill_mana_cost()` 用新旧法力池加权，扩蓝确实增加可施法次数；
##   ② 蓝不够时**不施放、不进入冷却、不扣蓝**（T11）；
##   ③ 详情浮层显示的是百分比口径，且格式化不出 %d 原文（裸 % 的老坑）。

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

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[MageManaTest] " + label)

func _ready() -> void:
	_test_cost_formula()
	_test_cost_follows_max_mp()
	_test_high_level_cast_budget()
	_test_insufficient_mp()
	_test_warrior_stays_fixed()
	_test_tooltip_format()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[MageManaTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[MageManaTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

func _lightning() -> Dictionary:
	return SkillProgression.current("lightning")

## 1.2% × 加权法力参考池，四舍五入 —— 口径必须能一眼复算出来。
## ⚠ 工程 98 修订：技能 CD 从 5s 压到 0.6s（≈1 个攻击间隔）后，单次蓝耗必须同比例下调，
## 否则每秒蓝耗从 0.6% 涨到 5% 以上，蓝池 20 秒见底。费率是绝对判据（不复用被测常量）：
## 数据被改回 3% 时这条会红，那是它该报告的内容，不是「数字不好看」。
func _test_cost_formula() -> void:
	GameState.reset_to_defaults("mage")
	GameState.player.level = 30
	var reference := 0.55 * float(GameState.max_mp()) + 0.45 * float(GameState.legacy_max_mp())
	var expected := int(round(reference * 0.012))
	check(GameState.skill_mana_cost(_lightning()) == expected,
		"雷电术耗蓝应为参考池的 1.2%%（%.0f → %d），实际 %d"
		% [reference, expected, GameState.skill_mana_cost(_lightning())])
	var shield: Dictionary = SkillProgression.current("magic_shield")
	check(GameState.skill_mana_cost(shield) == int(round(float(GameState.max_mp()) * 0.06)),
		"魔法盾开盾应为 max_mp 的 6%")

## 扩蓝后费用仍增长，但低于蓝池增长倍数 —— 玩家可施放次数确实增加。
func _test_cost_follows_max_mp() -> void:
	GameState.reset_to_defaults("mage")
	GameState.player.level = 30
	var before_mp := GameState.max_mp()
	var before_cost := GameState.skill_mana_cost(_lightning())
	GameState.player.mpFlat = 50000
	var after_mp := GameState.max_mp()
	var after_cost := GameState.skill_mana_cost(_lightning())
	check(after_mp > before_mp * 2, "用例前提：加蓝装后蓝池应显著变大（%d → %d）" % [before_mp, after_mp])
	var expected := int(round((0.55 * float(after_mp) + 0.45 * float(GameState.legacy_max_mp())) * 0.012))
	check(after_cost == expected and after_cost > before_cost,
		"费用随容量温和增长（%d → %d），实际 %d" % [before_cost, expected, after_cost])
	GameState.player.mpFlat = 0

func _test_high_level_cast_budget() -> void:
	GameState.reset_to_defaults("mage")
	GameState.player.level = 160
	GameState.player.attack = Balance.base_attack(160)
	GameState.player.defense = Balance.base_defense(160)
	var old_pool := GameState.legacy_max_mp()
	var new_pool := GameState.max_mp()
	var cost := GameState.skill_mana_cost(_lightning())
	var old_cost := int(round(float(old_pool) * 0.012))
	check(new_pool > old_pool and float(new_pool) / float(cost) > float(old_pool) / float(old_cost) * 1.2,
		"高等级扩蓝应让雷电可施放次数至少增加 20%%（旧 %d/%d，新 %d/%d）" % [old_pool, old_cost, new_pool, cost])
	var shield: Dictionary = SkillProgression.current("magic_shield")
	check(GameState.skill_mana_cost(shield) == int(round(float(new_pool) * 0.06)),
		"魔法盾仍按新上限 6%% 开盾，不随法术折算降价")

## 蓝不足：不施放、不扣蓝、不进入冷却（三条缺一都会让玩家「以为放了」）。
func _test_insufficient_mp() -> void:
	GameState.reset_to_defaults("mage")
	GameState.current_map = "wild_trial"
	GameState.player.level = 30
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(3000, 3000)
	var enemy := TestEnemy.new()
	add_child(enemy)
	enemy.global_position = player.global_position + Vector2(3.0 * TILE, 0)
	var cost := GameState.skill_mana_cost(_lightning())
	GameState.player.mp = cost - 1
	player._attack_cd = 0.0
	check(not player.cast_skill("lightning", enemy),
		"蓝差 1 点时不得施放（需要 %d，只有 %d）" % [cost, int(GameState.player.mp)])
	check(player.skill_cooldown("lightning") == 0.0, "施放失败不得进入冷却")
	check(int(GameState.player.mp) == cost - 1, "施放失败不得扣蓝")
	check(enemy.hits == 0, "施放失败不得结算伤害")
	GameState.player.mp = cost
	player._attack_cd = 0.0
	check(player.cast_skill("lightning", enemy), "蓝刚好够时必须能施放")
	check(int(GameState.player.mp) == 0, "应恰好扣掉 %d 点，剩余 %d" % [cost, int(GameState.player.mp)])
	check(player.skill_cooldown("lightning") > 0.0, "施放成功必须进入冷却")
	check(enemy.hits == 1, "雷电术应对目标结算一次")
	player.queue_free()
	enemy.queue_free()

## 武士的固定蓝耗一个字节都不许动。
func _test_warrior_stays_fixed() -> void:
	GameState.reset_to_defaults("warrior")
	GameState.player.level = 30
	var cleave: Dictionary = SkillProgression.current("earth_cleave")
	check(int(cleave.get("manaCost", 0)) == 15, "武士裂地斩的基础蓝耗应仍为 15")
	GameState.player.mpFlat = 100000
	check(GameState.skill_mana_cost(cleave) == 15,
		"武士固定蓝耗不得随蓝池变化（实际 %d）" % GameState.skill_mana_cost(cleave))
	GameState.player.mpFlat = 0

## 浮层文案：必须出现百分比且不残留 `%d` 原文（裸 % 遇带参格式化会静默返回原文）。
func _test_tooltip_format() -> void:
	var text := Localization.tr_key("ui.skill_panel.detail_meta_pct", ["1.2", 4587, "4.5 格"])
	check(text.contains("1.2%") and text.contains("折算"), "详情应显示系数与折算口径，实际：%s" % text)
	check(text.contains("4587"), "详情应同时给出绝对量，实际：%s" % text)
	check(not text.contains("%d") and not text.contains("%s"), "详情不得残留格式占位符，实际：%s" % text)
	var shield_text := Localization.tr_key("ui.skill_panel.detail_meta_shield", ["6.0", 1234, "自身"])
	check(shield_text.contains("6.0% 法力上限") and shield_text.contains("1234"),
		"魔法盾需明确仍按最大蓝量百分比计费")
