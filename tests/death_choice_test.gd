extends Node
## 死亡选择隔离回归；验证暂停、复活卷、跨图回所属城镇及自动战斗边界，不写真实槽位。

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
	check(MapService.safe_town_for("wild_trial") == "camp", "第一章野外仍返回幸存者营地")
	check(MapService.safe_town_for("c2_pipe_slope").is_empty(), "未解锁城镇不可作为复活目的地")
	GameState.unlocks["chapter2"] = true
	check(MapService.safe_town_for("c2_pipe_slope") == "c2_well_town", "第二章野外选择沉井镇")
	check(MapService.safe_town_for("missing_hub_map").is_empty(), "目的地缺失时不回退到幸存者营地")
	player.queue_free()
	panel.queue_free()
	await get_tree().process_frame
	GameState.current_map = "c2_pipe_slope"
	GameState.menu_mode = "world"
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await get_tree().process_frame
	var town_player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	var town_panel := main.get_node("UI/DeathPanel") as Control
	GameState.damage_player(99999)
	town_player._begin_death()
	town_panel._show_after_death()
	check(town_player.is_dead and get_tree().paused and town_panel.visible,
		"第二章野外死亡显示复活选择")
	check(town_panel.revive_camp(), "第二章野外免费复活成功")
	check(GameState.current_map == "c2_well_town" and GameState.save_pos.distance_to(MapService.entry_point("c2_well_town")) < 1.0,
		"免费复活目的地及落点与回城卷相同")
	for _i in range(5):
		await get_tree().process_frame
	var revived_player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	check(revived_player != null and not revived_player.is_dead and not get_tree().paused,
		"切图完成后角色存活且世界恢复")
	check(MapService.pending_travel.is_empty(), "到达后清理切图事务")
	if failures.is_empty():
		print("DeathChoiceTest: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
