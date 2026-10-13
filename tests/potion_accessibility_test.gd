extends Node
## 药品不只靠颜色识别，配色预设随设置切换且存档校验接受。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func _ready() -> void:
	GameState.reset_to_defaults()
	var red := ItemSlot.new()
	var blue := ItemSlot.new()
	add_child(red)
	add_child(blue)
	red.item = {"kind": "potion", "itemId": "potion_hp_small", "count": 1}
	blue.item = {"kind": "potion", "itemId": "potion_mp_small", "count": 1}
	check(red._potion_marker.text == "十" and blue._potion_marker.text == "滴", "红蓝药具有不同形状标识")
	var slot := HotbarSlot.new()
	add_child(slot)
	slot.entry = {"kind": "auto_potion", "id": "blue"}
	check(slot._potion_marker.text == "滴", "快捷栏自动蓝药也有标识")
	var before := red._potion_marker.get_theme_color("font_color")
	GameState.settings.colorblindMode = "friendly"
	EventBus.settings_changed.emit()
	check(red._potion_marker.get_theme_color("font_color") != before,
		"友好预设切换可见配色")
	check(SettingsRuntime.valid_choice("colorblindMode", "friendly") and not SettingsRuntime.valid_choice("colorblindMode", "unknown"),
		"预设枚举受存档校验")
	check(SaveManager._is_valid_save(SaveManager._collect()), "含新设置的存档结构有效")
	if failures.is_empty():
		print("PotionAccessibilityTest: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
