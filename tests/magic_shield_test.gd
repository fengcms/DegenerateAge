extends Node
## 工程 98 Q4=A：魔法盾契约（受伤 35% 转由法力承担，1 伤害 = 1 蓝）。
##
## 这条是「传奇味」的全部来源，也是最容易做成白送的地方（R6）：
## 只减伤不扣蓝 ⇒ 法师直接强于武士，而且测试照样绿（如果只断「掉血变少」）。
## 所以每个用例都同时断**扣了多少血**与**扣了多少蓝**，两侧夹逼。
##
## 另外两个必须钉死的边界：
##   · 蓝不够时按**剩余量**转嫁，余下全部扣血（不是「蓝不够就完全免伤」）；
##   · 武士没有任何 buff 带这个键 ⇒ 行为必须逐位不变（0.0 早退路径）。

const TILE := 64.0

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[MagicShieldTest] " + label)

func _ready() -> void:
	_test_cast_costs_mana()
	_test_absorbs_share()
	_test_mana_exhausted()
	_test_partial_mana()
	_test_expired()
	_test_rank_effect()
	_test_warrior_unchanged()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[MagicShieldTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[MagicShieldTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

func _make_player() -> PlayerCharacter:
	GameState.reset_to_defaults("mage")
	GameState.current_map = "wild_trial"
	GameState.player.level = 60
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(4000, 4000)
	# 血 / 蓝都给到远高于单次 1000 的量：`apply_damage` 的返回值会被 `mini(伤害, 当前血)`
	# 夹到现存血量，血少了会让「扣血 650」变成「扣血 = 当前血」，把用例本身测坏。
	GameState.player.hp = 100000
	GameState.player.mp = 100000
	return player

## 开盾要花 6% 上限的蓝，并且进入冷却。
func _test_cast_costs_mana() -> void:
	var player := _make_player()
	var cost := GameState.skill_mana_cost(SkillProgression.current("magic_shield"))
	var before := int(GameState.player.mp)
	check(player.cast_skill("magic_shield"), "Lv60 应能开启魔法盾")
	check(int(GameState.player.mp) == before - cost,
		"开盾应扣 %d 点蓝（%d → %d）" % [cost, before, int(GameState.player.mp)])
	check(GameState.buff_remaining("magic_shield") > 0.0, "开盾后 buff 必须生效")
	check(player.skill_cooldown("magic_shield") > 0.0, "开盾必须进入冷却")
	player.queue_free()

## 核心：1000 点伤害 → 扣血 650 / 扣蓝 350（按 buff 的 0.35 转嫁）。
func _test_absorbs_share() -> void:
	var player := _make_player()
	GameState.start_buff("magic_shield")
	var mp_before := int(GameState.player.mp)
	var hp_before := int(GameState.player.hp)
	var taken := player.apply_damage(1000)
	check(taken == 650, "开盾后 1000 点伤害应只扣 650 血，实际 %d" % taken)
	check(hp_before - int(GameState.player.hp) == 650,
		"血条应减少 650，实际 %d" % (hp_before - int(GameState.player.hp)))
	check(mp_before - int(GameState.player.mp) == 350,
		"蓝条应减少 350（只减伤不扣蓝就是白送），实际 %d" % (mp_before - int(GameState.player.mp)))
	player.queue_free()

## 蓝干了：转嫁 0，1000 点全额扣血 —— 这就是「断蓝即变脆」。
func _test_mana_exhausted() -> void:
	var player := _make_player()
	GameState.start_buff("magic_shield")
	GameState.player.mp = 0
	var taken := player.apply_damage(1000)
	check(taken == 1000, "蓝为 0 时 1000 点伤害必须全额扣血，实际 %d" % taken)
	check(int(GameState.player.mp) == 0, "蓝为 0 时不得变成负数")
	player.queue_free()

## 蓝只够转嫁一部分：余下照常扣血（不能出现「蓝不足 ⇒ 免伤」）。
func _test_partial_mana() -> void:
	var player := _make_player()
	GameState.start_buff("magic_shield")
	GameState.player.mp = 100
	var taken := player.apply_damage(1000)
	check(taken == 900, "蓝只有 100 时应转嫁 100、扣血 900，实际 %d" % taken)
	check(int(GameState.player.mp) == 0, "剩余蓝应被扣干")
	player.queue_free()

## 盾到期（buff 移除）后恢复全额扣血。
func _test_expired() -> void:
	var player := _make_player()
	GameState.start_buff("magic_shield")
	GameState.tick_buffs(31.0)
	check(GameState.buff_remaining("magic_shield") == 0.0, "31 秒后盾应过期（持续 30 秒）")
	var mp_before := int(GameState.player.mp)
	check(player.apply_damage(1000) == 1000, "盾过期后应全额扣血")
	check(int(GameState.player.mp) == mp_before, "盾过期后不得扣蓝")
	player.queue_free()

## 升阶必须真生效：5 阶 = 47%，不是写死 35%。
func _test_rank_effect() -> void:
	var player := _make_player()
	GameState.skill_ranks["magic_shield"] = 5
	GameState.start_buff("magic_shield")
	check(is_equal_approx(GameState.buff_effect_total("damageToManaPct"), 0.47),
		"5 阶盾的转嫁比例应为 0.47，实际 %.2f" % GameState.buff_effect_total("damageToManaPct"))
	check(player.apply_damage(1000) == 530, "5 阶盾下 1000 点伤害应扣 530 血")
	player.queue_free()

## 武士路径逐位不变：没有任何 buff 提供 damageToManaPct ⇒ 全额扣血、蓝不动。
func _test_warrior_unchanged() -> void:
	GameState.reset_to_defaults("warrior")
	GameState.current_map = "wild_trial"
	GameState.player.level = 60
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(4200, 4200)
	GameState.player.hp = 100000
	GameState.start_buff("battle_focus")
	var mp_before := int(GameState.player.mp)
	var taken := player.apply_damage(1000)
	check(taken == 1000, "武士 1000 点伤害应全额扣血，实际 %d" % taken)
	check(int(GameState.player.mp) == mp_before, "武士受击不得扣蓝")
	player.queue_free()
