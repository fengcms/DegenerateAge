extends Node
## M4-8 配置与存档回归；不写磁盘上的玩家存档。

var _errors: Array[String] = []

func _ready() -> void:
	GameState.reset_to_defaults()
	_check(HotbarConfig.valid_layout(GameState.hotbar), "默认布局有效")
	_check(GameState.hotbar[0].id == "red" and GameState.hotbar[2].id == "basic_slash", "默认红蓝药与普攻")
	_check(GameState.set_hotbar_entry(4, {"kind": "potion", "id": "potion_hp_small"}), "可绑定药品模板")
	_check(GameState.set_hotbar_entry(5, {"kind": "item", "id": "misc_town_scroll"}), "可绑定已接通卷轴")
	_check(GameState.swap_hotbar_entries(4, 5), "两格交换")
	_check(GameState.hotbar[4].id == "misc_town_scroll" and GameState.hotbar[5].id == "potion_hp_small", "交换后内容正确")
	_check(GameState.set_hotbar_entry(5, null) and GameState.hotbar[5] == null, "右键清空状态")
	_check(not GameState.set_hotbar_entry(6, {"kind": "item", "id": "misc_revive_scroll"}), "未接通卷轴不可绑定")
	_check(GameState.set_hotbar_entry(6, {"kind": "skill", "id": "earth_cleave"}), "裂地斩可绑定")
	var data := SaveManager._collect()
	_check(SaveManager._is_valid_save(data), "当前布局可写入存档")
	GameState.reset_to_defaults()
	SaveManager.apply_to_game_state(data)
	_check(GameState.hotbar[4].id == "misc_town_scroll", "读档恢复快捷栏")
	var old := data.duplicate(true)
	old.schemaVersion = 5
	old.erase("hotbar")
	_check(not SaveManager._is_valid_save(old), "装备模型升级后 v5 旧档拒绝")
	_check(GameState.hotbar[4].id == "misc_town_scroll", "拒绝旧档不改动当前快捷栏")
	var invalid := data.duplicate(true)
	invalid.hotbar[4] = {"kind": "item", "id": "misc_revive_scroll"}
	_check(not SaveManager._is_valid_save(invalid), "非法卷轴引用拒绝读档")
	invalid = data.duplicate(true)
	invalid.hotbar.pop_back()
	_check(not SaveManager._is_valid_save(invalid), "非 12 格布局拒绝读档")
	print("[HotbarConfigTest] ", "全部通过 ✅" if _errors.is_empty() else str(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_errors.append(message)
		push_error("[HotbarConfigTest] " + message)
