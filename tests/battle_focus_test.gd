extends Node
## 战意觉醒的真实运行态和玩家属性边界；不写存档。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "wild_trial"
	GameState.player.level = 15
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	var base_attack := GameState.total_attack()
	var base_interval := player.effective_attack_interval()
	check(GameState.start_buff("battle_focus"), "增益可启动")
	check(not GameState.start_buff("battle_focus"), "增益不可叠层")
	check(is_equal_approx(player.effective_attack_power(), float(base_attack) * 1.2), "攻击力提升20%")
	check(is_equal_approx(player.effective_attack_interval(), base_interval / 1.15), "攻击间隔缩短")
	check(GameState.total_attack() == base_attack and is_equal_approx(float(GameState.player.attack), 12.0), "基础攻击未改写")
	GameState.current_map = "camp"
	check(GameState.buff_remaining("battle_focus") > 0.0, "切图保留增益")
	GameState.tick_buffs(8.0)
	check(GameState.buff_remaining("battle_focus") == 0.0, "8秒后失效")
	check(is_equal_approx(player.effective_attack_power(), float(base_attack)) and is_equal_approx(player.effective_attack_interval(), base_interval), "失效后恢复基值")
	GameState.start_buff("battle_focus")
	player.set_sitting(true)
	check(GameState.buff_remaining("battle_focus") == 0.0, "打坐清除增益")
	player.set_sitting(false)
	GameState.start_buff("battle_focus")
	player._begin_death()
	check(GameState.buff_remaining("battle_focus") == 0.0, "死亡清除增益")
	GameState.start_buff("battle_focus")
	GameState.reset_to_defaults()
	check(GameState.buff_remaining("battle_focus") == 0.0, "新游戏清除增益")
	if failures.is_empty():
		print("BattleFocusTest: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
