class_name SettingsRuntime
extends RefCounted
## 设置统一应用层：输入、声音、窗口和显示倍率的唯一应用入口。
## 本机显示偏好独立于角色存档；只保存手动值与来源，自动推荐保存在会话缓存。

const ACTIONS := ["move_up", "move_down", "move_left", "move_right", "attack", "target_next", "sit_toggle",
	"auto_battle", "auto_pickup", "interact", "pause", "panel_inventory", "panel_character",
	"panel_map", "panel_skill", "panel_mount", "mount_toggle", "hotbar_1", "hotbar_2", "hotbar_3",
	"hotbar_4", "hotbar_5", "hotbar_6", "hotbar_7", "hotbar_8", "hotbar_9",
	"hotbar_10", "hotbar_11", "hotbar_12"]

## M5-9c（09-A §4）：显示适配手动系数与 UI/文字/地图三轴的档位上下限。
## 4K 试玩修订：界面、地图、文字三轴均可选到 200%；旧档值继续按原值读取。
const DISPLAY_SCALE_MIN := 0.75
const DISPLAY_SCALE_MAX := 1.5
const UI_SCALE_MIN := 0.8
const UI_SCALE_MAX := 2.0
const MAP_SCALE_MIN := 0.8
const MAP_SCALE_MAX := 2.0
## 弹层（Window 类对话框）允许占用的界面设计空间上限比例，留边避免高倍率下顶满窗口。
const DIALOG_FIT_RATIO := 0.96
const TEXT_SCALE_MIN := 0.8
const TEXT_SCALE_MAX := 2.0
## 与角色进度分离的本机显示偏好；旧槽的 settings 字段继续保留以兼容旧档。
const DISPLAY_PREFS_PATH := "user://display_preferences.json"
const SCALE_KEYS := ["uiScale", "mapScale", "textScale"]
## 元数据随本机偏好加载，角色重置不会清空；测试可通过 load_display_policy 显式建立隔离状态。
static var _display_policy: Dictionary = {}
static var _preferences_write_blocked := false
static var _screen_snapshot: Dictionary = {}

const DISPLAY_PREF_KEYS := ["uiScale", "mapScale", "textScale", "displayScaleMode", "displayScale",
	"fullscreen", "resolution"]

## String 型设置键的合法值表（**单一来源**，C-P2-1）。
## 新增默认值为 String 的设置键**必须**在此登记，否则 `valid_choice` 无法判定其值域；
## `tests/smoke_test.gd` 有一条断言逐键核对「default_settings() 中 String 键均已登记」，漏注册会在冒烟阶段失败。
## ⚠ 历史事故（M5-9c）：漏登记会让 `_is_valid_save` 把该键的任何合法值判非法 → 全量存量档被判损坏。
const CHOICE_VALUES := {
	"colorblindMode": ["off", "friendly"],
	"qualityFilter": ["all", "rare", "epic", "legendary"],
	"resolution": ["auto", "1280x800", "1440x900", "1600x900", "1920x1200"],
	"displayScaleMode": ["auto", "manual"],
	"sellGearPreset": ["cautious", "standard", "aggressive"],
}

## 数值型设置键的合法区间（**单一来源**，C-P2-3）。未登记键仅要求「有限数且非负」。
## 区间与运行态读取口径一致（`display_scale_factor` / `_apply_map_scale` 等使用同一组常量）。
const NUMERIC_RANGES := {
	"potionThreshold": [0.0, 1.0],
	"masterVolume": [0.0, 1.0],
	"sfxVolume": [0.0, 1.0],
	"musicVolume": [0.0, 1.0],
	"uiScale": [UI_SCALE_MIN, UI_SCALE_MAX],
	"textScale": [TEXT_SCALE_MIN, TEXT_SCALE_MAX],
	"mapScale": [MAP_SCALE_MIN, MAP_SCALE_MAX],
	"displayScale": [DISPLAY_SCALE_MIN, DISPLAY_SCALE_MAX],
	"searchRadius": [1.0, 99.0],
	# 与 `GameState.LOW_GEAR_LEVEL_MAX` 必须相等（**同一口径**）。本常量表是 `const`，
	# 无法跨 autoload 取常量，故此处写字面量，由 `smoke_test` 的逐键断言核对两者相等。
	# ⚠ 只改 `GameState` 而不改这里 ⇒ 玩家把筛选设到 >100 后存档被 `_is_valid_save` 判「数值越界」= 存档损坏。
	"lowGearLevelLimit": [1.0, 9999.0],
}

## 校验显示偏好数值；与角色设置使用相同值域，不允许 NaN、越界或错误类型进入布局。
static func valid_display_value(key: String, value: Variant) -> bool:
	if key in SCALE_KEYS or key == "displayScale":
		return (value is int or value is float) and valid_setting_number(key, float(value))
	if key == "fullscreen":
		return value is bool
	return value is String and valid_choice(key, value)

## 纯解析 v1/v2 本机偏好；旧值含 100% 均标为 legacy，真正缺失的轴才采用自动。
static func decode_display_preferences(raw: Dictionary) -> Dictionary:
	var values := {}
	for key in DISPLAY_PREF_KEYS:
		if raw.has(key) and valid_display_value(key, raw[key]):
			values[key] = raw[key]
	var version: Variant = raw.get("version", 1)
	var v2: bool = (version is int or version is float) and version == 2
	var raw_sources: Variant = raw.get("scaleSources", {})
	var sources := {}
	for key in SCALE_KEYS:
		var source := "legacy" if values.has(key) else "auto"
		if v2 and raw_sources is Dictionary and raw_sources.get(key) in ["auto", "manual", "legacy"]:
			source = raw_sources[key] if values.has(key) else "auto"
		sources[key] = source
	var window_policy := "fullscreen" if values.get("fullscreen", false) else ("fixed" if values.get("resolution", "auto") != "auto" else "auto_maximized")
	var custom_size := Vector2i.ZERO
	var custom: Variant = raw.get("customWindowSize", [])
	if custom is Array and custom.size() == 2:
		if valid_window_dimension(custom[0]) and valid_window_dimension(custom[1]):
			custom_size = Vector2i(int(custom[0]), int(custom[1]))
	if v2 and raw.get("windowPolicy") in ["auto_maximized", "fixed", "custom", "fullscreen"]:
		window_policy = raw.windowPolicy
	if window_policy == "custom" and custom_size == Vector2i.ZERO:
		window_policy = "auto_maximized"
	return {"values": values, "scaleSources": sources, "windowPolicy": window_policy, "customWindowSize": custom_size}

## 自定义客户区使用整数像素；拒绝非法数值和不合理的大尺寸，实际落屏仍须按工作区夹紧。
static func valid_window_dimension(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= 64 and value <= 32768

## 从显式文档更新会话来源，供首次迁移及独立测试使用，不写入磁盘或角色成长数据。
static func load_display_policy(raw: Dictionary) -> void:
	_display_policy = decode_display_preferences(raw)

## 查询来源只读会话缓存，不在界面热路径读文件。
static func scale_source(key: String) -> String:
	return str(_display_policy.get("scaleSources", {}).get(key, "auto"))

## 记录真正由玩家触发的字段变化；声音/玩法变更不改变显示来源。
static func mark_display_customized(key: String) -> void:
	if _display_policy.is_empty():
		load_display_policy({})
	if key in SCALE_KEYS:
		_display_policy.scaleSources[key] = "manual"
	elif key in ["displayScale", "displayScaleMode"]:
		for axis in SCALE_KEYS:
			_display_policy.scaleSources[axis] = "legacy"
	elif key in ["fullscreen", "resolution"]:
		if key == "resolution":
			_display_policy.customWindowSize = Vector2i.ZERO
		var windowed := "fixed" if GameState.settings.get("resolution", "auto") != "auto" else "auto_maximized"
		if _display_policy.customWindowSize != Vector2i.ZERO:
			windowed = "custom"
		_display_policy.windowPolicy = "fullscreen" if GameState.settings.get("fullscreen", false) else windowed

## 恢复指定轴或三轴自动；保留手动值，后续重新选手动时不会丢失原有配置。
static func restore_automatic_scale(key: String = "") -> void:
	if _display_policy.is_empty():
		load_display_policy({})
	for axis in SCALE_KEYS:
		if key.is_empty() or key == axis:
			_display_policy.scaleSources[axis] = "auto"

## 仅在旧角色导入本机偏好时调用，必须在第一次保存自动配置之前执行。
static func adopt_legacy_display_preferences(settings: Dictionary) -> void:
	load_display_policy(settings)

## 读取并校验文件；损坏文档先保留副本，不能备份时禁止覆盖。未来版本也不降级写入。
static func _read_display_document() -> Dictionary:
	_preferences_write_blocked = false
	if not FileAccess.file_exists(DISPLAY_PREFS_PATH):
		return {}
	var file := FileAccess.open(DISPLAY_PREFS_PATH, FileAccess.READ)
	if file == null:
		_preferences_write_blocked = true
		return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		var backup := DISPLAY_PREFS_PATH + ".corrupt-" + str(Time.get_ticks_usec())
		_preferences_write_blocked = DirAccess.copy_absolute(DISPLAY_PREFS_PATH, backup) != OK
		push_warning("[SettingsRuntime] 显示偏好损坏，已尝试保留副本：" + backup)
		return {}
	var raw: Dictionary = parser.data
	var version: Variant = raw.get("version", 1)
	if not (version is int or version is float) or (version != 1 and version != 2):
		_preferences_write_blocked = true
	return raw

## 返回合法的七项兼容值；来源元数据不会混进角色 settings 校验。
static func read_display_preferences() -> Dictionary:
	return decode_display_preferences(_read_display_document()).values

## 返回本机显示偏好覆盖后的设置。磁盘无记录时保留当前会话来源，不让新建角色重置玩家选择。
static func with_display_preferences(settings: Dictionary) -> Dictionary:
	var result := settings.duplicate(true)
	var raw := _read_display_document()
	if not raw.is_empty() or _display_policy.is_empty():
		load_display_policy(raw)
	for key in decode_display_preferences(raw).values:
		result[key] = raw[key]
	return result

## 保存版本、逐项来源和手动值；自动推荐不回写。隔离测试按既有开关决定是否允许写入。
static func save_display_preferences(force_in_tests: bool = false) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if not force_in_tests and tree != null and tree.current_scene != null \
			and String(tree.current_scene.scene_file_path).begins_with("res://tests/"):
		return true
	if _preferences_write_blocked:
		push_warning("[SettingsRuntime] 保留不可覆盖的显示偏好，未写入")
		return false
	if _display_policy.is_empty():
		load_display_policy({})
	var values := {"version": 2, "scaleSources": _display_policy.scaleSources.duplicate(), "windowPolicy": _display_policy.windowPolicy}
	var custom_size: Vector2i = _display_policy.customWindowSize
	values.customWindowSize = [custom_size.x, custom_size.y]
	var defaults := GameState.default_settings()
	for key in DISPLAY_PREF_KEYS:
		var value: Variant = GameState.settings.get(key, defaults[key])
		values[key] = value if valid_display_value(key, value) else defaults[key]
	var tmp := DISPLAY_PREFS_PATH + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("[SettingsRuntime] 无法写入显示偏好")
		return false
	file.store_string(JSON.stringify(values, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(tmp, DISPLAY_PREFS_PATH) != OK:
		DirAccess.remove_absolute(tmp)
		push_warning("[SettingsRuntime] 无法保存显示偏好")
		return false
	return true

## 旧槽迁移完成后建立缺失的本机文档，保存自动来源而非推荐快照。
## 否则新角色默认值下次启动会被误当成旧手动值；已有文档（含损坏/未来版本）不覆盖。
static func ensure_display_preferences(force_in_tests: bool = false) -> bool:
	if FileAccess.file_exists(DISPLAY_PREFS_PATH):
		return true
	return save_display_preferences(force_in_tests)

## 无头判定唯一可靠方式。⚠ `OS.has_feature("headless")` 实测恒为 false（无头下也 false），勿用。
static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

## M5-9c：显示适配模式（"auto" / "manual"）。非法值与缺键一律视为 auto。
static func display_scale_mode() -> String:
	var mode := String(GameState.settings.get("displayScaleMode", "auto"))
	return "manual" if mode == "manual" else "auto"

## 旧版高级统一系数，只影响 legacy 来源；手动轴与自动轴均不重复乘它。
static func display_scale_factor() -> float:
	if display_scale_mode() != "manual":
		return 1.0
	var factor := float(GameState.settings.get("displayScale", 1.0))
	return clampf(factor, DISPLAY_SCALE_MIN, DISPLAY_SCALE_MAX) if is_finite(factor) else 1.0

## 解析单轴最终倍率。未启动主场景的工具/无头预览没有屏幕快照，沿用其显式原值。
## 自动值只来自缓存；旧来源保留历史乘法，新的手动值就是玩家选择的最终百分比。
static func effective_scale(key: String) -> float:
	var raw := float(GameState.settings.get(key, 1.0))
	if not is_finite(raw):
		raw = 1.0
	raw = clampf(raw, float(NUMERIC_RANGES[key][0]), float(NUMERIC_RANGES[key][1]))
	var source := scale_source(key)
	if source == "auto" and not _screen_snapshot.is_empty():
		return DisplayEnvironment.recommended_scale(_screen_snapshot)
	if source == "manual":
		return raw
	return raw * display_scale_factor()

## Main 低频检查屏幕变化；同屏窗口拖动只更新诊断快照，不触发三轴重算或写文件。
static func refresh_screen_environment() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var snapshot := DisplayEnvironment.screen_snapshot(tree.root)
	var changed := DisplayEnvironment.screen_signature(snapshot) != DisplayEnvironment.screen_signature(_screen_snapshot)
	_screen_snapshot = snapshot
	return changed

## 屏幕变化后只刷新显示，不重载输入、声音、窗口或持久化来源。
static func refresh_display_scales() -> void:
	_apply_ui_scale()
	_apply_text_scale()
	_apply_map_scale()
	apply_world_text_scale()

## 校验输入绑定字段是否符合现有动作规则。
static func valid_bindings(value: Dictionary) -> bool:
	var used := {}
	for action in value:
		if not ACTIONS.has(String(action)):
			return false
		var code: Variant = value[action]
		if not (code is int or code is float) or float(code) != floor(float(code)) or int(code) <= 0:
			return false
		if used.has(int(code)):
			return false
		used[int(code)] = true
	return true

## String 型设置键的合法值列表（单一来源，C-P2-1）。未登记的键返回空数组。
## `lowGearMaxQuality` 的合法值来自品质枚举（`Shop.QUALITY_ORDER`），不在此重复维护。
static func choice_values(key: String) -> Array:
	if key == "lowGearMaxQuality":
		return Shop.QUALITY_ORDER
	var values: Variant = CHOICE_VALUES.get(key)
	return values if values is Array else []

## 该键是否为「已登记的枚举止键」。未登记键不做值域校验（见 `_is_valid_save` 注释）。
static func is_choice_key(key: String) -> bool:
	return not choice_values(key).is_empty()

## 检查枚举型设置值是否位于登记选项中。
static func valid_choice(key: String, value: String) -> bool:
	return choice_values(key).has(value)

## 数值型设置键的合法区间校验（单一来源，C-P2-3）。未登记键仅要求有限且非负。
static func valid_setting_number(key: String, value: float) -> bool:
	if not is_finite(value):
		return false
	var range: Variant = NUMERIC_RANGES.get(key)
	if range is Array:
		var bounds := range as Array
		return value >= float(bounds[0]) and value <= float(bounds[1])
	return value >= 0.0

## 返回动作默认键位，供恢复绑定使用。
static func default_key(action: String) -> int:
	var raw: Variant = ProjectSettings.get_setting("input/" + action, {})
	if raw is Dictionary:
		for event in raw.get("events", []):
			if event is InputEventKey:
				return int((event as InputEventKey).physical_keycode)
	return 0

## 读取动作的有效当前键位。
static func key_for(action: String) -> int:
	var bindings: Dictionary = GameState.settings.get("keyBindings", {})
	return int(bindings.get(action, default_key(action)))

## 查找当前键位对应的动作。
static func action_for_key(code: int, except_action: String = "") -> String:
	for action in ACTIONS:
		if action != except_action and key_for(action) == code:
			return action
	return ""

## 更新动作绑定，沿用现有冲突处理规则。
static func set_binding(action: String, code: int) -> bool:
	if not ACTIONS.has(action) or code <= 0:
		return false
	var conflict := action_for_key(code, action)
	var bindings: Dictionary = GameState.settings.get("keyBindings", {}).duplicate()
	if not conflict.is_empty():
		bindings[conflict] = key_for(action)
	bindings[action] = code
	GameState.settings["keyBindings"] = bindings
	apply_all()
	EventBus.settings_changed.emit()
	return true

## 将当前设置统一应用到输入、显示、界面及声音。
static func apply_all() -> void:
	InputMap.load_from_project_settings()
	var bindings: Dictionary = GameState.settings.get("keyBindings", {})
	for action in bindings:
		if not ACTIONS.has(String(action)):
			continue
		InputMap.action_erase_events(String(action))
		var event := InputEventKey.new()
		event.physical_keycode = int(bindings[action])
		InputMap.action_add_event(String(action), event)
	apply_audio()
	_apply_ui_scale()
	_apply_text_scale()
	_apply_map_scale()
	apply_world_text_scale()   # M5-9e：世界文字反向补偿与地图倍率联动（见该函数）

## M5-9a（09-A 显示适配，工程 17）：渲染策略 = disabled。
## disabled 下「逻辑视口尺寸 = 窗口逻辑尺寸」⇒ 窗口放大 = 看到更多地图，元素像素尺寸不变；
## 基准 1280×800 时与 canvas_items 1:1 等价，故不是"换基准"，是渲染策略修正。
##
## ⚠ 为什么写在运行时而不是 project.godot：
## 无头运行时 dummy 显示驱动报告窗口尺寸 0×0，而 disabled 的视口尺寸**源自窗口** ⇒ 根视口
## 塌成 64×64；`Game.visible_enemies()` 用 `get_viewport_rect()` 判定可见怪，于是有怪也"看不见"，
## T 系列冒烟（自动战斗锁定目标等）随之误判。无头没有显示器、策略无意义，故无头保持项目默认的
## canvas_items（视口取 `display/window/size/viewport_*` 的 1280×800）。
## ⚠ 判断无头只能用 DisplayServer.get_name()：`OS.has_feature("headless")` 实测恒为 false。
static func apply_display_strategy() -> void:
	if is_headless():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED

## 将音量和静音设置应用到现有声音总线。
static func apply_audio() -> void:
	AudioServer.set_bus_volume_linear(AudioServer.get_bus_index("Master"), clampf(float(GameState.settings.get("masterVolume", 1.0)), 0.0, 1.0))
	for name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	AudioServer.set_bus_volume_linear(AudioServer.get_bus_index("Music"), clampf(float(GameState.settings.get("musicVolume", 1.0)), 0.0, 1.0))
	AudioServer.set_bus_volume_linear(AudioServer.get_bus_index("SFX"), clampf(float(GameState.settings.get("sfxVolume", 1.0)), 0.0, 1.0))

## M5-9c：视口尺寸变化后的重算入口。`main.gd` 对 `size_changed` 做同帧合并后调用本函数
## （disabled 策略下拖窗口会高频触发，避免重复重排全部面板）。
static func reapply_for_viewport() -> void:
	_apply_ui_scale()

## 查找当前场景界面并应用统一倍率。
static func _apply_ui_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null:
		return
	var ui := scene.get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	apply_ui_scale_to(ui)

## 布局尺寸是否可用。**唯一判据，不要在各处重写 `size <= 0`。**
## 拦截非有限值与非正尺寸，避免异常输入扩散；不将其视作本次重铸闪退的已证实根因。
static func is_usable_layout_size(size: Vector2) -> bool:
	return is_finite(size.x) and is_finite(size.y) and size.x > 0.0 and size.y > 0.0

## 使用 UI 实际所在 Viewport 的可见尺寸。嵌入式试玩时 SceneTree.root 是编辑器窗口，
## 与游戏 SubViewport 尺寸不同；拿 root.size 会让右/下锚点随窗口改变而漂出游戏区域。
## M5-9c：最终倍率 = clamp(uiScale) × display_scale_factor()（自动模式下后者恒为 1.0）。
static func apply_ui_scale_to(ui: CanvasLayer) -> void:
	var scale_value := ui_scale_value()
	if not is_finite(scale_value) or scale_value <= 0.0:
		return
	var viewport := ui.get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	if not is_usable_layout_size(viewport_size):
		return
	# 根控件使用当前游戏画布的逻辑尺寸，四边锚点才能始终贴住可见区域。
	var logical_size := viewport_size / scale_value
	if not is_usable_layout_size(logical_size):
		return
	for child in ui.get_children():
		if child is Control:
			var control := child as Control
			control.set_anchors_preset(Control.PRESET_TOP_LEFT)
			control.position = Vector2.ZERO
			control.size = logical_size
	ui.transform = Transform2D(Vector2(scale_value, 0), Vector2(0, scale_value), Vector2.ZERO)

## 返回经过来源解析及有限性防御的界面倍率，供所有面板统一换算逻辑视口。
static func ui_scale_value() -> float:
	return effective_scale("uiScale")

## 把界面倍率补到 Window 类弹层（FileDialog / Popup 等）上。
## 界面轴挂在 UI CanvasLayer 的 transform，而 transform 只作用于 CanvasItem；Window 不是
## CanvasItem，落在视口像素坐标系，不会跟随界面倍率 ⇒ 高分屏 / 高界面倍率下弹层会明显小于
## 其余面板、内容（文字、行高）也不放大，必须在弹层自身补同一份内容缩放。
## 弹层内部的子弹层（FileDialog 自带的覆盖确认 / 收藏夹菜单等）同样落在独立视口，一并补上。
## 见工程文档《存档导出文件选择器高分屏缩放修正》。
static func apply_ui_scale_to_window(dialog: Window) -> void:
	var scale_value := ui_scale_value()
	for window in [dialog] + dialog.find_children("*", "Window", true, false):
		(window as Window).content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		(window as Window).content_scale_factor = scale_value

## 弹层的视口像素尺寸 = 设计尺寸 × 界面倍率：弹层内可用设计空间因此恒等于设计尺寸，
## 与同倍率下的面板同一口径（面板也是在「视口尺寸 / 倍率」的设计空间里排版）。
## 界面倍率越大，窗口能容纳的设计空间越小，故按设计空间收缩，避免弹层大过游戏窗口、
## 确认按钮落到屏幕外。`viewport_size` 取弹层父视口的可见尺寸。
static func dialog_popup_size(viewport_size: Vector2, design_size: Vector2i) -> Vector2i:
	var scale_value := ui_scale_value()
	var design_space := viewport_size / maxf(scale_value, 0.01)
	var design := Vector2(design_size).min(design_space * DIALOG_FIT_RATIO)
	return Vector2i((design * scale_value).round())

## 按当前文字倍率刷新界面文字，不重复叠乘历史字号。
static func _apply_text_scale() -> void:
	# 引擎的原生悬浮提示不在 UI CanvasLayer 下，必须单独给 TooltipLabel 设置字号。
	var theme := ThemeDB.get_project_theme()
	if theme != null:
		theme.set_font_size("font_size", "TooltipLabel", maxi(9, roundi(16.0 * text_scale_value())))
		_apply_tooltip_shell(theme)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	apply_text_scale_to(tree.current_scene.get_node_or_null("UI"))

## 工程 78：原生悬浮提示换壳 —— 与 panel_help_button 同款（深底 + 灰边 + 圆角 + 内衬）。
## 引擎默认 TooltipPanel 是「黑半透明」的唯一来源；换壳后全部 tooltip_text 原生提示一次换装。
## 注意：自定义浮层（_make_custom_tooltip）同样被 TooltipPanel 包裹，且 PopupPanel::_update_child_rects
## 会把内容内缩到 content margin 内 ⇒ 外壳对自定义卡片是可见的「容器框」，
## 卡片本体（品质描边）不动，背包对比多卡的卡片结构零改动。
static func _apply_tooltip_shell(theme: Theme) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111820")
	style.border_color = Color("74818a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	theme.set_stylebox("panel", "TooltipPanel", style)
	theme.set_color("font_color", "TooltipLabel", Color("e1e7ee"))

## 文字轴使用独立有效倍率，后续仅补偿 UI 已有变换。
static func text_scale_value() -> float:
	return effective_scale("textScale")

## 供外部（测试 / 工具）对指定 UI 层直接应用文字缩放，不依赖 current_scene 路径
## —— 与 `apply_ui_scale_to` / `apply_map_scale_to` 同一模式。
static func apply_text_scale_to(ui: Node) -> void:
	if ui == null:
		return
	# CanvasLayer 已放大整个控件树；字体只补「目标文字倍率 / 当前界面倍率」。
	# 因此界面 150% + 文字 150% 的最终字体仍为 150%，不会叠成 225%。
	_text_scale_node(ui, text_scale_value() / ui_scale_value())

## 递归应用文字倍率，缓存原始字号作为计算基准。
static func _text_scale_node(node: Node, factor: float) -> void:
	if node is TabContainer:
		# TabBar 是 TabContainer 的内部子节点，默认 get_children() 不会遍历到。
		_text_scale_node((node as TabContainer).get_tab_bar(), factor)
	if node is Label or node is Button or node is LineEdit or node is OptionButton or node is TabBar:
		var control := node as Control
		if not control.has_meta("base_font_size"):
			control.set_meta("base_font_size", control.get_theme_font_size("font_size"))
		control.add_theme_font_size_override("font_size", maxi(9, roundi(int(control.get_meta("base_font_size")) * factor)))
	for child in node.get_children():
		_text_scale_node(child, factor)

## 地图显示大小 = 相机 zoom（80/100/125/150/175/200%）。
## zoom < 1 时可见范围等比例变大（不改碰撞、射程、怪物数量、拾取距离，创意 09 §4）；
## 数据不变时相机被 limit 夹住 ⇒ 地图外围会出现底色空白 —— 属"地图真实边界外仍受相机限制"
## 的预期行为，不视为缺陷（是否给边界外做装饰留 M6）。
static func _apply_map_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var camera := tree.get_first_node_in_group("player_camera") as Camera2D
	if camera == null:
		return
	apply_map_scale_to(camera)

## 供世界装配（game.gd）在**切图重建 Player 后**调用：不依赖 current_scene 的节点路径。
static func apply_map_scale_to(camera: Camera2D) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	camera.zoom = Vector2.ONE * map_scale_value()
	StableFollowCamera.snap(camera)

## 地图独立有效倍率；仅影响相机显示，不修改世界坐标或玩法数值。
static func map_scale_value() -> float:
	return effective_scale("mapScale")

## 返回文字相对地图缩放的反向补偿倍率。
static func world_text_scale_value() -> float:
	return text_scale_value() / map_scale_value()

# ---- M5-9e（创意 09 §7）：世界文字反向补偿 ----
##
## 人物 / 地形 / 物品形状随相机 zoom 缩放（世界坐标画布，天然跟随）；但**头顶名称、交互提示、
## 伤害飘字、墓碑倒计时**必须保持可读的文字像素尺寸 —— zoom<1 时它们会跟着变小，正是"看不清"的来源。
##
## 实现：文字节点入组 `world_text`，倍率 = 目标文字倍率 / 地图倍率。
## - Control（Label）：设 `scale` + `pivot_offset = size/2`（绕自身中心缩放，位置不动）。
##   入组节点在 `_ready` 里**自应用一次**（覆盖生成时刻 / 切图重建 / 动态飘字），
##   运行时改档位由本组统一重扫（apply_all → 本函数）。
## - 自绘文字（CanvasItem 非 Control，如墓碑倒计时）：只 `queue_redraw`，由 `_draw` 按当时倍率取字号。
## ⚠ 飘字 / 头顶名称均**无自身 scale 动画**（实测 U4），故直接缩放节点即可，无需父节点中转。
static func apply_world_text_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for node in tree.get_nodes_in_group("world_text"):
		apply_world_text_scale_to(node)

## 对单个世界文字节点应用反向补偿（外部在 `_ready` 自应用时用）。
static func apply_world_text_scale_to(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Control:
		var control := node as Control
		var factor := world_text_scale_value()
		control.scale = Vector2(factor, factor)
		# 绕自身中心缩放：pivot 未设时默认绕左上角，文字会向右下漂
		control.pivot_offset = control.size * 0.5
	elif node is CanvasItem:
		(node as CanvasItem).queue_redraw()

## Main 首次进入时应用窗口偏好，角色加载和普通设置更新不改变窗口。
static func initialize_startup_display() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		DisplayEnvironment.initialize(tree.root, _display_policy, str(GameState.settings.get("resolution", "auto")))
		refresh_screen_environment()

## 玩家明确变更窗口模式时调用，与音量、按键等设置的应用路径分离。
static func apply_window_preferences() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		DisplayEnvironment.apply_window(tree.root, _display_policy, str(GameState.settings.get("resolution", "auto")))

## 显式记住当前客户区尺寸；拖动窗口本身不产生持久化副作用。
static func remember_current_window() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or not DisplayEnvironment.can_control_window(tree.root):
		return false
	if tree.root.mode not in [Window.MODE_WINDOWED, Window.MODE_MAXIMIZED]:
		return false
	if _display_policy.is_empty():
		load_display_policy({})
	_display_policy.windowPolicy = "custom"
	_display_policy.customWindowSize = tree.root.size
	GameState.settings.fullscreen = false
	GameState.settings.resolution = "auto"
	return true

## 设置页显示实际启动策略，避免记住自定义尺寸后仍误显示自动最大化。
static func window_preference_description() -> String:
	var policy: String = _display_policy.get("windowPolicy", "auto_maximized")
	if policy == "custom":
		var size: Vector2i = _display_policy.customWindowSize
		return Localization.tr_key("ui.display.window_custom") % [size.x, size.y]
	if policy == "fixed":
		return Localization.tr_key("ui.display.window_fixed") % str(GameState.settings.get("resolution", "auto"))
	return Localization.tr_key("ui.display.window_" + policy)
