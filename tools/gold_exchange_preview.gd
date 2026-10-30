extends Control
## 仓库兑换台预览（工程 109 / 110）：窗口模式截 3 张 1280×720 实机排版图。
##
## 🔴 必须**窗口模式**运行：`--headless` 截出来是空图（见 08 坑清单的截图约定）。
## 用法：/Applications/Godot.app/Contents/MacOS/Godot --path . tools/gold_exchange_preview.tscn
## 产物：
##   /tmp/warehouse_exchange_preview.png       面板本体 + 兑换按钮行（109）
##   /tmp/warehouse_exchange_dialog.png        数量弹框常态：输入 100（110）
##   /tmp/warehouse_exchange_dialog_over.png   数量弹框超限禁用态（110）

const OUT_PANEL := "/tmp/warehouse_exchange_preview.png"
const OUT_DIALOG := "/tmp/warehouse_exchange_dialog.png"
const OUT_DIALOG_OVER := "/tmp/warehouse_exchange_dialog_over.png"

var _panel: Control

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	GameState.reset_to_defaults()
	# 1.2 亿：把「金币 → 金条」的可换次数顶到 123，才够演示输入 100 的常态。
	GameState.gold = 123456789
	GameState.warehouse[0] = {"kind": "misc", "itemId": "gold_ingot", "count": 42}
	GameState.warehouse[1] = {"kind": "misc", "itemId": "gold_brick", "count": 7}
	GameState.warehouse[2] = {"kind": "misc", "itemId": "misc_firework", "count": 3}
	# 🔑 必须等一帧让窗口尺寸生效，再挂面板：面板在 `_ready` 里按当时的父尺寸
	# 算 anchors，父还是 0×0 的话，它的 CenterContainer 会把面板与弹框都摆在左上角
	# （真机上面板挂在 CanvasLayer 下、尺寸已就绪，没有这个时序问题）。
	await get_tree().process_frame
	_panel = preload("res://scripts/ui/warehouse_panel.gd").new()
	add_child(_panel)
	# 预览环境里没有 Container 帮忙布局，`PRESET_FULL_RECT` 的 anchors 在根 Control 下
	# 不会自己撑开（实测 size 停在 0×0，面板靠内容溢出才画出来，弹框就贴左上）。
	# 这里直接按逻辑视口尺寸定死；真机上面板挂在 CanvasLayer 下，尺寸由场景给出。
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.size = get_viewport().get_visible_rect().size
	await get_tree().process_frame
	EventBus.warehouse_panel_requested.emit("杜仓")
	for i in range(4):
		await get_tree().process_frame
	await _shot(OUT_PANEL)

	# 弹框常态：输入 100（上限 123）
	_panel._on_exchange("gold_to_ingot")
	await get_tree().process_frame
	_type("100")
	await _shot(OUT_DIALOG)

	# 超限禁用态：输入 999 > 123
	_type("999")
	await _shot(OUT_DIALOG_OVER)

	get_tree().quit(0)

## 模拟玩家在输入框敲字。`LineEdit.set_text()` 不触发 `text_changed`，必须显式补发。
func _type(value: String) -> void:
	var dialog: PanelAmountDialog = _panel._amount_dialog
	dialog._edit.text = value
	dialog._edit.text_changed.emit(value)

func _shot(path: String) -> void:
	for i in range(3):
		await get_tree().process_frame
	print("[preview] root=", size, " panel=", _panel.size, " dialog=", _panel._amount_dialog.size,
		" viewport=", get_viewport().get_visible_rect().size)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("[gold_exchange_preview] saved ", path, " ", image.get_size())
