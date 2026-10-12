class_name SettingsRuntime
extends RefCounted
## 设置统一应用层。改键只存物理键码，旧档迁移后沿用项目默认绑定。

const ACTIONS := ["move_up", "move_down", "move_left", "move_right", "attack", "target_next",
	"auto_battle", "auto_pickup", "interact", "pause", "panel_inventory", "panel_character",
	"panel_map", "panel_skill", "panel_mount", "hotbar_1", "hotbar_2", "hotbar_3",
	"hotbar_4", "hotbar_5", "hotbar_6", "hotbar_7", "hotbar_8", "hotbar_9",
	"hotbar_10", "hotbar_11", "hotbar_12"]

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

static func valid_choice(key: String, value: String) -> bool:
	if key == "qualityFilter":
		return ["all", "rare", "epic", "legendary"].has(value)
	if key == "resolution":
		return ["auto", "1280x800", "1440x900", "1600x900"].has(value)
	return false

static func default_key(action: String) -> int:
	var raw: Variant = ProjectSettings.get_setting("input/" + action, {})
	if raw is Dictionary:
		for event in raw.get("events", []):
			if event is InputEventKey:
				return int((event as InputEventKey).physical_keycode)
	return 0

static func key_for(action: String) -> int:
	var bindings: Dictionary = GameState.settings.get("keyBindings", {})
	return int(bindings.get(action, default_key(action)))

static func action_for_key(code: int, except_action: String = "") -> String:
	for action in ACTIONS:
		if action != except_action and key_for(action) == code:
			return action
	return ""

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
	_apply_audio()
	_apply_ui_scale()
	_apply_text_scale()
	_apply_window()

static func _apply_audio() -> void:
	AudioServer.set_bus_volume_linear(AudioServer.get_bus_index("Master"), clampf(float(GameState.settings.get("masterVolume", 1.0)), 0.0, 1.0))
	for name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	AudioServer.set_bus_volume_linear(AudioServer.get_bus_index("Music"), clampf(float(GameState.settings.get("musicVolume", 1.0)), 0.0, 1.0))
	AudioServer.set_bus_volume_linear(AudioServer.get_bus_index("SFX"), clampf(float(GameState.settings.get("sfxVolume", 1.0)), 0.0, 1.0))

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

## 使用 UI 实际所在 Viewport 的可见尺寸。嵌入式试玩时 SceneTree.root 是编辑器窗口，
## 与游戏 SubViewport 尺寸不同；拿 root.size 会让右/下锚点随窗口改变而漂出游戏区域。
static func apply_ui_scale_to(ui: CanvasLayer) -> void:
	var scale_value := clampf(float(GameState.settings.get("uiScale", 1.0)), 0.8, 1.5)
	var viewport_size := ui.get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	# 根控件使用当前游戏画布的逻辑尺寸，四边锚点才能始终贴住可见区域。
	var logical_size := viewport_size / scale_value
	for child in ui.get_children():
		if child is Control:
			var control := child as Control
			control.set_anchors_preset(Control.PRESET_TOP_LEFT)
			control.position = Vector2.ZERO
			control.size = logical_size
	ui.transform = Transform2D(Vector2(scale_value, 0), Vector2(0, scale_value), Vector2.ZERO)

static func _apply_text_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var ui := tree.current_scene.get_node_or_null("UI")
	if ui == null:
		return
	_text_scale_node(ui, clampf(float(GameState.settings.get("textScale", 1.0)), 0.8, 1.5))

static func _text_scale_node(node: Node, factor: float) -> void:
	if node is Label or node is Button or node is LineEdit or node is OptionButton:
		var control := node as Control
		if not control.has_meta("base_font_size"):
			control.set_meta("base_font_size", control.get_theme_font_size("font_size"))
		control.add_theme_font_size_override("font_size", maxi(9, roundi(int(control.get_meta("base_font_size")) * factor)))
	for child in node.get_children():
		_text_scale_node(child, factor)

static func _apply_window() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or OS.has_feature("headless"):
		return
	var window := tree.root
	window.mode = Window.MODE_FULLSCREEN if bool(GameState.settings.get("fullscreen", false)) else Window.MODE_WINDOWED
	if window.mode == Window.MODE_WINDOWED:
		match String(GameState.settings.get("resolution", "auto")):
			"1280x800": window.size = Vector2i(1280, 800)
			"1440x900": window.size = Vector2i(1440, 900)
			"1600x900": window.size = Vector2i(1600, 900)
