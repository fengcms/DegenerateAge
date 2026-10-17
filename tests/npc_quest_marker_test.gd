extends Node
## NPC 可接任务标记的世界装配回归：检查发布人 ID、状态事件、容量和标记点击命中。
## 使用隔离项目与临时 GameState，不写真实存档；只验证逻辑和几何，不代替窗口视觉验收。

var failures: Array[String] = []

## 以正式营地 NPC 和任务数据驱动整条事件链，检查标记从出现到消失再出现。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "camp"
	var world := (load("res://scenes/Game.tscn") as PackedScene).instantiate()
	add_child(world)
	await get_tree().process_frame
	var elder := _find_npc(world, "elder")
	var merchant: Npc = null
	for child in world.get_node("Npcs").get_children():
		var npc := child as Npc
		if npc != null and npc.shop_id == "peddler_camp":
			merchant = npc
			break
	check(elder != null and merchant != null, "营地生成任务发布人和普通货郎")
	if elder != null and merchant != null:
		var marker := elder.get_node("QuestMarker") as Label
		check(marker.visible and not (merchant.get_node("QuestMarker") as Label).visible,
			"新角色只在可接发布人头顶显示标记")
		var marker_center := marker.get_global_transform_with_canvas() * (marker.size * 0.5)
		check(elder.contains_screen_point(marker_center), "点击标记会命中该 NPC")
		var quest_panel := (load("res://scenes/ui/QuestPanel.tscn") as PackedScene).instantiate()
		add_child(quest_panel)
		check(world._interact_with(elder) and String(quest_panel.get("_current_npc_id")) == "elder",
			"点击任务 NPC 时以稳定 ID 打开其任务列表")
		quest_panel.queue_free()
		await get_tree().process_frame
		merchant.npc_name = elder.npc_name
		EventBus.quest_state_changed.emit()
		check(not (merchant.get_node("QuestMarker") as Label).visible, "同名 NPC 不继承发布人标记")
		check(Quest.accept("S001", "elder").ok and Quest.accept("S002", "elder").ok
			and Quest.accept("Q001", "elder").ok, "接取营地初始可接任务")
		check(not marker.visible, "所有可接任务已接取后标记立即隐藏")
		check(Quest.abandon("S001").ok and marker.visible, "支线放弃后标记立即重新显示")
		check(Quest.accept("S001", "elder").ok and not marker.visible, "重接后标记立即隐藏")
		check(Quest.deliver("Q001", "elder").ok and marker.visible, "交付后下一主线解锁并显示标记")
		GameState.quest_states["Q002"] = {"state": Quest.STATE_ACTIVE, "progress": 0}
		EventBus.quest_state_changed.emit()
		check(not marker.visible, "进行中任务不显示可接标记")
		GameState.quest_states.erase("Q002")
		EventBus.quest_state_changed.emit()
		check(marker.visible, "状态恢复后可接标记重现")
	world.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()
	GameState.current_map = "c2_well_town"
	GameState.unlocks["chapter2"] = true
	GameState.quest_states["C2Q03"] = {"state": Quest.STATE_REWARDED, "progress": 1}
	var chapter_two := (load("res://scenes/Game.tscn") as PackedScene).instantiate()
	add_child(chapter_two)
	await get_tree().process_frame
	var lu_heng := _find_npc(chapter_two, "c2_lu_heng")
	check(lu_heng != null and (lu_heng.get_node("QuestMarker") as Label).visible,
		"切图装配时第二章发布人按任务状态初始化标记")
	chapter_two.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("NpcQuestMarkerTest: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)

## 按配置 ID 查找当前世界 NPC，避免显示名重复导致测试误判。
func _find_npc(world: Node, npc_id: String) -> Npc:
	for child in world.get_node("Npcs").get_children():
		var npc := child as Npc
		if npc != null and npc.npc_id == npc_id:
			return npc
	return null

## 收集断言，任一标记状态不符即使隔离测试失败。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
