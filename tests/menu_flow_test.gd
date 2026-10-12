extends Node
## M4-7：真实主场景菜单流转。临时使用槽 3；测试结束还原原始文件。

var _failures: Array[String] = []
var _original_files: Dictionary = {}
var _original_active := -1

func _ready() -> void:
	_original_active = SaveManager.active_slot
	for path in _protected_paths():
		if FileAccess.file_exists(path):
			_original_files[path] = FileAccess.get_file_as_bytes(path)
	GameState.reset_to_defaults()
	GameState.menu_mode = "menu"
	SaveManager.active_slot = -1
	await get_tree().process_frame
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await get_tree().process_frame
	var menu: Control = main.get_node("UI/MenuPanel")
	_check(menu.visible and get_tree().paused, "启动进入主菜单并暂停世界")
	menu._open_new_slots()
	var saves: Control = main.get_node("UI/SavePanel")
	_check(saves.visible and saves._mode == "new" and not menu.visible, "新游戏进入三槽选择")
	saves._name_input.text = "测试守护者"
	saves._on_save_pressed(3)
	if saves._pending_overwrite == 3:
		_check(saves._overwrite_dialog.visible, "覆盖现有存档前需要确认")
		saves._on_overwrite_confirmed()
	for _i in range(5):
		await get_tree().process_frame
	main = get_tree().current_scene
	_check(GameState.menu_mode == "world" and not get_tree().paused, "新游戏进入可运行世界")
	_check(SaveManager.active_slot == 3 and bool(SaveManager.read_slot(3).get("ok", false)), "新档写入槽 3")
	_check(GameState.player.level == 1 and GameState.current_map == "camp" and GameState.player.name == "测试守护者",
		"新档保存角色名称并从营地开始")
	menu = main.get_node("UI/MenuPanel")
	menu.open_pause()
	_check(menu.visible and get_tree().paused, "暂停菜单停止世界")
	menu._open_settings()
	var settings: Control = main.get_node("UI/SettingsPanel")
	_check(settings.visible and not menu.visible, "暂停菜单进入设置")
	settings.set_open(false)
	await get_tree().process_frame
	_check(menu.visible and get_tree().paused, "关闭设置返回暂停菜单")
	menu.resume_game()
	_check(not get_tree().paused and not menu.visible, "继续游戏恢复模拟")
	menu._return_to_main()
	for _i in range(5):
		await get_tree().process_frame
	main = get_tree().current_scene
	menu = main.get_node("UI/MenuPanel")
	_check(menu.visible and get_tree().paused and GameState.menu_mode == "menu", "返回主菜单重新停止世界")
	_check(not menu._continue.disabled, "已有存档时继续游戏可用")
	menu._continue_game()
	for _i in range(5):
		await get_tree().process_frame
	_check(GameState.menu_mode == "world" and not get_tree().paused and SaveManager.active_slot == 3,
		"继续游戏读取上次活动槽")
	main = get_tree().current_scene
	main.get_node("UI/MenuPanel")._return_to_main()
	for _i in range(5):
		await get_tree().process_frame
	main = get_tree().current_scene
	menu = main.get_node("UI/MenuPanel")
	menu._open_load_slots()
	saves = main.get_node("UI/SavePanel")
	_check(saves._mode == "load" and not saves._cards[2].save.visible, "读取界面不提供覆盖保存")
	saves._on_load_pressed(3)
	for _i in range(5):
		await get_tree().process_frame
	_check(GameState.menu_mode == "world" and not get_tree().paused and SaveManager.active_slot == 3,
		"读档进入世界并恢复活动槽")
	_finish()

func _protected_paths() -> Array[String]:
	var paths: Array[String] = [SaveManager.LAST_SLOT_FILE]
	for suffix in ["", ".bak", ".tmp", ".corrupt"]:
		paths.append(SaveManager.slot_path(3) + suffix)
	return paths

func _finish() -> void:
	get_tree().paused = false
	for path in _protected_paths():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		if _original_files.has(path):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				_failures.append("无法还原玩家存档：" + path)
			else:
				file.store_buffer(_original_files[path])
				file.close()
	SaveManager.active_slot = _original_active
	GameState.menu_mode = "menu"
	print("[MenuFlowTest] ", "全部通过 ✅" if _failures.is_empty() else str(_failures))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
		push_error("[MenuFlowTest] " + message)
