extends Control
## 仓库兑换台预览（工程 109）：窗口模式截一张 1280×720 的实机排版图。
##
## 🔴 必须**窗口模式**运行：`--headless` 截出来是空图（见 08 坑清单的截图约定）。
## 用法：/Applications/Godot.app/Contents/MacOS/Godot --path . tools/gold_exchange_preview.tscn
## 产物：/tmp/warehouse_exchange_preview.png

const OUT := "/tmp/warehouse_exchange_preview.png"

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	GameState.reset_to_defaults()
	GameState.gold = 12345678
	GameState.warehouse[0] = {"kind": "misc", "itemId": "gold_ingot", "count": 42}
	GameState.warehouse[1] = {"kind": "misc", "itemId": "gold_brick", "count": 7}
	GameState.warehouse[2] = {"kind": "misc", "itemId": "misc_firework", "count": 3}
	var panel: Control = preload("res://scripts/ui/warehouse_panel.gd").new()
	add_child(panel)
	await get_tree().process_frame
	EventBus.warehouse_panel_requested.emit("杜仓")
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(OUT)
	print("[gold_exchange_preview] saved ", OUT, " ", image.get_size())
	get_tree().quit(0)
