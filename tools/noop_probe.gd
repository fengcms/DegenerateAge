extends Node
## 必须通过tools/run_isolated_probe.py启动；隔离由项目身份强制检查，不能只依赖HOME约定。
## 对照探针：只加载世界 + 打开面板，不重铸。用于判定崩溃是否需要重铸触发。
func _ready() -> void:
	if not DiagnosticProbeGuard.require_isolated(self):
		return
	var mode := OS.get_cmdline_user_args()
	print("[Noop] args=", mode)
	SaveManager.active_slot = -1
	GameState.menu_mode = "world"
	var res: Dictionary = SaveManager.load_into_game(1)
	print("[Noop] load ok=%s" % str(res.get("ok", false)))
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = packed.instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = main
	await get_tree().process_frame
	await get_tree().process_frame
	print("[Noop] 世界已建，viewport=%s window=%s" % [
		str(get_viewport().get_visible_rect().size), str(DisplayServer.window_get_size())])
	var open_panel := "--panel" in mode
	if open_panel:
		var panel: Node = main.get_node_or_null("UI/ReforgePanel")
		if panel != null:
			panel.set_open(true)
			await get_tree().process_frame
			var choices: Array = panel.get("_choices")
			if choices.size() > 0:
				panel.select_choice(0)
			print("[Noop] 面板已打开，候选 %d 条" % choices.size())
	for i in range(40):
		await get_tree().create_timer(0.4).timeout
		if i % 10 == 0:
			print("[Noop] 存活 %.1fs frame=%d" % [i * 0.4, Engine.get_process_frames()])
	print("[Noop] === 未崩溃 ===")
	get_tree().quit(0)
