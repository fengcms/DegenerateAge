extends Node
## M4-6：旧档迁移、改键冲突交换与运行时 InputMap 回归。不写玩家存档。

func _ready() -> void:
	GameState.reset_to_defaults()
	var inventory_key := SettingsRuntime.default_key("panel_inventory")
	var character_key := SettingsRuntime.default_key("panel_character")
	_check(inventory_key > 0 and character_key > 0, "项目默认快捷键可读")
	_check(SettingsRuntime.set_binding("panel_inventory", character_key), "改键操作成功")
	_check(SettingsRuntime.key_for("panel_inventory") == character_key, "目标键位即时生效")
	_check(SettingsRuntime.key_for("panel_character") == inventory_key, "冲突键位交换")
	_check(_map_key("panel_inventory") == character_key, "InputMap 已应用新键位")
	var data := SaveManager._collect()
	_check(SaveManager._is_valid_save(data), "新设置可以存档")
	data["schemaVersion"] = 4
	for key in ["musicVolume", "screenShake", "strongFlash", "textScale", "fullscreen", "resolution", "qualityFilter", "keyBindings"]:
		data.settings.erase(key)
	_check(SaveManager._is_valid_save(data), "v4 旧档仍可读取")
	var migrated := SaveManager._migrate(data)
	_check(migrated.schemaVersion == 5 and migrated.settings.has("keyBindings"), "v4 设置补齐并迁移 v5")
	var bad := migrated.duplicate(true)
	bad.settings.keyBindings = {"panel_inventory": -1}
	_check(not SaveManager._is_valid_save(bad), "非法键位被拒绝")
	GameState.settings = migrated.settings
	SettingsRuntime.apply_all()
	_check(_map_key("panel_inventory") == inventory_key, "读取旧档恢复默认键位")
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(screen)
	GameState.settings["uiScale"] = 1.5
	GameState.settings["musicVolume"] = 0.4
	SettingsRuntime.apply_all()
	_check(is_equal_approx(ui.transform.x.x, 1.5), "UI 缩放即时生效")
	_check(screen.size.is_equal_approx(Vector2(get_viewport().size) / 1.5), "UI 根尺寸随缩放调整")
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Music")), 0.4), "音乐音量即时生效")
	print("[SettingsTest] 全部通过 ✅")
	get_tree().quit()

func _map_key(action: String) -> int:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return int((event as InputEventKey).physical_keycode)
	return 0

func _check(ok: bool, message: String) -> void:
	if not ok:
		push_error("[SettingsTest] 失败：" + message)
		get_tree().quit(1)
