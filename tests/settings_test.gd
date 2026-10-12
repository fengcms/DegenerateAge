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
	_check(screen.size.is_equal_approx(get_viewport().get_visible_rect().size / 1.5),
		"UI 根尺寸随缩放调整：实际 %s 视口 %s" % [screen.size, get_viewport().get_visible_rect().size])
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Music")), 0.4), "音乐音量即时生效")
	await _check_embedded_resize()
	print("[SettingsTest] 全部通过 ✅")
	get_tree().quit()

func _check_embedded_resize() -> void:
	var embedded := SubViewport.new()
	embedded.size = Vector2i(1153, 721)
	add_child(embedded)
	var layer := CanvasLayer.new()
	embedded.add_child(layer)
	var hud: Control = (load("res://scenes/ui/Hud.tscn") as PackedScene).instantiate()
	layer.add_child(hud)
	for viewport_size in [Vector2i(1153, 721), Vector2i(1387, 867)]:
		embedded.size = viewport_size
		for factor in [1.0, 1.5]:
			GameState.settings["uiScale"] = factor
			SettingsRuntime.apply_ui_scale_to(layer)
			await get_tree().process_frame
			var logical: Vector2 = Vector2(viewport_size) / factor
			_check(hud.size.is_equal_approx(logical), "HUD 根尺寸跟随游戏 Viewport")
			var map_panel := hud.get_node("MapPanel") as Control
			var hotbar := hud.get_node("Hotbar") as Control
			_check(map_panel.position.x >= 0 and map_panel.position.x + map_panel.size.x <= logical.x + 1,
				"小地图留在可见宽度内")
			_check(hotbar.position.y >= 0 and hotbar.position.y + hotbar.size.y <= logical.y + 1,
				"快捷栏留在可见高度内")
	embedded.queue_free()

func _map_key(action: String) -> int:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return int((event as InputEventKey).physical_keycode)
	return 0

func _check(ok: bool, message: String) -> void:
	if not ok:
		push_error("[SettingsTest] 失败：" + message)
		get_tree().quit(1)
