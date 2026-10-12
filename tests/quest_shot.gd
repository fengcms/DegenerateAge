extends Node
## 任务系统视觉验收工具（开发期，R11）：
## ① 构造任务局面（交付主线 + 接取并推进 + 接支线）→ 打开**任务面板**截图；
## ② 关闭面板、让一条支线进入「可交付」→ 截 **HUD 任务列表**（小地图下方，9.1 第 6 条），
##    目视确认不与 MapPanel / TargetPanel 重叠（R-f）。
## 运行：GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##       "$GODOT" --path . res://tests/QuestShot.tscn

func _ready() -> void:
	GameState.reset_to_defaults()
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(20):
		await get_tree().process_frame

	# 造局面：Q001 交付 → Q002 接取并推进 3/5；再接一条支线
	Quest.accept("Q001")
	Quest.deliver("Q001")
	Quest.accept("Q002")
	for _i in range(3):
		Quest.on_event("monster_died", "wolf_corrupted")
	Quest.accept("S001")

	var panel: Control = main.get_node("UI/QuestPanel")

	# ① 任务面板
	EventBus.quest_panel_requested.emit("长老")
	for _i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/degenerateage_quest_panel.png")
	print("[QuestShot] ① 任务面板 → /tmp/degenerateage_quest_panel.png（任务行数=%d）" % _panel_row_count(panel))

	# ② HUD 任务列表（让 S001 打满 → completed，验证「⚑ 可交付」高亮）
	panel.set_open(false)
	await get_tree().process_frame
	for _i in range(3):
		Quest.on_event("monster_died", "shellback_bug")
	for _i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img2: Image = get_viewport().get_texture().get_image()
	img2.save_png("/tmp/degenerateage_quest_hud.png")
	var hud = main.get_node("UI/Hud")
	var list = hud.get_node_or_null("QuestTracker/Margin/Root/QuestList")
	var tracker = hud.get_node_or_null("QuestTracker")
	print("[QuestShot] ② HUD 任务列表 → /tmp/degenerateage_quest_hud.png（行数=%d；tracker 可见=%s）" % [
		list.get_child_count() if list != null else -1,
		str(tracker.visible) if tracker != null else "?"])

	get_tree().quit()

## 面板内的任务行数（ScrollContainer 内的 VBox 子节点数）。
func _panel_row_count(panel: Control) -> int:
	var sc: Array = panel.find_children("*", "ScrollContainer", true, false)
	if sc.is_empty():
		return -1
	var vbox = (sc[0] as Node).get_child(0)
	return vbox.get_child_count() if vbox != null else -1
