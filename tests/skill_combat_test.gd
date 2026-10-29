extends Node
## 主动技能的真实玩家施放回归；使用假敌人记录单次受击，不写角色存档。

class TestEnemy extends Node2D:
	var is_dead := false
	var hits := 0
	var damage := 0
	func _ready() -> void:
		add_to_group("enemies")
	func get_defense() -> float:
		return 0.0
	func get_dodge() -> float:
		return 0.0
	func take_hit(result: Dictionary, _from: Node = null) -> void:
		hits += 1
		damage += int(result.get("damage", 0))

var _failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)

## 工程 107：武士耗蓝改成「按当前蓝池百分比」，CD 也一起调过。任何写死的扣蓝量/冷却值
## 都会随等级与平衡调整漂移 —— 统一从这里取单次口径。
## ⚠ 这两条助手只提供**单位**：每条用例的真正判据是「结算了几次」「在不在范围内」，
## 而不是「这个数是多少」。单纯把 60 换成 `_cost(...)` 会让「耗蓝被改成 0」也变绿，
## 所以每处都另配一条与数值无关的绝对断言（> 0 / 严格大小关系）。
func _cost(skill_id: String) -> int:
	var skill: Variant = DataLoader.get_entry("skills", skill_id)
	return GameState.skill_mana_cost(skill as Dictionary) if skill is Dictionary else 0

func _cd(skill_id: String) -> float:
	var skill: Variant = DataLoader.get_entry("skills", skill_id)
	return float((skill as Dictionary).get("cooldown", 0.0)) if skill is Dictionary else 0.0

## 蓝池拉满：等价于旧代码里的「mp = 100 表示充足」，但不随等级变化而失效。
func _fill_mp() -> void:
	GameState.player.mp = GameState.max_mp()

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "wild_trial"
	GameState.player.level = 5
	_fill_mp()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(1500, 1500)
	var near := _enemy(player.global_position + Vector2(90, 0))
	var upper := _enemy(player.global_position + Vector2(80, -40))
	var lower := _enemy(player.global_position + Vector2(80, 40))
	var fourth := _enemy(player.global_position + Vector2(110, 0))
	var behind := _enemy(player.global_position + Vector2(-65, 0))
	var cleave: Dictionary = DataLoader.get_entry("skills", "earth_cleave")
	_check(player.skill_targets(cleave, near).size() == 3, "扇形只取最近三个目标")
	_check(player.skill_targets(cleave, fourth).has(fourth), "扇形多目标上限时保留锁定目标")
	var cleave_cost := _cost("earth_cleave")
	_check(cleave_cost > 0, "裂地斩耗蓝应大于 0（改成 0 时下面的「扣一次蓝」会变成假绿）")
	var before := int(GameState.player.mp)
	_check(player.cast_skill("earth_cleave", near), "Lv5 可施放裂地斩")
	_check(int(GameState.player.mp) == before - cleave_cost and is_equal_approx(player.skill_cooldown("earth_cleave"), _cd("earth_cleave")),
		"耗蓝与冷却只结算一次（扣 %d，冷却 %.1f）" % [cleave_cost, _cd("earth_cleave")])
	_check(near.hits == 1 and upper.hits == 1 and lower.hits == 1 and fourth.hits == 0 and behind.hits == 0,
		"每个命中目标只受击一次，超额和背后不受击")
	_check(not player.cast_skill("earth_cleave", near) and int(GameState.player.mp) == before - cleave_cost,
		"冷却中不重复扣蓝")
	player.skill_cooldowns.clear()
	player._attack_cd = 0.0
	GameState.player.mp = cleave_cost - 1
	var short_mp := int(GameState.player.mp)
	_check(not player.cast_skill("earth_cleave", near) and int(GameState.player.mp) == short_mp, "蓝量不足不施放")
	_fill_mp()
	GameState.player.level = 4
	_check(not player.cast_skill("earth_cleave", near) and player.skill_cooldown("earth_cleave") == 0.0,
		"等级不足不进入冷却")
	GameState.player.level = 5
	near.is_dead = true
	var full_mp := int(GameState.player.mp)
	_check(not player.cast_skill("earth_cleave", near) and int(GameState.player.mp) == full_mp,
		"目标失效不扣蓝")
	near.is_dead = false
	GameState.player.level = 10
	_fill_mp()
	player._attack_cd = 0.0
	var whirl_cost := _cost("whirlwind")
	_check(whirl_cost > cleave_cost, "旋风斩应比裂地斩更贵（本就是更高的蓝耗档）")
	var before_whirl := int(GameState.player.mp)
	_check(player.cast_skill("whirlwind"), "Lv10 无锁定目标可施放旋风斩")
	_check(int(GameState.player.mp) == before_whirl - whirl_cost and is_equal_approx(player.skill_cooldown("whirlwind"), _cd("whirlwind")),
		"旋风斩耗蓝与冷却正确（扣 %d，冷却 %.1f）" % [whirl_cost, _cd("whirlwind")])
	_check(near.hits == 2 and upper.hits == 2 and lower.hits == 2 and fourth.hits == 1 and behind.hits == 1,
		"圆形范围内每只怪各受击一次")
	_check(not player.cast_skill("whirlwind") and int(GameState.player.mp) == before_whirl - whirl_cost,
		"旋风斩冷却阻止重复施放")
	player.skill_cooldowns.clear()
	player._attack_cd = 0.0
	var original_position := player.global_position
	var original_fourth := fourth.global_position
	fourth.global_position = original_position + Vector2(400, 0)
	player.select_target(fourth)
	var before_chase := int(GameState.player.mp)
	_check(player.request_skill("whirlwind"), "远处锁定目标的旋风斩接受追击指令")
	_check(player.manual_attack_active and int(GameState.player.mp) == before_chase
		and player.skill_cooldown("whirlwind") == 0.0, "追击开始时不提前耗蓝或进入冷却")
	_check(not player.cast_skill("whirlwind", fourth) and int(GameState.player.mp) == before_chase,
		"身边有其他怪时也不能提前命中远处锁定目标")
	_check(player._manual_attack_direction(0.016) != Vector2.ZERO and fourth.hits == 1,
		"未到技能范围继续接近目标")
	player.global_position = fourth.global_position - Vector2(80, 0)
	player._manual_attack_direction(0.016)
	_check(fourth.hits == 2 and int(GameState.player.mp) == before_chase - whirl_cost
		and not player.manual_attack_active, "进入范围后只施放一次并命中锁定目标")
	player.global_position = original_position
	fourth.global_position = original_fourth
	player.select_target(null)
	player.skill_cooldowns.clear()
	player._attack_cd = 0.0
	var pilot := AutoBattle.new()
	player.add_child(pilot)
	pilot.set_physics_process(false)
	_check(String(pilot._best_area_skill(near).get("id", "")) == "whirlwind",
		"自动战斗按实际圆形命中数优先旋风斩")
	# 「够裂地斩、不够旋风斩」这两个值必须**在当前等级重算**：百分比耗蓝随蓝池走，
	# 复用等级 5 算出的值会在等级 10 变成「两个都放不出」，用例名还叫「改选裂地斩」。
	var now_cleave := _cost("earth_cleave")
	var now_whirl := _cost("whirlwind")
	_check(now_cleave < now_whirl, "构造前提：同等级下裂地斩比旋风斩便宜")
	GameState.player.mp = now_cleave
	_check(String(pilot._best_area_skill(near).get("id", "")) == "earth_cleave",
		"蓝量不足时改选可用的裂地斩")
	_fill_mp()
	GameState.player.level = 4
	_check(pilot._best_area_skill(near).is_empty(), "未解锁时自动战斗回退普攻")
	GameState.player.level = 10
	_fill_mp()
	player.global_position += Vector2(50, 0)
	pilot._target = near
	var before_auto := int(GameState.player.mp)
	pilot._tick(0.016)
	_check(int(GameState.player.mp) == before_auto - whirl_cost and player.skill_cooldown("whirlwind") > 0.0,
		"自动战斗通过玩家统一入口施放范围技")
	var next_map_player := PlayerCharacter.new()
	add_child(next_map_player)
	next_map_player.set_physics_process(false)
	_check(next_map_player.skill_cooldown("whirlwind") > 0.0, "重建地图角色后冷却继续")
	GameState.player.level = 15
	_fill_mp()
	player._attack_cd = 0.0
	var focus_cost := _cost("battle_focus")
	_check(focus_cost > 0, "战意觉醒耗蓝应大于 0")
	pilot._target = near
	var before_focus := int(GameState.player.mp)
	_check(pilot._try_battle_focus(near), "自动战斗在有效近战目标前施放增益")
	var after_focus := int(GameState.player.mp)
	_check(GameState.buff_remaining("battle_focus") > 0.0 and after_focus == before_focus - focus_cost,
		"自动施放复用耗蓝和运行态（扣 %d）" % focus_cost)
	_check(not pilot._try_battle_focus(near) and int(GameState.player.mp) == after_focus, "持续期间不叠加")
	GameState.clear_buffs()
	player.skill_cooldowns.clear()
	_check(not pilot._try_battle_focus(null), "无目标不空放")
	near.global_position = player.global_position + Vector2(player.melee_range_px() + 100.0, 0)
	_check(not pilot._try_battle_focus(near), "追路期间不提前施放")
	near.global_position = player.global_position + Vector2(30, 0)
	GameState.player.mp = focus_cost - 1
	_check(not pilot._try_battle_focus(near), "缺蓝时继续保留普通攻击")
	_fill_mp()
	pilot._target = near
	pilot._tick(0.016)
	_check(GameState.buff_remaining("battle_focus") > 0.0 and is_equal_approx(player.skill_cooldown("battle_focus"), _cd("battle_focus")),
		"自动战斗实际决策优先施放增益（冷却 %.1f）" % _cd("battle_focus"))
	if _failures.is_empty():
		print("[SkillCombatTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)

func _enemy(at: Vector2) -> TestEnemy:
	var enemy := TestEnemy.new()
	add_child(enemy)
	enemy.global_position = at
	return enemy
