extends Control
## 如意压阵（工程 112）实机出图工具：窗口模式截两张图 —— 重铸面板、保星面板。
##
## 出图要回答的是「四格下拉 + 提示行塞进面板之后，面板还能不能看」：
##   · 有没有把价格行 / 按钮挤出视口；
##   · 四格下拉在同一行里会不会挤成看不清的宽度；
##   · 提示行换行后有没有压到下一块。
##
## 🔴 必须**窗口模式**运行：`--headless` 截出来是空图（08 坑清单的截图约定）。
## 🔴 用 `.tscn` 实例化而不是 `脚本.new()`：与 `RuneRerollTest` 的挂载方式一致，
##    出图看到的才是玩家真看到的那一份（坑 99 同族：少挂一层就少一堆默认样式）。
## 🔴 截**整个视口**而不是 `panel.get_rect()`：面板是空壳 Control，自身 `size` 恒为 0，
##    按它裁剪会得到 0×0 的图。
## 用法：/Applications/Godot.app/Contents/MacOS/Godot --path . tools/rune_reroll_preview.tscn

const OUT_REFORGE := "/tmp/rune_reroll_reforge.png"
const OUT_FUSION := "/tmp/rune_reroll_fusion.png"

var _panel: Control
var _bg: ColorRect
## 🔴 必须取**实际视口**尺寸，不能写死一个「我觉得够大」的数：
## 面板定位用的是 `get_viewport_rect()`，而浮窗可用区取的是宿主控件 `size`。
## 两者不一致时面板会被推到画面外（第一版写死 1440×900、实际视口 1280×800，
## 面板右边缘就在 1440 —— 截图里被切掉三分之一）。
var VIEW := Vector2(1280, 800)

func _ready() -> void:
	VIEW = get_viewport_rect().size
	size = VIEW
	_bg = ColorRect.new()
	_bg.color = Color("10151a")
	_bg.position = Vector2.ZERO
	_bg.size = VIEW
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	await get_tree().process_frame
	await _shot_reforge()
	await _shot_fusion()
	get_tree().quit(0)

# ---- ① 重铸面板：精炼四格 + 如意四格 ----

func _shot_reforge() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 900000
	GameState.inventory[0] = _make("c6_equip_necklace", 100)
	# 四档各来一堆：下拉里能同时看到「有货 / 没货」两种状态。
	GameState.inventory[1] = _rune("rune_iron", 12)
	GameState.inventory[2] = _rune("rune_jade", 7)
	GameState.inventory[3] = _rune("rune_gold", 4)
	GameState.inventory[4] = _rune("rune_diamond", 0)
	for i in range(4):
		GameState.inventory[5 + i] = _make("c6_equip_weapon", 100)
	_panel = (load("res://scenes/ui/ReforgePanel.tscn") as PackedScene).instantiate()
	add_child(_panel)
	_panel.set_open(true)
	await _settle(10)
	# 摆两枚金如意：让提示行真的显示「掷 N 次」，而不是空态。
	_panel._rune_choices[0] = "rune_gold"
	_panel._rune_choices[1] = "rune_gold"
	_panel._refresh_runes()
	await _settle(4)
	await _capture(OUT_REFORGE, "reforge")
	_panel.set_open(false)
	_panel.queue_free()
	await _settle(2)

# ---- ② 保星面板：材料两格 + 如意四格 ----

func _shot_fusion() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 900000
	var old_item := _make("c6_equip_weapon", 100)
	var new_item := _make("c6_equip_weapon", 110)
	old_item["star"] = Upgrade.max_star()
	GameState.inventory[0] = old_item
	GameState.inventory[1] = new_item
	GameState.inventory[2] = _rune("rune_iron", 12)
	GameState.inventory[3] = _rune("rune_jade", 7)
	GameState.inventory[4] = _rune("rune_gold", 4)
	GameState.inventory[5] = _rune("rune_diamond", 2)
	_panel = (load("res://scenes/ui/EquipmentFusionPanel.tscn") as PackedScene).instantiate()
	add_child(_panel)
	# `_mode` 必须在 `set_open` 之前定：如意区可见性与确认按钮文案都在 set_open 里分支。
	_panel._mode = EquipmentFusion.STAR_TRANSFER
	_panel.set_open(true)
	await _settle(8)
	# 直接灌预选，绕开拖拽载荷：出图只要「材料齐备时的样子」。
	_panel._selected[0] = old_item.duplicate(true)
	_panel._selected[1] = new_item.duplicate(true)
	_panel._refresh_slots()
	_panel._refresh_preview()
	await _settle(6)
	_panel._rune_choices[0] = "rune_diamond"
	_panel._rune_choices[1] = "rune_diamond"
	_panel._refresh_runes()
	await _settle(4)
	await _capture(OUT_FUSION, "fusion")
	_panel.set_open(false)
	_panel.queue_free()
	await _settle(2)

# ---- 助手 ----

func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame

## 数据驱动取模板，不写死等级前缀；与 `RuneRerollTest._make` 同口径。
func _make(item_id: String, level: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(item_id) + level
	if level > Balance.SOFTCAP_LEVEL:
		return ItemFactory.make_equip_exact(item_id, level, "legendary", rng)
	return ItemFactory.make_equip_roll(item_id, ItemFactory.tier_start_for_template(item_id),
		"legendary", rng)

func _rune(rune_id: String, count: int) -> Dictionary:
	return {"kind": "rune", "itemId": rune_id, "count": count}

## 出图必须带数字：光看截图分不清「裁切框小了」和「控件真的溢出面板」。
## 这里把面板框、内容区、如意行、每个下拉的真实矩形都打出来。
func _dump_layout(tag: String) -> void:
	var frame := Rect2()
	if _panel.get("_box") != null:
		var box_ctrl = _panel.get("_box")
		if box_ctrl is Control:
			frame = (box_ctrl as Control).get_global_rect()
	print("[layout:%s] viewport=%s panel_frame=%s" % [tag, get_viewport_rect().size, frame])
	if _panel.get("_content") != null and _panel.get("_content") is Control:
		var content := _panel.get("_content") as Control
		print("[layout:%s] content rect=%s min=%s" % [tag, content.get_global_rect(),
			content.get_combined_minimum_size()])
	if _panel.get("_rune_row") != null and _panel.get("_rune_row") is Control:
		var row := _panel.get("_rune_row") as Control
		print("[layout:%s] rune_row rect=%s min=%s" % [tag, row.get_global_rect(),
			row.get_combined_minimum_size()])
	var pickers: Array = _panel.get("_rune_pickers")
	for i in range(pickers.size()):
		var ctrl := pickers[i] as Control
		print("[layout:%s]   picker[%d] rect=%s min=%s" % [tag, i, ctrl.get_global_rect(),
			ctrl.get_combined_minimum_size()])

## 面板里的可视内容包围盒。
## 🔴 面板脚本本身是空壳 Control（`size` 恒 0），按它居中/裁剪会得到 0×0 的图（坑 99）。
func _panel_box() -> Rect2:
	var box := Rect2()
	var first := true
	for child in _panel.get_children():
		if not child is Control:
			continue
		var ctrl := child as Control
		if not ctrl.is_visible_in_tree():
			continue
		var rect := ctrl.get_global_rect()
		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			continue
		# 跳过铺满全屏的那层压暗遮罩：它一进包围盒，裁出来的就是整屏（等于没裁）。
		if rect.size.x >= VIEW.x * 0.9 and rect.size.y >= VIEW.y * 0.9:
			continue
		box = rect if first else box.merge(rect)
		first = false
	return box

## 截「面板包围盒外扩 30px」，而不是整屏：重铸/合成面板在游戏里靠右（左半屏留给背包），
## 整屏截会把面板切在画面外。外扩是给左上角折角与描边留位置，贴着内容裁会切掉半个字。
func _capture(path: String, tag: String = "") -> void:
	await RenderingServer.frame_post_draw
	_dump_layout(tag)
	var image := get_viewport().get_texture().get_image()
	var box := _panel_box()
	if box.size.x > 1.0 and box.size.y > 1.0:
		var margin := 30
		var start := Vector2i((box.position - Vector2(margin, margin)).floor())
		var end := Vector2i((box.position + box.size + Vector2(margin, margin)).ceil())
		start = start.clamp(Vector2i.ZERO, image.get_size())
		end = end.clamp(Vector2i.ZERO, image.get_size())
		if end.x > start.x and end.y > start.y:
			image = image.get_region(Rect2i(start, end - start))
	image.save_png(path)
	print("[rune_reroll_preview] saved ", path, " ", image.get_size(), " box=", box)
