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
	# 工程 107：战意觉醒从「攻击 +20% / 攻速 +15%」改成「减伤 20% / 攻速 +15%」。
	# 这两条必须分开断 —— 只把 1.2 改成 1.0 会让「减伤有没有生效」完全没人看守。
	check(is_equal_approx(player.effective_attack_power(), float(base_attack)),
		"战意觉醒不再提升攻击力（107 起改为减伤，攻击面板必须逐位不变）")
	check(is_equal_approx(GameState.buff_effect_total("damageReducePct"), 0.2),
		"战意觉醒 1 阶应提供 20%% 减伤（实际 %.2f）" % GameState.buff_effect_total("damageReducePct"))
	check(is_equal_approx(player.effective_attack_interval(), base_interval / 1.15), "攻击间隔缩短")
	check(GameState.total_attack() == base_attack and is_equal_approx(float(GameState.player.attack), 12.0), "基础攻击未改写")
	GameState.current_map = "camp"
	check(GameState.buff_remaining("battle_focus") > 0.0, "切图保留增益")
	GameState.tick_buffs(8.0)
	check(GameState.buff_remaining("battle_focus") == 0.0, "8秒后失效")
	check(is_equal_approx(player.effective_attack_power(), float(base_attack)) and is_equal_approx(player.effective_attack_interval(), base_interval), "失效后恢复基值")
	check(HotbarConfig.valid_entry({"kind": "skill", "id": "battle_focus"}), "技能可配置到快捷栏")
	GameState.player.level = 14
	GameState.player.mp = 100
	check(not player.request_skill("battle_focus") and int(GameState.player.mp) == 100, "未解锁不耗蓝")
	GameState.player.level = 15
	# 工程 107：耗蓝改成按蓝池百分比，蓝量与冷却都从数据取 —— 写死 29 / 70 / 30 会在
	# 任何一次调价后误红，而这几条守的是「缺蓝挡住 / 只扣一次 / 不叠层」。
	var focus_cost := GameState.skill_mana_cost(SkillProgression.current("battle_focus"))
	var focus_cd := float((DataLoader.get_entry("skills", "battle_focus") as Dictionary).get("cooldown", 0.0))
	check(focus_cost > 0, "战意觉醒耗蓝应大于 0（实际 %d）" % focus_cost)
	GameState.player.mp = focus_cost - 1
	check(not player.request_skill("battle_focus") and player.skill_cooldown("battle_focus") == 0.0, "缺蓝不进冷却")
	GameState.player.mp = GameState.max_mp()
	var full_mp := int(GameState.player.mp)
	check(player.request_skill("battle_focus"), "安全区无目标可手动施放")
	check(int(GameState.player.mp) == full_mp - focus_cost and is_equal_approx(player.skill_cooldown("battle_focus"), focus_cd),
		"手动施放耗蓝与冷却（扣 %d，冷却 %.1f）" % [focus_cost, focus_cd])
	var after_cast := int(GameState.player.mp)
	check(not player.request_skill("battle_focus") and int(GameState.player.mp) == after_cast, "冷却时不重复扣蓝")
	player.skill_cooldowns.clear()
	check(not player.request_skill("battle_focus") and int(GameState.player.mp) == after_cast, "增益生效时不可叠层")
	GameState.clear_buffs()
	GameState.start_buff("battle_focus")
	player.set_sitting(true)
	check(GameState.buff_remaining("battle_focus") == 0.0, "打坐清除增益")
	player.set_sitting(false)
	GameState.start_buff("battle_focus")
	player._begin_death()
	check(GameState.buff_remaining("battle_focus") == 0.0, "死亡清除增益")
	GameState.start_buff("battle_focus")
	var snapshot := SaveManager._collect()
	check(not snapshot.has("activeBuffs"), "增益不写入存档")
	SaveManager.apply_to_game_state(snapshot)
	check(GameState.buff_remaining("battle_focus") == 0.0, "读档清除增益")
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
