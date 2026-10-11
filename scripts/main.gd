extends Node2D
## 启动引导：校验数据配置；游戏世界由子场景 Game 承载（M1 起）。

@onready var _info: Label = $UI/InfoLabel

func _ready() -> void:
	print("========================================")
	print("[Main] 《末法纪元：最后的守护者》启动")

	var report: Array[String] = DataLoader.validate_all()
	if report.is_empty():
		print("[Main] 配置校验通过 ✅")
	else:
		push_warning("[Main] 配置校验存在问题（%d 项）:\n%s" % [report.size(), "\n".join(PackedStringArray(report))])

	_info.text = "%s · WASD 移动（M1）" % _current_map_name()
	print("========================================")

func _current_map_name() -> String:
	var m = DataLoader.get_entry("maps", GameState.current_map)
	if m == null:
		return String(GameState.current_map)
	return String(m.get("name", GameState.current_map))
