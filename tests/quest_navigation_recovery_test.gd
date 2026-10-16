extends Node
## 任务跨图导航回归：复现槽 1 在断流渠岸靠近东南边界时，点击 C3Q05 首领链接。
## 仅在隔离项目使用固定位置和临时任务状态，不读取或写入真实存档。

const START := Vector2(1908.2567, -4360.1387)

## 从槽 1 的位置出发，确认重新点击同一任务目标会重新发出移动指令。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "c3_map01"
	GameState.unlocks["c3_access_02"] = true
	GameState.save_pos = START
	GameState.has_save_pos = true
	var world := preload("res://scenes/Game.tscn").instantiate()
	add_child(world)
	var player := world.get_node("Entities/Player") as PlayerCharacter
	var goal := Iso.grid_to_world(Vector2i(184, 54))
	var path := (world.get_node("Ground") as IsoGround).route(player.global_position, goal)
	if path.is_empty():
		push_error("[QuestNavigationRecoveryTest] 存档位置到任务出口无路线")
		get_tree().quit(1)
		return
	var request := MapService.start_quest_link_navigation("monster", "c3_boss01", ["c3_map02"])
	if not bool(request.get("ok", false)):
		push_error("[QuestNavigationRecoveryTest] 任务目标道路不可用")
		get_tree().quit(1)
		return
	world._tick_quest_navigation()
	if not player.map_move_active:
		push_error("[QuestNavigationRecoveryTest] 首次点击未发出移动指令")
		get_tree().quit(1)
		return
	# 打开普通面板会暂停移动，关闭后应继续导航，不应把暂停误报为道路失败。
	GameState.panel_open = true
	player.map_move_active = false
	world._tick_quest_navigation()
	GameState.panel_open = false
	world._tick_quest_navigation()
	if not player.map_move_active or MapService.quest_nav_target.is_empty():
		push_error("[QuestNavigationRecoveryTest] 面板关闭后未恢复任务导航")
		get_tree().quit(1)
		return
	# 先前行走因战斗/手动输入等原因结束，同一地图中再次点击任务链接。
	player.map_move_active = false
	MapService.clear_quest_navigation()
	request = MapService.start_quest_link_navigation("monster", "c3_boss01", ["c3_map02"])
	if not bool(request.get("ok", false)):
		push_error("[QuestNavigationRecoveryTest] 重试时任务目标道路不可用")
		get_tree().quit(1)
		return
	world._tick_quest_navigation()
	if not player.map_move_active or MapService.quest_nav_target.is_empty():
		push_error("[QuestNavigationRecoveryTest] 重新点击后没有重新发出移动指令")
		get_tree().quit(1)
		return
	print("[QuestNavigationRecoveryTest] 全部通过 ✅")
	get_tree().quit(0)
