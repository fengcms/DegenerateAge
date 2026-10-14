extends Node
## 回城卷快捷格实际切图、失败不耗卷和同一使用入口。不写玩家存档。

var _errors: Array[String] = []

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.menu_mode = "world"
	GameState.current_map = "wild_trial"
	GameState.inventory[0] = {"kind": "misc", "itemId": "misc_town_scroll", "count": 2}
	GameState.set_hotbar_entry(3, {"kind": "item", "id": "misc_town_scroll"})
	await get_tree().process_frame
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await get_tree().process_frame
	_check(GameState.current_map == "wild_trial", "从野外开始")
	GameState.player.hp = 0
	_check(not GameState.use_item(0).ok and GameState.inventory[0].count == 2,
		"角色倒下时拒绝使用且不耗卷")
	GameState.player.hp = GameState.max_hp()
	main.get_node("UI/Hud")._activate_hotbar(3)
	for _i in range(5):
		await get_tree().process_frame
	_check(GameState.current_map == "camp" and GameState.inventory[0].count == 1,
		"快捷键回营地且只消耗一张")
	_check(GameState.hotbar[3].id == "misc_town_scroll", "切图保留快捷栏配置")
	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	_check(player != null and player.global_position.distance_to(MapService.entry_point("camp")) < 1.0,
		"玩家落在营地中心")
	_check(not GameState.use_item(0).ok and GameState.inventory[0].count == 1,
		"已在营地时背包使用不耗卷")
	GameState.unlocks["chapter2"] = true
	GameState.current_map = "c2_well_town"
	_check(not TravelItem.use_town_scroll(0, false).ok and GameState.inventory[0].count == 1,
		"第二章城镇内使用不耗卷")
	GameState.current_map = "missing_hub_map"
	_check(not TravelItem.use_town_scroll(0, false).ok and GameState.inventory[0].count == 1,
		"目的城镇缺失时不耗卷")
	GameState.current_map = "c2_pipe_slope"
	_check(TravelItem.use_town_scroll(0, false).ok and GameState.inventory[0] == null,
		"最后一张卷轴使用后移除背包格")
	_check(GameState.current_map == "c2_well_town" and GameState.save_pos.distance_to(MapService.entry_point("c2_well_town")) < 1.0,
		"第二章野外回到沉井镇安全落点")
	print("[TownScrollTest] ", "全部通过 ✅" if _errors.is_empty() else str(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_errors.append(message)
		push_error("[TownScrollTest] " + message)
