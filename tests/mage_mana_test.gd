extends Node
## 工程 98 第三层：法师「按最大法力百分比计费」契约。
##
## 为什么不能沿用武士的固定蓝耗：装备把蓝池堆到 15 万，武士的 15—60 点蓝耗等于免费。
## 法师若也写固定值，「高蓝」就只是数字，魔法盾也就没有压力。
##
## 守三件事：
##   ① 唯一口径 `GameState.skill_mana_cost()` 真的按 `max_mp()` 算（不是按某个常量）；
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

## 3% × 最大法力，四舍五入 —— 口径必须能一眼复算出来。
func _test_cost_formula() -> void:
	GameState.reset_to_defaults("mage")
	GameState.player.level = 30
	var expected := int(round(float(GameState.max_mp()) * 0.03))
	check(GameState.skill_mana_cost(_lightning()) == expected,
		"雷电术耗蓝应为 max_mp 的 3%%（%.0f → %d），实际 %d"
		% [float(GameState.max_mp()), expected, GameState.skill_mana_cost(_lightning())])
	var shield: Dictionary = SkillProgression.current("magic_shield")
	check(GameState.skill_mana_cost(shield) == int(round(float(GameState.max_mp()) * 0.06)),
		"魔法盾开盾应为 max_mp 的 6%")

## 蓝池翻倍，费用必须跟着翻倍 —— 写死常量会在这里红。
func _test_cost_follows_max_mp() -> void:
	GameState.reset_to_defaults("mage")
	GameState.player.level = 30
	var before_mp := GameState.max_mp()
	var before_cost := GameState.skill_mana_cost(_lightning())
	GameState.player.mpFlat = 50000
	var after_mp := GameState.max_mp()
	var after_cost := GameState.skill_mana_cost(_lightning())
	check(after_mp > before_mp * 2, "用例前提：加蓝装后蓝池应显著变大（%d → %d）" % [before_mp, after_mp])
	check(after_cost == int(round(float(after_mp) * 0.03)),
		"耗蓝必须跟着蓝池走（%d → %d），实际 %d" % [before_cost, int(round(float(after_mp) * 0.03)), after_cost])
	GameState.player.mpFlat = 0

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
	var text := Localization.tr_key("ui.skill_panel.detail_meta_pct", [3, 4587, "4.5 格"])
	check(text.contains("3%"), "详情应显示 3%%，实际：%s" % text)
	check(text.contains("4587"), "详情应同时给出绝对量，实际：%s" % text)
	check(not text.contains("%d") and not text.contains("%s"), "详情不得残留格式占位符，实际：%s" % text)
