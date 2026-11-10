extends Node
## 本机显示偏好的来源、迁移和失败写入回归；必须使用隔离项目，避免接触玩家文件。
var failures: Array[String] = []

## 覆盖旧值保护、逐项自动、跨档恢复、损坏备份与原子写失败，所有断言聚合输出。
func _ready() -> void:
	if not DiagnosticProbeGuard.require_isolated(self):
		return
	DirAccess.remove_absolute(SettingsRuntime.DISPLAY_PREFS_PATH)
	GameState.reset_to_defaults()
	SettingsRuntime.load_display_policy({})
	check(SettingsRuntime.ensure_display_preferences(true), "首次启动在旧档迁移之后持久化自动来源")
	var auto_document := FileAccess.get_file_as_string(SettingsRuntime.DISPLAY_PREFS_PATH)
	SettingsRuntime.load_display_policy({"uiScale": 1.75})
	GameState.reset_to_defaults()
	check(SettingsRuntime.scale_source("uiScale") == "auto", "重新启动不会把新角色默认值误迁为旧手动值")
	check(SettingsRuntime.ensure_display_preferences(true) and FileAccess.get_file_as_string(SettingsRuntime.DISPLAY_PREFS_PATH) == auto_document, "重复启动不改已有偏好文档")
	DirAccess.remove_absolute(SettingsRuntime.DISPLAY_PREFS_PATH)
	var old := {"uiScale": 1.0, "mapScale": 1.25, "textScale": 2.0, "displayScaleMode": "manual", "displayScale": 1.5}
	var decoded := SettingsRuntime.decode_display_preferences(old)
	check(decoded.values.uiScale == 1.0 and decoded.scaleSources.uiScale == "legacy", "旧手动100%不能被误判未自定义")
	check(decoded.values.mapScale == 1.25 and decoded.values.displayScale == 1.5, "旧倍率与高级系数原值保留")
	decoded = SettingsRuntime.decode_display_preferences({"uiScale": 1.5})
	check(decoded.scaleSources.uiScale == "legacy" and decoded.scaleSources.mapScale == "auto", "缺失轴自动，已有轴保留")
	decoded = SettingsRuntime.decode_display_preferences({"uiScale": INF, "textScale": -1, "mapScale": "2", "fullscreen": 1})
	check(decoded.values.is_empty(), "错误类型、非法数值和越界值拒绝")
	decoded = SettingsRuntime.decode_display_preferences({"version": 2, "windowPolicy": "custom", "customWindowSize": [NAN, 900]})
	check(decoded.windowPolicy == "auto_maximized", "非法自定义窗口安全回退")
	GameState.reset_to_defaults()
	SettingsRuntime.load_display_policy({})
	SettingsRuntime.mark_display_customized("musicVolume")
	check(SettingsRuntime.scale_source("uiScale") == "auto", "改音量不标记显示自定义")
	GameState.settings.uiScale = 1.0
	SettingsRuntime.mark_display_customized("uiScale")
	check(SettingsRuntime.scale_source("uiScale") == "manual" and SettingsRuntime.scale_source("textScale") == "auto", "新手动100%只保护自身")
	check(SettingsRuntime.save_display_preferences(true), "v2偏好保存成功")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SettingsRuntime.DISPLAY_PREFS_PATH))
	check(raw.version == 2 and raw.scaleSources.uiScale == "manual" and raw.scaleSources.mapScale == "auto", "写入来源而非只写快照数值")
	SettingsRuntime.read_display_preferences()
	check(SettingsRuntime.save_display_preferences(true), "JSON数字解析为浮点版本后仍可再次保存")
	SettingsRuntime.load_display_policy({})
	GameState.reset_to_defaults()
	check(SettingsRuntime.scale_source("uiScale") == "manual", "重置角色保留本机来源")
	var slot := SaveManager._collect()
	slot.settings.uiScale = 1.75
	SaveManager.apply_to_game_state(slot)
	check(GameState.settings.uiScale == 1.0 and SettingsRuntime.scale_source("uiScale") == "manual", "读取别的角色不覆盖本机偏好")
	SettingsRuntime.restore_automatic_scale("uiScale")
	check(SettingsRuntime.scale_source("uiScale") == "auto" and GameState.settings.uiScale == 1.0, "恢复自动不擦除保留手动值")
	var before := FileAccess.get_file_as_bytes(SettingsRuntime.DISPLAY_PREFS_PATH)
	DirAccess.make_dir_absolute(SettingsRuntime.DISPLAY_PREFS_PATH + ".tmp")
	check(not SettingsRuntime.save_display_preferences(true), "临时文件无法写入时明确失败")
	check(FileAccess.get_file_as_bytes(SettingsRuntime.DISPLAY_PREFS_PATH) == before, "保存失败不破坏旧偏好")
	DirAccess.remove_absolute(SettingsRuntime.DISPLAY_PREFS_PATH + ".tmp")
	write_raw("{ broken")
	check(SettingsRuntime.read_display_preferences().is_empty(), "损坏配置不影响游戏回退")
	var backup_found := false
	for file in DirAccess.get_files_at("user://"):
		if file.begins_with("display_preferences.json.corrupt-"):
			backup_found = FileAccess.get_file_as_string("user://" + file) == "{ broken"
	check(backup_found, "损坏原文有可诊断备份")
	write_raw('{"version":99,"uiScale":1.5}')
	SettingsRuntime.read_display_preferences()
	check(not SettingsRuntime.save_display_preferences(true), "未来版本禁止降级覆盖")
	check(FileAccess.get_file_as_string(SettingsRuntime.DISPLAY_PREFS_PATH).contains('"version":99'), "未来版本原文件保持")
	DirAccess.remove_absolute(SettingsRuntime.DISPLAY_PREFS_PATH)
	SettingsRuntime.read_display_preferences()
	SettingsRuntime.adopt_legacy_display_preferences(old)
	check(SettingsRuntime.scale_source("mapScale") == "legacy", "首次迁入旧角色保留旧来源")
	print("[DisplayPreferencesTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

## 写入显式损坏/未来版本夹具，仅允许隔离测试调用。
func write_raw(value: String) -> void:
	var file := FileAccess.open(SettingsRuntime.DISPLAY_PREFS_PATH, FileAccess.WRITE)
	file.store_string(value)
	file.close()

## 累积错误，保证后续兼容分支仍完成验证。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[DisplayPreferencesTest] " + message)
