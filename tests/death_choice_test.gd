extends Node
## 死亡选择隔离回归；验证暂停、复活卷、跨图回所属城镇及自动战斗边界，不写真实槽位。
## 另含「自动原地复活」段：设置项开启且背包有复活卷时，死亡不弹面板、原地复活并恢复挂机。

var failures: Array[String] = []

## 记录一条断言结果；失败项在退出前统一输出，避免首个失败就中断后续校验。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

## 依次执行自动复活段与手动复活段；全部通过则以退出码 0 结束，否则输出失败项并以 1 退出。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _check_auto_revive()
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

## 自动原地复活段：先于手动复活断言执行，结束时清理节点并把状态交回 `_ready()` 的
## `reset_to_defaults()`，避免残留的开关 / 暂停 / 背包数据影响后续断言。
func _check_auto_revive() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "camp"
	GameState.settings["autoReviveOnDeath"] = true
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	var panel: Control = load("res://scripts/ui/death_panel.gd").new()
	add_child(panel)
	GameState.inventory[0] = {"kind": "misc", "itemId": "misc_revive_scroll", "count": 2}
	GameState.set_auto_battle(true)
	GameState.damage_player(99999)
	player._begin_death()
	await get_tree().process_frame
	check(not player.is_dead and not panel.visible and not get_tree().paused,
		"自动复活：不弹面板、不暂停直接站起")
	check(GameState.auto_battle_on, "自动复活：恢复死亡前的自动战斗")
	check(int(GameState.inventory[0].get("count", 0)) == 1, "自动复活：只消耗一张复活卷")
	# 死亡前未挂机 → 只自动复活，不代开自动战斗。
	GameState.set_auto_battle(false)
	GameState.damage_player(99999)
	player._begin_death()
	await get_tree().process_frame
	check(not player.is_dead and not panel.visible and not GameState.auto_battle_on,
		"自动复活：未挂机死亡时不代开自动战斗")
	check(GameState.inventory[0] == null, "自动复活：最后一张复活卷就地扣除")
	# 复活卷耗尽 → 回落手动死亡面板。
	GameState.damage_player(99999)
	player._begin_death()
	await get_tree().process_frame
	check(player.is_dead and panel.visible and get_tree().paused, "自动复活：无复活卷回落手动选择")
	panel._close()
	player.queue_free()
	panel.queue_free()
	await get_tree().process_frame
