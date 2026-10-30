extends Control
## 如意边框分色（工程 111）实机出图工具：窗口模式截两张图（全景 + 2 倍放大）。
##
## 内容是真实 `InventoryPanel` + 真实 `ItemSlot` + 真实图标，四档如意同屏。
## 这是「改完之后到底能不能一眼分开」的唯一证据 —— 单看色号没有意义，
## 因为 52px 格子里 1px 描边的实际观感与十六进制相差很远。
##
## 🔑 只出背包，**不出地面掉落**：`GroundItem._draw_label()` 第一行就是
## `if kind != "equip": return`，`_draw_quality_augment()` 同样只对装备生效 ——
## 如意掉在地上既不显示名字也没有光柱，那个场景看不出分色，出了图只会误导。
## 同理，玩家能在背包 / 仓库 / 货郎托盘三处看到效果，这三处同源（工程 111 §3）。
##
## 🔴 必须**窗口模式**运行：`--headless` 截出来是空图（08 坑清单的截图约定）。
## 用法：/Applications/Godot.app/Contents/MacOS/Godot --path . tools/rune_border_preview.tscn

const OUT_BAG := "/tmp/rune_accent_bag.png"
const OUT_BAG_ZOOM := "/tmp/rune_accent_bag_zoom.png"
const RUNES := ["rune_iron", "rune_jade", "rune_gold", "rune_diamond"]
const VIEW := Vector2(1280, 720)

var _panel: Control

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	size = Vector2(1280, 720)
	GameState.reset_to_defaults()
	# 四档如意放进背包最前四格；第 5 格放一件史诗装备做对照（它应当仍是黄框）。
	for i in range(RUNES.size()):
		GameState.inventory[i] = {"kind": "rune", "itemId": String(RUNES[i]), "count": 1}
	var probe_equip := _first_equip_id()
	if not probe_equip.is_empty():
		GameState.inventory[4] = {
			"kind": "equip", "itemId": probe_equip, "quality": "epic", "star": 9, "count": 1,
		}
	await get_tree().process_frame
	await _shot_bag()
	get_tree().quit(0)

# ---- ① 背包 ----

func _shot_bag() -> void:
	var bg := ColorRect.new()
	bg.color = Color("10151a")
	bg.position = Vector2.ZERO
	bg.size = VIEW
	add_child(bg)

	_panel = preload("res://scripts/ui/inventory_panel.gd").new()
	add_child(_panel)
	_panel.set_open(true)
	for i in range(6):
		await get_tree().process_frame
	# 🔑 面板脚本本身是**空壳 Control（size 恒为 0）**，可视内容全在它的子节点里，
	# 所以不能拿 `_panel.size` 去居中或裁剪 —— 那会得到 0×0 的裁图。
	# 取子节点包围盒才是真身。预览环境没有居中容器，只能手动摆。
	var box := _panel_box()
	print("[preview] panel box=", box)
	_panel.position = ((VIEW - box.size) * 0.5 - box.position).floor()
	await get_tree().process_frame
	await _capture(OUT_BAG)
	# 外扩 30px：面板的部分装饰（左上角折角、底部小菱形）画在内容包围盒之外，
	# 贴着 box 裁会把「整理」按钮和标题切掉半个字。
	var zoom_rect := Rect2i(Vector2i(_panel.position + box.position) - Vector2i(30, 30),
		Vector2i(box.size) + Vector2i(60, 60))
	await _capture_zoom(OUT_BAG_ZOOM, zoom_rect, 2)
	_panel.set_open(false)
	_panel.queue_free()
	await get_tree().process_frame

# ---- 助手 ----

## 面板里的可视内容包围盒（把子节点里的 Control 合并）。
## 面板脚本本身是空壳 Control（`size` 恒 0），拿它居中会得到 0×0。
func _panel_box() -> Rect2:
	var box := Rect2()
	var first := true
	for child in _panel.get_children():
		if not child is Control:
			continue
		var ctrl := child as Control
		if not ctrl.is_visible_in_tree():
			continue
		var rect := ctrl.get_rect()
		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			continue
		box = rect if first else box.merge(rect)
		first = false
	return box

## 取第一件真实装备模板做对照，不写死 id（数据改了也不会失效）。
func _first_equip_id() -> String:
	var table = DataLoader.tables.get("equipments", [])
	if table is Array and not (table as Array).is_empty():
		var first = (table as Array)[0]
		if first is Dictionary:
			return String((first as Dictionary).get("id", ""))
	return ""

func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("[rune_border_preview] saved ", path, " ", image.get_size())

## 裁一块区域放大另存：1px 描边在 1280 宽的整体图里肉眼难判，审阅要看放大图。
func _capture_zoom(path: String, rect: Rect2i, factor: int) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var region := image.get_region(rect)
	region.resize(rect.size.x * factor, rect.size.y * factor, Image.INTERPOLATE_NEAREST)
	region.save_png(path)
	print("[rune_border_preview] saved ", path, " ", region.get_size())
