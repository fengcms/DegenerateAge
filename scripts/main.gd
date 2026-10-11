extends Node2D
## 启动场景脚本（脚手架版）。
##
## 职责：验证工程骨架可用——数据层已加载、配置校验可通过。
## 正式的玩法（移动 / 战斗 / NPC / UI）将在阶段 1 之后逐步接入。

func _ready() -> void:
	print("========================================")
	print("[Main] 《末法纪元：最后的守护者》脚手架启动")
	print("[Main] 配置表加载摘要: ", DataLoader.get_summary())

	var report: Array[String] = DataLoader.validate_all()
	if report.is_empty():
		print("[Main] 配置校验通过 ✅")
	else:
		push_warning("[Main] 配置校验存在问题（%d 项）:\n%s" % [report.size(), "\n".join(PackedStringArray(report))])

	# 示例：读取一条怪物数据，验证数据层可用。
	var wolf = DataLoader.get_entry("monsters", "wolf_corrupted")
	if wolf != null:
		print("[Main] 示例读取 monster 'wolf_corrupted' -> ", wolf.get("name", "?"), " HP基础=", wolf.get("hpBase", "?"))
	print("========================================")
