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
	for key in ["musicVolume", "screenShake", "strongFlash", "textScale", "fullscreen", "resolution", "qualityFilter", "keyBindings",
		"mapScale", "displayScaleMode", "displayScale"]:
		data.settings.erase(key)
	_check(SaveManager._is_valid_save(data), "v4 旧档仍可读取")
	var migrated := SaveManager._migrate(data)
	_check(migrated.schemaVersion == SaveManager.CURRENT_SCHEMA and migrated.settings.has("keyBindings")
		and HotbarConfig.valid_layout(migrated.hotbar), "v4 设置与快捷栏补齐并迁移到当前版本")
	_check(is_equal_approx(float(migrated.settings.get("mapScale", -1.0)), 1.0)
		and String(migrated.settings.get("displayScaleMode", "")) == "auto"
		and is_equal_approx(float(migrated.settings.get("displayScale", -1.0)), 1.0),
		"M5-9c：显示三键缺键应补默认值（无需 schema 升级）")
	var bad := migrated.duplicate(true)
	bad.settings.keyBindings = {"panel_inventory": -1}
	_check(not SaveManager._is_valid_save(bad), "非法键位被拒绝")
	# M5-9c 回归（实测事故）：**当前版本**档缺新增设置键时仍必须可读 ——
	# 事故形态：9c 给 default_settings() 加键后，启动续档报「槽 1 主档不可用」，
	# 根因是 _migrate 原先只在 v < CURRENT_SCHEMA 时补设置键，而校验按 default_settings() 逐键查。
	var current := SaveManager._collect()
	current["schemaVersion"] = SaveManager.CURRENT_SCHEMA
	current.settings.erase("mapScale")
	current.settings.erase("displayScaleMode")
	current.settings.erase("displayScale")
	_check(SaveManager._is_valid_save(current), "当前版本档缺新增设置键仍应有效")
	var refilled := SaveManager._migrate(current)
	_check(is_equal_approx(float(refilled.settings.get("mapScale", -1.0)), 1.0)
		and String(refilled.settings.get("displayScaleMode", "")) == "auto"
		and is_equal_approx(float(refilled.settings.get("displayScale", -1.0)), 1.0),
		"当前版本档缺键应补齐默认值")
	# 补齐只填缺键，不得覆盖存档已有值、不得丢弃未知键
	current = SaveManager._collect()
	current["schemaVersion"] = SaveManager.CURRENT_SCHEMA
	current.settings.erase("displayScale")
	current.settings["displayScaleMode"] = "manual"
	current.settings["unknownFutureKey"] = 7
	refilled = SaveManager._migrate(current)
	_check(String(refilled.settings.get("displayScaleMode", "")) == "manual"
		and is_equal_approx(float(refilled.settings.get("displayScale", -1.0)), 1.0)
		and int(refilled.settings.get("unknownFutureKey", 0)) == 7,
		"补齐只填缺键：已有值与未知键均保留")
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
