extends Node
## 车夫面板视觉验收工具（开发期，M3-2；M5 随其他测试工具一并清理）：
## ① **营地车夫**：1 条线路（试炼野外 · 免费）；
## ② **灰烬之地车夫**：2 条线路（试炼野外 50 / 腐化源头 100），金币给 60 →
##    验证「50 可点、100 禁用（金币不足）」两态渲染。
## 运行（需开窗，非 headless）：
##   GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##   "$GODOT" --path . res://tests/CarterShot.tscn

func _ready() -> void:
	GameState.reset_to_defaults()
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(20):
		await get_tree().process_frame

	var panel: Control = main.get_node("UI/CarterPanel")

	# ① 营地车夫
	EventBus.carter_panel_requested.emit("车夫")
	for _i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/degenerateage_carter_camp.png")
	print("[CarterShot] ① 营地车夫 → /tmp/degenerateage_carter_camp.png（线路数=%d）" % _row_count(panel))

	# ② 灰烬之地车夫（金币 60 → 50 可点 / 100 禁用）
	panel.set_open(false)
	GameState.current_map = "ash_land"
	EventBus.map_changed.emit("ash_land")   # 让 HUD 地图名同步（真实切图会走同样信号）
	GameState.add_gold(60)                  # 走正规入口（emit gold_changed，HUD 金币同步）
	await get_tree().process_frame
	EventBus.carter_panel_requested.emit("车夫")
	for _i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img2: Image = get_viewport().get_texture().get_image()
	img2.save_png("/tmp/degenerateage_carter_ash.png")
	print("[CarterShot] ② 灰烬之地车夫（金 60）→ /tmp/degenerateage_carter_ash.png（线路数=%d，可见=%s）" % [
		_row_count(panel), str(panel.visible)])

	get_tree().quit()

## 面板内线路行数（VBoxContainer 的子节点数）。
func _row_count(panel: Control) -> int:
	var vbox = panel.get("_list")
	if vbox is Node:
		return (vbox as Node).get_child_count()
	return -1
