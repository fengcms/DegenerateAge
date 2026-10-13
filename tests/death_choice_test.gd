extends Node
## 死亡选择不写真实槽位；验证暂停、复活卷和自动战斗边界。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.reset_to_defaults()
	GameState.current_map = "camp"
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	var panel: Control = load("res://scripts/ui/death_panel.gd").new()
	add_child(panel)
	GameState.set_auto_battle(true)
	GameState.damage_player(99999)
	player._begin_death()
	await get_tree().process_frame
	check(player.is_dead and get_tree().paused and panel.visible, "死亡后停止行动并显示选择")
	check(not GameState.auto_battle_on, "死亡关闭自动战斗")
	player._physics_process(5.0)
	check(player.is_dead, "等待选择时不会自动复活")
	check(not panel.revive_here() and player.is_dead, "无复活卷不可原地复活")
	GameState.inventory[0] = {"kind": "misc", "itemId": "misc_revive_scroll", "count": 1}
	check(panel.revive_here(), "消耗复活卷原地复活")
	check(GameState.inventory[0] == null and not player.is_dead and not get_tree().paused,
		"复活卷扣一张且世界恢复")
	check(int(GameState.player.hp) == GameState.max_hp() and int(GameState.player.mp) == GameState.max_mp(),
		"复活恢复全部血蓝")
	GameState.damage_player(99999)
	player._begin_death()
	await get_tree().process_frame
	check(panel.revive_camp(), "营地死亡可免费回安全区")
	check(not player.is_dead and not get_tree().paused and GameState.inventory[0] == null,
		"免费复活不产生物品")
	if failures.is_empty():
		print("DeathChoiceTest: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
