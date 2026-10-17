extends Node
## M4-6：旧档迁移、改键冲突交换与运行时 InputMap 回归。不写玩家存档。

func _ready() -> void:
	GameState.reset_to_defaults()
	var inventory_key := SettingsRuntime.default_key("panel_inventory")
	var character_key := SettingsRuntime.default_key("panel_character")
	_check(inventory_key > 0 and character_key > 0, "项目默认快捷键可读")
	_check(SettingsRuntime.set_binding("panel_inventory", character_key), "改键操作成功")
	_check(SettingsRuntime.key_for("panel_inventory") == character_key, "目标键位即时生效")
	_check(SettingsRuntime.key_for("panel_character") == inventory_key, "冲突键位交换")
	_check(_map_key("panel_inventory") == character_key, "InputMap 已应用新键位")
	var data := SaveManager._collect()
	_check(SaveManager._is_valid_save(data), "新设置可以存档")
	data["schemaVersion"] = 4
	for key in ["musicVolume", "screenShake", "strongFlash", "textScale", "fullscreen", "resolution", "qualityFilter", "keyBindings",
		"mapScale", "displayScaleMode", "displayScale"]:
		data.settings.erase(key)
	_check(not SaveManager._is_valid_save(data), "装备模型升级后 v4 旧档明确拒绝")
	var migrated := SaveManager._migrate(data)
	_check(migrated.schemaVersion == SaveManager.CURRENT_SCHEMA and migrated.settings.has("keyBindings")
		and HotbarConfig.valid_layout(migrated.hotbar), "v4 设置与快捷栏补齐并迁移到当前版本")
	_check(is_equal_approx(float(migrated.settings.get("mapScale", -1.0)), 1.0)
		and String(migrated.settings.get("displayScaleMode", "")) == "auto"
		and is_equal_approx(float(migrated.settings.get("displayScale", -1.0)), 1.0),
		"M5-9c：显示三键缺键应补默认值（无需 schema 升级）")
	var bad := migrated.duplicate(true)
	bad.settings.keyBindings = {"panel_inventory": -1}
	_check(not SaveManager._is_valid_save(bad), "非法键位被拒绝")
	# M5-9c 回归（实测事故）：**当前版本**档缺新增设置键时仍必须可读 ——
	# 事故形态：9c 给 default_settings() 加键后，启动续档报「槽 1 主档不可用」，
	# 根因是 _migrate 原先只在 v < CURRENT_SCHEMA 时补设置键，而校验按 default_settings() 逐键查。
	var current := SaveManager._collect()
	current["schemaVersion"] = SaveManager.CURRENT_SCHEMA
	current.settings.erase("mapScale")
	current.settings.erase("displayScaleMode")
	current.settings.erase("displayScale")
	_check(SaveManager._is_valid_save(current), "当前版本档缺新增设置键仍应有效")
	var refilled := SaveManager._migrate(current)
	_check(is_equal_approx(float(refilled.settings.get("mapScale", -1.0)), 1.0)
		and String(refilled.settings.get("displayScaleMode", "")) == "auto"
		and is_equal_approx(float(refilled.settings.get("displayScale", -1.0)), 1.0),
		"当前版本档缺键应补齐默认值")
	# 补齐只填缺键，不得覆盖存档已有值、不得丢弃未知键
	current = SaveManager._collect()
	current["schemaVersion"] = SaveManager.CURRENT_SCHEMA
	current.settings.erase("displayScale")
	current.settings["displayScaleMode"] = "manual"
	current.settings["unknownFutureKey"] = 7
	refilled = SaveManager._migrate(current)
	_check(String(refilled.settings.get("displayScaleMode", "")) == "manual"
		and is_equal_approx(float(refilled.settings.get("displayScale", -1.0)), 1.0)
		and int(refilled.settings.get("unknownFutureKey", 0)) == 7,
		"补齐只填缺键：已有值与未知键均保留")
	GameState.settings = migrated.settings
	SettingsRuntime.apply_all()
	_check(_map_key("panel_inventory") == inventory_key, "读取旧档恢复默认键位")
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(screen)
	GameState.settings["uiScale"] = 1.5
	GameState.settings["musicVolume"] = 0.4
	SettingsRuntime.apply_all()
	_check(is_equal_approx(ui.transform.x.x, 1.5), "UI 缩放即时生效")
	_check(screen.size.is_equal_approx(get_viewport().get_visible_rect().size / 1.5),
		"UI 根尺寸随缩放调整：实际 %s 视口 %s" % [screen.size, get_viewport().get_visible_rect().size])
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Music")), 0.4), "音乐音量即时生效")
	var font_probe := Label.new()
	font_probe.add_theme_font_size_override("font_size", 16)
	ui.add_child(font_probe)
	GameState.settings["uiScale"] = 1.5
	GameState.settings["textScale"] = 1.5
	GameState.settings["displayScaleMode"] = "manual"
	GameState.settings["displayScale"] = 1.5
	SettingsRuntime.apply_ui_scale_to(ui)
	SettingsRuntime.apply_text_scale_to(ui)
	_check(absf(float(font_probe.get_theme_font_size("font_size")) * ui.transform.x.x - 16.0 * 2.25) <= 1.0,
		"界面/文字/手动适配均 150% 时，最终文字应为 225% 而非重复叠乘")
	GameState.settings["displayScaleMode"] = "auto"
	GameState.settings["displayScale"] = 1.0
	GameState.settings["uiScale"] = 2.0
	GameState.settings["mapScale"] = 2.0
	GameState.settings["textScale"] = 2.0
	SettingsRuntime.apply_ui_scale_to(ui)
	SettingsRuntime.apply_text_scale_to(ui)
	_check(is_equal_approx(ui.transform.x.x, 2.0)
		and absf(float(font_probe.get_theme_font_size("font_size")) * ui.transform.x.x - 32.0) <= 1.0
		and is_equal_approx(SettingsRuntime.world_text_scale_value(), 1.0),
		"界面/地图/文字均 200% 时，最终字体为 200%，世界文字不重复放大")
	GameState.settings["textScale"] = 1.0
	GameState.settings["mapScale"] = 1.0
	font_probe.queue_free()
	# M5-9d：界面大小上限开到 200%（大窗口 + 200% ⇒ 逻辑视口回到设计基准尺寸）
	GameState.settings["uiScale"] = 2.0
	SettingsRuntime.apply_ui_scale_to(ui)
	_check(is_equal_approx(ui.transform.x.x, 2.0), "uiScale=2.0 应生效（M5-9d 上限 2.0）")
	GameState.settings["uiScale"] = 1.0
	SettingsRuntime.apply_ui_scale_to(ui)
	_check(SettingsRuntime.valid_choice("resolution", "1920x1200")
		and not SettingsRuntime.valid_choice("resolution", "2560x1440"),
		"1920×1200 窗口档位应被接受、未登记档位应被拒绝")
	await _check_visual_tab()
	await _check_controls_tab()
	await _check_panels_matrix()
	await _check_embedded_resize()
	_check_display_preferences()
	_check_dialog_scale()
	print("[SettingsTest] 全部通过 ✅")
	get_tree().quit()

func _check_controls_tab() -> void:
	var panel: Control = (load("res://scenes/ui/SettingsPanel.tscn") as PackedScene).instantiate()
	add_child(panel)
	panel.set_open(true)
	var controls := _find_by_name(panel, "控制") as ScrollContainer
	_check(controls != null, "设置面板应含「控制」页")
	if controls == null:
		panel.queue_free()
		return
	var tabs := controls.get_parent() as TabContainer
	tabs.current_tab = controls.get_index()
	await get_tree().process_frame
	var rows := panel._key_list as VBoxContainer
	var first_row := rows.get_child(0) as HBoxContainer
	var key_button := first_row.get_child(1) as Button
	_check(rows.get_parent() == controls.get_child(0) and rows.get_child_count() == SettingsRuntime.ACTIONS.size()
		and key_button.is_visible_in_tree() and key_button.size.y > 0,
		"改键列表应在控制页展开且按钮可见")
	var original := SettingsRuntime.key_for("move_up")
	var replacement := KEY_F12
	_check(SettingsRuntime.action_for_key(replacement).is_empty(), "测试改键用键应未被占用")
	key_button.pressed.emit()
	_check(panel._capture_action == "move_up", "点击键位按钮应进入等待按键状态")
	var event := InputEventKey.new()
	event.physical_keycode = replacement
	event.pressed = true
	panel._input(event)
	await get_tree().process_frame
	_check(SettingsRuntime.key_for("move_up") == replacement and
		(rows.get_child(0).get_child(1) as Button).text == "F12", "控制页改键应即时生效并刷新显示")
	SettingsRuntime.set_binding("move_up", original)
	panel.set_open(false)
	panel.queue_free()
	await get_tree().process_frame

func _check_display_preferences() -> void:
	var path := SettingsRuntime.DISPLAY_PREFS_PATH
	var had_file := FileAccess.file_exists(path)
	var old_contents := FileAccess.get_file_as_string(path) if had_file else ""
	var old_settings := GameState.settings.duplicate(true)
	GameState.settings["uiScale"] = 1.75
	GameState.settings["mapScale"] = 1.25
	GameState.settings["textScale"] = 2.0
	_check(SettingsRuntime.save_display_preferences(true), "显示偏好应独立保存")
	GameState.reset_to_defaults()
	_check(is_equal_approx(float(GameState.settings.uiScale), 1.75)
		and is_equal_approx(float(GameState.settings.mapScale), 1.25)
		and is_equal_approx(float(GameState.settings.textScale), 2.0),
		"重新初始化时应从独立偏好恢复显示倍率")
	_check(ThemeDB.get_project_theme().get_font_size("font_size", "TooltipLabel") == 32,
		"背包装备等原生悬浮提示应跟随文字倍率")
	var slot_data := SaveManager._collect()
	slot_data.settings.uiScale = 1.0
	slot_data.settings.mapScale = 1.0
	slot_data.settings.textScale = 1.0
	SaveManager.apply_to_game_state(slot_data)
	_check(is_equal_approx(float(GameState.settings.uiScale), 1.75)
		and is_equal_approx(float(GameState.settings.mapScale), 1.25)
		and is_equal_approx(float(GameState.settings.textScale), 2.0),
		"读取另一个角色槽时不应覆盖本机显示偏好")
	if had_file:
		var original := FileAccess.open(path, FileAccess.WRITE)
		if original != null:
			original.store_string(old_contents)
	else:
		DirAccess.remove_absolute(path)
	GameState.settings = old_settings
	SettingsRuntime.apply_all()

## M5-9d：设置面板「画面」页新控件自洽（档位清单 + 显示适配两模式 + 选档即写设置）。
func _check_visual_tab() -> void:
	var panel: Control = (load("res://scenes/ui/SettingsPanel.tscn") as PackedScene).instantiate()
	add_child(panel)
	await get_tree().process_frame
	# ⚠ 面板是代码逐层建的；代码创建的控件入树后名字是 "@类型@N" 自动名（TabContainer 也是），
	# 只有 `_tab()` 显式设过名的页容器才是真名 ⇒ 直接找「画面」页，不经过 TabContainer。
	var visual_tab := _find_by_name(panel, "画面") as ScrollContainer
	var visual: VBoxContainer = visual_tab.get_child(0) as VBoxContainer if visual_tab != null else null
	_check(visual != null, "设置面板应含「画面」页")
	if visual == null:
		panel.queue_free()
		return
	_check(visual_tab.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"设置页应纵向滚动，避免高倍率下横向溢出")
	var tabs := visual_tab.get_parent() as TabContainer
	var tab_bar := tabs.get_tab_bar()
	var old_ui := float(GameState.settings.get("uiScale", 1.0))
	var old_text := float(GameState.settings.get("textScale", 1.0))
	GameState.settings["uiScale"] = 1.5
	GameState.settings["textScale"] = 1.0
	SettingsRuntime.apply_text_scale_to(panel)
	var base := int(tab_bar.get_meta("base_font_size", 0))
	var small := tab_bar.get_theme_font_size("font_size")
	GameState.settings["textScale"] = 1.5
	SettingsRuntime.apply_text_scale_to(panel)
	var large := tab_bar.get_theme_font_size("font_size")
	_check(base > 0 and small == maxi(9, roundi(float(base) / 1.5)) and large == base and large > small,
		"选项卡标题字体应随文字倍率变化，且与界面倍率不重复叠乘（base=%d small=%d large=%d）" % [base, small, large])
	GameState.settings["uiScale"] = old_ui
	GameState.settings["textScale"] = old_text
	SettingsRuntime.apply_text_scale_to(panel)
	# 收集「标签行 → 下拉」：manual_row 里只有 HSlider 无 OptionButton，天然被跳过
	var dropdowns := {}
	for row in visual.get_children():
		if row is HBoxContainer:
			var options: OptionButton = null
			for node in row.get_children():
				if node is OptionButton:
					options = node as OptionButton
			if options != null and row.get_child(0) is Label:
				dropdowns[String((row.get_child(0) as Label).text)] = options
	_check(dropdowns.has("界面大小") and dropdowns.has("地图显示大小") and dropdowns.has("文字大小")
		and dropdowns.has("显示适配"), "画面页应有 界面/地图/文字/显示适配 四个档位行")
	if dropdowns.has("界面大小"):
		var items := _option_texts(dropdowns["界面大小"])
		_check(items == ["80%", "100%", "125%", "150%", "175%", "200%"],
			"界面大小档位应为 80/100/125/150/175/200，实际 %s" % str(items))
	if dropdowns.has("地图显示大小"):
		var items := _option_texts(dropdowns["地图显示大小"])
		_check(items == ["80%", "100%", "125%", "150%", "175%", "200%"],
			"地图显示大小档位应为 80/100/125/150/175/200，实际 %s" % str(items))
	if dropdowns.has("文字大小"):
		var items := _option_texts(dropdowns["文字大小"])
		_check(items == ["100%", "110%", "125%", "150%", "175%", "200%"],
			"文字大小档位应为 100/110/125/150/175/200，实际 %s" % str(items))
	if dropdowns.has("显示适配"):
		var mode: OptionButton = dropdowns["显示适配"]
		_check(mode.item_count == 2 and String(mode.get_item_text(0)).begins_with("自动"),
			"显示适配应有「自动 / 手动」两档")
		# 选「手动」⇒ 写 displayScaleMode 并显示系数行
		mode.select(1)
		mode.item_selected.emit(1)
		await get_tree().process_frame
		_check(String(GameState.settings.get("displayScaleMode", "")) == "manual", "选「手动」应写入 displayScaleMode")
		mode.select(0)
		mode.item_selected.emit(0)
		await get_tree().process_frame
		_check(String(GameState.settings.get("displayScaleMode", "")) == "auto", "选「自动」应写回 displayScaleMode")
	# 选 200% ⇒ uiScale=2.0 且即时应用（经 _changed → apply_all 链路）
	if dropdowns.has("界面大小"):
		var scale_options: OptionButton = dropdowns["界面大小"]
		scale_options.select(5)
		scale_options.item_selected.emit(5)
		await get_tree().process_frame
		_check(is_equal_approx(float(GameState.settings.get("uiScale", 0.0)), 2.0),
			"选 200% 档位应写 uiScale=2.0")
		_check(is_equal_approx((panel.get_parent().get_node_or_null("UI") as CanvasLayer).transform.x.x, 2.0),
			"选 200% 档位应即时应用到界面轴")
		GameState.settings["uiScale"] = 1.0
		SettingsRuntime.apply_all()
	for field in ["地图显示大小", "文字大小"]:
		if dropdowns.has(field):
			var options: OptionButton = dropdowns[field]
			options.select(options.item_count - 1)
			options.item_selected.emit(options.item_count - 1)
			await get_tree().process_frame
	_check(is_equal_approx(float(GameState.settings.get("mapScale", 0.0)), 2.0)
		and is_equal_approx(float(GameState.settings.get("textScale", 0.0)), 2.0)
		and is_equal_approx(SettingsRuntime.world_text_scale_value(), 1.0),
		"地图与文字选 200% 后应即时生效，世界字形不应重复放大")
	var scaled_save := SaveManager._collect()
	_check(SaveManager._is_valid_save(scaled_save)
		and is_equal_approx(float(SaveManager._migrate(scaled_save).settings.get("mapScale", 0.0)), 2.0)
		and is_equal_approx(float(SaveManager._migrate(scaled_save).settings.get("textScale", 0.0)), 2.0),
		"地图和文字 200% 设置应通过存档校验并在读取后保持")
	GameState.settings["mapScale"] = 1.0
	GameState.settings["textScale"] = 1.0
	SettingsRuntime.apply_all()
	GameState.settings.erase("displayScaleMode")
	panel.queue_free()
	await get_tree().process_frame

func _find_by_name(node: Node, name: String) -> Node:
	if String(node.name) == name:
		return node
	for child in node.get_children():
		var found := _find_by_name(child, name)
		if found != null:
			return found
	return null

func _option_texts(options: OptionButton) -> Array:
	var out := []
	for i in options.item_count:
		out.append(options.get_item_text(i))
	return out

## 控件是否完整落在逻辑视口内（含 1px 容差；坐标同为逻辑坐标口径）。
func _fits(control: Control, extent: Vector2) -> bool:
	if control == null:
		return false
	var rect := control.get_global_rect()
	return rect.position.x >= -1.0 and rect.position.y >= -1.0 \
		and rect.end.x <= extent.x + 1.0 and rect.end.y <= extent.y + 1.0

## F-P2-3：倍率矩阵补到上限组合（uiScale 200% × 手动显示系数 150% = 3.0）。
## 断言口径：含关闭键的标题行与面板本体完整落在逻辑视口内；超出的内容由面板内滚动条承载。
func _check_extreme_scale(ui: CanvasLayer, embedded: SubViewport) -> void:
	embedded.size = Vector2i(2280, 1425)
	GameState.settings["uiScale"] = 2.0
	GameState.settings["textScale"] = 1.5
	GameState.settings["mapScale"] = 1.0
	GameState.settings["displayScaleMode"] = "manual"
	GameState.settings["displayScale"] = 1.5
	SettingsRuntime.apply_ui_scale_to(ui)
	SettingsRuntime.apply_text_scale_to(ui)
	SettingsRuntime.apply_world_text_scale()
	EventBus.settings_changed.emit()
	await get_tree().process_frame
	var value := SettingsRuntime.ui_scale_value()
	_check(is_equal_approx(value, 3.0), "uiScale 200% × 显示系数 150% 应为 3.0 倍率，实际 %.2f" % value)
	var extent := Vector2(embedded.size) / value
	for name in ["InventoryPanel", "CharacterPanel", "SkillPanel", "MountPanel"]:
		var panel: Variant = ui.get_node_or_null(name)
		if panel == null:
			continue
		panel.set_open(true)
		await get_tree().process_frame
		var window: Variant = panel._center
		_check(_fits(window.panel_box, extent), "%s 面板本体应完整落在可见区域（倍率 3.0）" % name)
		_check(_fits(window.header, extent), "%s 含关闭键的标题行应完整落在可见区域（倍率 3.0）" % name)
		panel.set_open(false)
		await get_tree().process_frame
	var carter: Variant = ui.get_node_or_null("CarterPanel")
	if carter != null:
		carter.set_open(true)
		await get_tree().process_frame
		_check(_fits(carter._box, extent), "车夫面板应完整落在可见区域（倍率 3.0）")
		carter.set_open(false)
		await get_tree().process_frame
	var shop: Variant = ui.get_node_or_null("ShopPanel")
	if shop != null:
		shop._on_shop_requested("peddler_camp")
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_fits(shop._box, extent), "货郎面板应完整落在可见区域（倍率 3.0）")
		shop.set_open(false)
		await get_tree().process_frame
	# 复位为自动适配：后文仍按「窗口 / uiScale」这一不含显示系数的口径计算逻辑视口。
	GameState.settings["displayScaleMode"] = "auto"
	GameState.settings["displayScale"] = 1.0
	EventBus.settings_changed.emit()
	await get_tree().process_frame

## M5-9f（09-A §5）：逐面板复验 —— 在「窗口尺寸 × 界面倍率」矩阵下，UI 下全部控件根
## 四边贴合逻辑视口；HUD 四角锚点控件不越界；z_index 层级约定不变（面板 0 ＜ Toast 2048 ＜ 拖拽 4096）。
func _check_panels_matrix() -> void:
	GameState.reset_to_defaults()
	GameState.menu_mode = "world"
	GameState.clear_save_pos()
	var embedded := SubViewport.new()
	embedded.size = Vector2i(1280, 800)
	add_child(embedded)
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	embedded.add_child(main)
	for _i in range(5):
		await get_tree().process_frame
	var ui := main.get_node_or_null("UI") as CanvasLayer
	_check(ui != null, "Main.tscn 应含 UI CanvasLayer")
	if ui == null:
		embedded.queue_free()
		return
	var panels: Array[Control] = []
	for child in ui.get_children():
		if child is Control:
			panels.append(child as Control)
	# Hud + 14 面板 + DragLayer = 16；新增面板自动纳入本轮检查（下限断言，不锁死数量）
	_check(panels.size() >= 16, "UI 下控件应不少于 16 个（Hud + 14 面板 + DragLayer），实际 %d" % panels.size())
	var hud := ui.get_node_or_null("Hud") as Control
	var toast := _find_by_name(main, "ToastBox") as Control
	var drag := ui.get_node_or_null("DragLayer") as Control
	_check(toast != null and int(toast.z_index) == 2048, "ToastBox z_index 应为 2048")
	_check(drag != null and int(drag.z_index) == 4096, "DragLayer z_index 应为 4096")
	for panel in panels:
		if panel == drag:
			continue   # DragLayer 恒在最上（4096），本就是拖拽幽灵层，不参与「面板 0」断言
		if panel.name == "EquipmentConfirmation":
			_check(int(panel.z_index) == 4095, "换装确认层应在普通面板上、拖拽层下")
			continue
		_check(int(panel.z_index) == 0, "%s z_index 应为 0（面板不压 Toast / DragLayer）" % panel.name)
	for viewport_size in [Vector2i(1280, 800), Vector2i(1920, 1200), Vector2i(2280, 1425), Vector2i(1153, 721)]:
		embedded.size = viewport_size
		for factor in [0.8, 1.0, 1.5, 2.0]:
			var text_factor := 2.0 if viewport_size == Vector2i(2280, 1425) and factor == 2.0 else 1.5
			GameState.settings["uiScale"] = factor
			GameState.settings["textScale"] = text_factor
			GameState.settings["mapScale"] = 2.0 if text_factor == 2.0 else 1.0
			SettingsRuntime.apply_ui_scale_to(ui)
			SettingsRuntime.apply_text_scale_to(ui)
			SettingsRuntime.apply_world_text_scale()
			EventBus.settings_changed.emit()
			await get_tree().process_frame
			var logical: Vector2 = Vector2(viewport_size) / factor
			for panel in panels:
				_check(panel.size.is_equal_approx(logical),
					"%s 根尺寸应贴合逻辑视口 %s（uiScale=%.1f，窗口 %s），实际 %s" % [
						panel.name, str(logical), factor, str(viewport_size), str(panel.size)])
			if hud != null:
				var hp_text := hud.get_node_or_null("StatusPanel/HpText") as Label
				if hp_text != null:
					var effective_font: float = float(hp_text.get_theme_font_size("font_size")) * factor
					_check(absf(effective_font - 12.0 * text_factor) <= factor,
						"血条文字最终大小应只跟随文字倍率 %.1f，实际 %.1f" % [text_factor, effective_font])
				var map_panel := hud.get_node_or_null("MapPanel") as Control
				var hotbar := hud.get_node_or_null("Hotbar") as Control
				if map_panel != null:
					_check(map_panel.position.x >= 0 and map_panel.position.x + map_panel.size.x <= logical.x + 1,
						"小地图留在可见宽度内（%.1f @ %s）" % [factor, str(viewport_size)])
				if hotbar != null:
					_check(hotbar.position.y >= 0 and hotbar.position.y + hotbar.size.y <= logical.y + 1,
						"快捷栏留在可见高度内（%.1f @ %s）" % [factor, str(viewport_size)])
			var settings := ui.get_node_or_null("SettingsPanel") as Control
			if settings != null:
				settings.set_open(true)
				await get_tree().process_frame
				var content: Control = settings._layout_root.get_parent().get_parent()
				_check(content.global_position.x >= -1 and content.global_position.y >= -1
					and content.global_position.x + content.size.x <= logical.x + 1
					and content.global_position.y + content.size.y <= logical.y + 1,
					"设置窗口应完整落在可见区域（%.1f @ %s）：%s / %s" % [factor, str(viewport_size), content.global_position, content.size])
				settings.set_open(false)
			if viewport_size == Vector2i(2280, 1425) or viewport_size == Vector2i(1280, 800):
				for name in ["QuestPanel", "MapBigPanel", "WarehousePanel"]:
					var responsive := ui.get_node_or_null(name) as Control
					responsive.visible = true
					await get_tree().process_frame
					var boxes := responsive.find_children("*", "PanelContainer", true, false)
					var largest: Control = null
					for box in boxes:
						if box is Control and (largest == null or box.size.x * box.size.y > largest.size.x * largest.size.y):
							largest = box as Control
					_check(largest != null and largest.global_position.x >= -1 and largest.global_position.y >= -1
						and largest.global_position.x + largest.size.x <= logical.x + 1
						and largest.global_position.y + largest.size.y <= logical.y + 1,
						"%s 应完整落在可见区域（%.1f @ %s）：%s / 逻辑 %s" % [name, factor, viewport_size, largest.size, logical])
					responsive.visible = false
	await _check_extreme_scale(ui, embedded)
	# 新增文字应在入树后自动获得同一倍率，不依赖再次打开设置。
	GameState.settings["uiScale"] = 1.5
	GameState.settings["textScale"] = 1.5
	SettingsRuntime.apply_ui_scale_to(ui)
	var dynamic := Label.new()
	dynamic.add_theme_font_size_override("font_size", 12)
	toast.add_child(dynamic)
	await get_tree().process_frame
	_check(int(dynamic.get_theme_font_size("font_size")) == 12,
		"运行中新建提示不得与 150% UI 再次叠乘")
	dynamic.queue_free()
	# ⑥ 点击坐标一致（创意 09 §8-5「看到哪点到哪」）：把玩家移到一只怪旁，按怪物的**屏幕坐标**
	# 点选，各相机倍率下都应命中同一只 —— 屏幕↔世界映射随 zoom 正确变化（点击链全走
	# canvas transform，见 game.gd::enemy_at_screen / npc_at_screen / request_map_move）。
	var game_node := main.get_node_or_null("Game") as Node2D
	var cam := main.get_node_or_null("Game/Entities/Player/Camera2D") as Camera2D
	var player := main.get_node_or_null("Game/Entities/Player") as Node2D
	var target: Node2D = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D and (e as Node2D).is_visible_in_tree():
			target = e as Node2D
			break
	if game_node != null and cam != null and player != null:
		_check(target != null, "营地（初始图）应有可见敌人，否则点击复验空转")
	if game_node != null and cam != null and player != null and target != null:
		# 关平滑求确定性（8.0 的平滑速度在 1 帧内赶不完传送距离，会留下几个像素的残差）
		var smoothing := cam.position_smoothing_enabled
		cam.position_smoothing_enabled = false
		player.global_position = target.global_position + Vector2(48.0, 0.0)
		cam.reset_smoothing()
		await get_tree().process_frame
		var npc_target: Npc = null
		var npcs_node := main.get_node_or_null("Game/Npcs")
		if npcs_node != null:
			for n in npcs_node.get_children():
				if n is Npc:
					npc_target = n as Npc
					break
		for factor in [1.0, 0.8, 1.5]:
			GameState.settings["mapScale"] = factor
			SettingsRuntime.apply_map_scale_to(cam)
			cam.reset_smoothing()
			await get_tree().process_frame
			# 敌人在世界坐标不动 ⇒ 屏幕坐标随 zoom 变；按屏幕坐标点选应命中同一敌人
			var screen_pos: Vector2 = target.get_global_transform_with_canvas().origin
			var hit: Node2D = game_node.enemy_at_screen(screen_pos)
			_check(hit == target,
				"地图倍率 %.1f 下按屏幕坐标应点选到同一怪物（看到哪点到哪）" % factor)
			# NPC 点选同理（contains_screen_point 路径；npc_at_screen 不过滤可见性，营地必有 NPC）
			if npc_target != null:
				var npc_screen: Vector2 = npc_target.get_global_transform_with_canvas().origin
				var npc_hit: Npc = game_node.npc_at_screen(npc_screen)
				_check(npc_hit == npc_target,
					"地图倍率 %.1f 下按屏幕坐标应点选到同一 NPC" % factor)
		cam.position_smoothing_enabled = smoothing
	GameState.settings["uiScale"] = 1.0
	GameState.settings["textScale"] = 1.0
	GameState.reset_to_defaults()
	embedded.queue_free()
	await get_tree().process_frame

## M5-9g：界面倍率必须同时作用于 Window 类弹层（FileDialog 走独立视口，不吃 CanvasLayer 变换）。
## 见工程文档《存档导出文件选择器高分屏缩放修正》。
func _check_dialog_scale() -> void:
	var design := Vector2i(760, 520)
	var viewport_size := Vector2i(1280, 800)
	GameState.settings["displayScaleMode"] = "auto"
	GameState.settings["displayScale"] = 1.0
	GameState.settings["uiScale"] = 1.0
	_check(SettingsRuntime.dialog_popup_size(Vector2(viewport_size), design) == design,
		"界面 100% 时弹层尺寸应与设计尺寸一致")
	for factor in [1.5, 2.0]:
		GameState.settings["uiScale"] = factor
		var zoomed := SettingsRuntime.dialog_popup_size(Vector2(viewport_size), design)
		_check(zoomed.x > design.x and zoomed.y > design.y,
			"界面 %.0f%% 时弹层应随之放大，实际 %s" % [factor * 100.0, str(zoomed)])
		_check(zoomed.x <= viewport_size.x and zoomed.y <= viewport_size.y,
			"放大后弹层不得超过游戏窗口，实际 %s" % str(zoomed))
		# 内容缩放与视口尺寸必须同倍率：弹层内可用设计空间 = 尺寸 / 倍率
		var design_space: Vector2 = Vector2(zoomed) / float(factor)
		_check(design_space.x <= design.x + 0.6 and design_space.y <= design.y + 0.6,
			"弹层内设计空间不得大于设计尺寸（界面 %.0f%%，实际 %s）" % [factor * 100.0, str(design_space)])
	# 窗口相对变小时按可用设计空间收缩，绝不溢出到屏幕外。
	var small := Vector2i(800, 600)
	var shrunk := SettingsRuntime.dialog_popup_size(Vector2(small), design)
	_check(shrunk.x <= small.x and shrunk.y <= small.y, "小窗口高倍率下弹层仍不得溢出，实际 %s" % str(shrunk))
	var dialog := FileDialog.new()
	add_child(dialog)
	SettingsRuntime.apply_ui_scale_to_window(dialog)
	_check(dialog.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		and is_equal_approx(dialog.content_scale_factor, 2.0),
		"弹层应启用内容缩放并按界面倍率取值，实际 mode=%d factor=%.2f" % [dialog.content_scale_mode, dialog.content_scale_factor])
	dialog.queue_free()
	# 弹层内部的子弹层（真 FileDialog 的覆盖确认 / 收藏夹菜单）也要吃到同一倍率，否则内部提示仍偏小。
	var outer := Window.new()
	add_child(outer)
	var inner := Window.new()
	outer.add_child(inner)
	SettingsRuntime.apply_ui_scale_to_window(outer)
	_check(inner.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		and is_equal_approx(inner.content_scale_factor, 2.0),
		"弹层内部子弹层应一并吃到界面倍率，实际 mode=%d factor=%.2f" % [inner.content_scale_mode, inner.content_scale_factor])
	outer.queue_free()
	GameState.settings["uiScale"] = 1.0

func _check_embedded_resize() -> void:
	var embedded := SubViewport.new()
	embedded.size = Vector2i(1153, 721)
	add_child(embedded)
	var layer := CanvasLayer.new()
	embedded.add_child(layer)
	var hud: Control = (load("res://scenes/ui/Hud.tscn") as PackedScene).instantiate()
	layer.add_child(hud)
	for viewport_size in [Vector2i(1153, 721), Vector2i(1387, 867)]:
		embedded.size = viewport_size
		for factor in [1.0, 1.5]:
			GameState.settings["uiScale"] = factor
			SettingsRuntime.apply_ui_scale_to(layer)
			await get_tree().process_frame
			var logical: Vector2 = Vector2(viewport_size) / factor
			_check(hud.size.is_equal_approx(logical), "HUD 根尺寸跟随游戏 Viewport")
			var map_panel := hud.get_node("MapPanel") as Control
			var hotbar := hud.get_node("Hotbar") as Control
			_check(map_panel.position.x >= 0 and map_panel.position.x + map_panel.size.x <= logical.x + 1,
				"小地图留在可见宽度内")
			_check(hotbar.position.y >= 0 and hotbar.position.y + hotbar.size.y <= logical.y + 1,
				"快捷栏留在可见高度内")
	embedded.queue_free()

func _map_key(action: String) -> int:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return int((event as InputEventKey).physical_keycode)
	return 0

func _check(ok: bool, message: String) -> void:
	if not ok:
		push_error("[SettingsTest] 失败：" + message)
		get_tree().quit(1)
