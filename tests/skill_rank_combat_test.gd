extends Node
## 技能升阶的真实战斗回归：同一个玩家施放入口、自动选技与 Buff 快照必须读取升级值。
## 使用无防御假敌人降低随机性，不写正式玩家存档。

class DummyEnemy extends Node2D:
	var is_dead := false
	var damage := 0
	var hit_count := 0

	## 注册到战斗目标组，供真实范围选择入口发现。
	func _ready() -> void:
		add_to_group("enemies")

	## 提供零防御，使前后伤害差只来自技能阶数。
	func get_defense() -> float:
		return 0.0

	## 关闭闪避，避免随机 Miss 干扰数值比较。
	func get_dodge() -> float:
		return 0.0

	## 收集真实战斗结算，不让测试目标死亡。
	func take_hit(result: Dictionary, _from: Node = null) -> void:
		hit_count += 1
		damage += int(result.get("damage", 0))

var _failures: Array[String] = []

## 验证升阶改变实际伤害、AI 估值，并确保持续 Buff 只在下一次施放取新效果。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "wild_trial"
	GameState.player.level = 80
	GameState.player.attack = 200
	GameState.player.criticalChance = 0.0
	GameState.player.mp = 1000
	GameState.gold = 1000000
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(2000, 2000)
	var enemy := DummyEnemy.new()
	add_child(enemy)
	enemy.global_position = player.global_position + Vector2(60, 0)
	_check(player.cast_skill("earth_cleave", enemy), "1 阶裂地斩能从真实入口施放")
	var base_damage := enemy.damage
	player.skill_cooldowns.clear()
	player._attack_cd = 0.0
	for _rank in range(2, 6):
		_check(bool(GameState.buy_skill_rank("earth_cleave").get("ok", false)), "裂地斩可连续购买至 5 阶")
	_check(player.cast_skill("earth_cleave", enemy), "升至 5 阶后仍可从同一入口施放")
	var upgraded_damage := enemy.damage - base_damage
	_check(upgraded_damage > base_damage and upgraded_damage == int(floorf(float(GameState.total_attack()) * 1.4 * 1.12)),
		"实际伤害而非仅面板描述提高：原 %d、升级后 %d" % [base_damage, upgraded_damage])
	_check(GameState.skill_rank("earth_cleave") == 5 and String(GameState.buy_skill_rank("earth_cleave").get("reason", "")) == "max",
		"升满后不能继续扣金币")
	_check(GameState.start_buff("battle_focus"), "1 阶战意觉醒能启动")
	_check(is_equal_approx(GameState.buff_effect_total("attackPct"), 0.2), "施放时攻击效果为 1 阶值")
	for _rank in range(2, 6):
		_check(bool(GameState.buy_skill_rank("battle_focus").get("ok", false)), "战意觉醒可连续购买至 5 阶")
	_check(is_equal_approx(GameState.buff_effect_total("attackPct"), 0.2)
		and is_equal_approx(GameState.buff_effect_total("attackSpeedPct"), 0.15),
		"持续中的 Buff 保留施放时效果快照")
	GameState.tick_buffs(8.0)
	_check(GameState.start_buff("battle_focus") and is_equal_approx(GameState.buff_effect_total("attackPct"), 0.26)
		and is_equal_approx(GameState.buff_effect_total("attackSpeedPct"), 0.19),
		"下一次施放使用 5 阶增益")
	var pilot := AutoBattle.new()
	player.add_child(pilot)
	pilot.set_physics_process(false)
	var another := DummyEnemy.new()
	add_child(another)
	another.global_position = player.global_position + Vector2(-40, 0)
	player.skill_cooldowns.clear()
	player._attack_cd = 0.0
	for _rank in range(2, 6):
		_check(bool(GameState.buy_skill_rank("spirit_storm").get("ok", false)), "灵刃风暴可升至 5 阶")
	var chosen := pilot._best_area_skill(enemy)
	_check(String(chosen.get("id", "")) == "spirit_storm"
		and is_equal_approx(float(chosen.get("coefficient", 0.0)), 1.12)
		and is_equal_approx(AutoBattle.skill_value(chosen), 3.36),
		"自动战斗按 5 阶真实三段系数评分")
	if _failures.is_empty():
		print("SkillRankCombatTest: PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)

## 汇总战斗断言失败，便于同轮检查施放和 AI 两条链路。
func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
