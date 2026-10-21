extends Control
## 技能图鉴与有限升阶入口。已解锁技能可拖入快捷栏；购买按钮展示下一阶门槛与实际效果。
## 金币事件只刷新五个按钮的可用状态，避免挂机拾金时重建全部技能行。

var _center: FloatingWindow
var _upgrade_buttons: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
	EventBus.player_leveled.connect(_on_player_leveled)
	EventBus.skill_rank_changed.connect(_on_skill_rank_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.data_loaded.connect(_on_data_loaded)

## 角色升级后若面板可见，重建技能行以显示新解锁或新阶门槛。
func _on_player_leveled(_level: int) -> void:
	if visible:
		_refresh()

## 成功购买新阶后更新当前/下一阶说明；隐藏面板下次打开再建。
func _on_skill_rank_changed(_skill_id: String, _rank: int) -> void:
	if visible:
		_refresh()

## 金币变化频繁，只更新五个按钮灰态与原因，不重建图标和技能行。
func _on_gold_changed(_amount: int) -> void:
	if visible:
		_refresh_affordability()

## 编辑器或测试重载技能配置时刷新面板显示。
func _on_data_loaded() -> void:
	if visible:
		_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("panel_skill") and not event.is_echo():
		set_open(not visible)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		if not _center.is_top_window():
			return
		set_open(false)
		get_viewport().set_input_as_handled()

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open("skill", open)
	var hud := get_node_or_null("../Hud")
	if hud != null:
		hud.set_hotbar_drop_mode(open)
	if open:
		_refresh()
		EventBus.panel_opened.emit("skill")
		_center.show_window()

## 并开集合统一由 `GameState.panels_coexist`（F-P3-1）判定，本面板不再自带名单。
func _on_panel_opened(panel_id: String) -> void:
	if visible and not GameState.panels_coexist(panel_id, "skill"):
		set_open(false)

var _list: VBoxContainer

func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.42)
	dim.visible = false
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_center = FloatingWindow.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	var panel := PanelChrome.new()
	_center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	var title := Label.new()
	title.text = Localization.tr_key("ui.skill_panel.p001")
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	PanelChrome.style_title(title)
	var help := PanelHelpButton.new()
	help.tooltip_text = Localization.tr_key("ui.skill_panel.p003")
	head.add_child(help)
	PanelChrome.style_help(help)
	var close := Button.new()
	close.text = Localization.tr_key("ui.skill_panel.p002")
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)
	_center.setup(self, panel, head, Vector2(0.02, 0.18))
	root.add_child(PanelChrome.make_title_gap())

	# F-P2-3：标题行留在外框渐变带内，技能列表整体可滚动。
	var content_scroll := ScrollContainer.new()
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content_scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 560
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(content)
	_center.set_content_scroll(content_scroll)

	var section := Label.new()
	section.text = "可用技能"
	PanelChrome.style_section(section)
	content.add_child(section)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	content.add_child(_list)

## 每项技能沿用同一张低对比内容卡，保留原拖动按钮作为交互源。
func _new_skill_row() -> HBoxContainer:
	var row := PanelSkillRow.new()
	_list.add_child(row)
	return row

func _refresh() -> void:
	if _list == null:
		return
	_upgrade_buttons.clear()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var skills: Variant = DataLoader.get_table("skills")
	if not skills is Array:
		return
	for raw in skills:
		if not raw is Dictionary:
			continue
		var skill: Dictionary = raw
		var skill_id := String(skill.get("id", ""))
		var rank := GameState.skill_rank(skill_id)
		var max_rank := SkillProgression.max_rank(skill_id)
		var unlocked := rank > 0
		var wired := HotbarConfig.ACTIVE_SKILLS.has(skill_id)
		var row := _new_skill_row()
		row.custom_minimum_size.y = 96 if max_rank > 1 else 62
		var icon := SkillDragButton.new()
		icon.custom_minimum_size = Vector2(52, 52)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.text = String(skill.get("name", Localization.tr_key("ui.skill_panel.p001"))).substr(0, 2)
		icon.skill_id = skill_id
		icon.drag_label = String(skill.get("name", ""))
		SampleArt.decorate(icon, SampleArt.skill_icon(icon.skill_id))
		icon.add_theme_constant_override("icon_max_width", 42)
		icon.disabled = not unlocked or not wired
		icon.tooltip_text = Localization.tr_key("ui.skill_panel.p004") if not icon.disabled else Localization.tr_key("ui.skill_panel.p005")
		row.add_child(icon)
		var desc := Label.new()
		desc.text = _skill_row_text(skill, rank, max_rank, unlocked and wired)
		desc.custom_minimum_size.x = 330 if max_rank > 1 else 430
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_color_override("font_color", PanelChrome.TEXT)
		row.add_child(desc)
		if max_rank > 1:
			var upgrade := Button.new()
			upgrade.name = "Upgrade_" + skill_id
			upgrade.text = Localization.tr_key("ui.skill_panel.upgrade")
			upgrade.custom_minimum_size.x = 84
			upgrade.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			upgrade.pressed.connect(_on_upgrade_pressed.bind(skill_id))
			PanelChrome.style_action(upgrade)
			row.add_child(upgrade)
			_upgrade_buttons[skill_id] = upgrade
	for kind in ["red", "blue"]:
		var row := _new_skill_row()
		var button := SkillDragButton.new()
		button.custom_minimum_size = Vector2(52, 52)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.text = Localization.tr_key("ui.skill_panel.p006") if kind == "red" else Localization.tr_key("ui.skill_panel.p007")
		button.binding = {"kind": "auto_potion", "id": kind}
		SampleArt.decorate(button, SampleArt.binding_icon(button.binding))
		button.add_theme_constant_override("icon_max_width", 42)
		button.tooltip_text = Localization.tr_key("ui.skill_panel.p008")
		row.add_child(button)
		var desc := Label.new()
		desc.text = Localization.tr_key("ui.skill_panel.p009") % (Localization.tr_key("ui.skill_panel.p010") if kind == "red" else Localization.tr_key("ui.skill_panel.p011"))
		desc.custom_minimum_size.x = 380
		desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		desc.add_theme_color_override("font_color", PanelChrome.TEXT)
		row.add_child(desc)
	_refresh_affordability()

## 给玩家显示当前阶与下一阶的真实数值；基础描述仍保留在同一行。
func _skill_row_text(skill: Dictionary, rank: int, max_rank: int, can_use: bool) -> String:
	var sid := String(skill.get("id", ""))
	var status := Localization.tr_key("ui.skill.available") if can_use else Localization.tr_key("ui.skill.locked")
	var heading := Localization.tr_key("ui.skill_panel.rank_heading") % [
		String(skill.get("name", "")), int(skill.get("unlockLevel", 1)), status, rank, max_rank]
	var lines: Array[String] = [heading, String(skill.get("desc", ""))]
	if rank < 1:
		lines.append(Localization.tr_key("ui.skill_panel.unlock_hint") % int(skill.get("unlockLevel", 1)))
	else:
		var current := SkillProgression.resolve(sid, rank)
		var detail := Localization.tr_key("ui.skill_panel.current_effect") % _effect_summary(current)
		if rank < max_rank:
			var step := SkillProgression.step(sid, rank + 1)
			var next := SkillProgression.resolve(sid, rank + 1)
			detail += "\n" + (Localization.tr_key("ui.skill_panel.next_effect") % [
				_effect_summary(next), int(step.get("unlockLevel", 0)), int(step.get("goldCost", 0))])
		elif max_rank > 1:
			detail += " · " + Localization.tr_key("ui.skill_panel.max_rank")
		lines.append(detail)
	return "\n".join(PackedStringArray(lines))

## 统一格式化技能面板的实际伤害系数或 Buff 百分比。
func _effect_summary(skill: Dictionary) -> String:
	if String(skill.get("kind", "")) == "buff":
		var effects: Dictionary = skill.get("effects", {})
		return Localization.tr_key("ui.skill_panel.buff_effect") % [
			float(effects.get("attackPct", 0.0)) * 100.0,
			float(effects.get("attackSpeedPct", 0.0)) * 100.0]
	var hits := maxi(1, int(skill.get("hits", 1)))
	return Localization.tr_key("ui.skill_panel.attack_effect_multi") % [float(skill.get("coefficient", 0.0)), hits] if hits > 1 \
		else Localization.tr_key("ui.skill_panel.attack_effect") % float(skill.get("coefficient", 0.0))

## 按角色等级和金币刷新购买按钮；拾金频繁时不重建技能行。
func _refresh_affordability() -> void:
	for skill_id in _upgrade_buttons.keys():
		var button := _upgrade_buttons[skill_id] as Button
		if not is_instance_valid(button):
			continue
		var rank := GameState.skill_rank(String(skill_id))
		var step := SkillProgression.step(String(skill_id), rank + 1)
		var reason := ""
		if rank < 1:
			reason = Localization.tr_key("ui.skill_panel.reason_locked")
		elif step.is_empty():
			reason = Localization.tr_key("ui.skill_panel.max_rank")
		elif int(GameState.player.level) < int(step.get("unlockLevel", 0)):
			reason = Localization.tr_key("ui.skill_panel.reason_level") % int(step.unlockLevel)
		elif GameState.gold < int(step.get("goldCost", 0)):
			reason = Localization.tr_key("ui.skill_panel.reason_gold") % int(step.goldCost)
		button.disabled = not reason.is_empty()
		button.tooltip_text = reason if not reason.is_empty() else Localization.tr_key("ui.skill_panel.ready")

## 玩家点击升级时调用原子购买入口，成功后由阶数事件刷新面板和快捷栏。
func _on_upgrade_pressed(skill_id: String) -> void:
	var result := GameState.buy_skill_rank(skill_id)
	if bool(result.get("ok", false)):
		var skill: Dictionary = DataLoader.get_entry("skills", skill_id)
		EventBus.toast_requested.emit(Localization.tr_key("ui.skill_panel.success") % [
			String(skill.get("name", skill_id)), int(result.rank)], "info")
	else:
		var reason := String(result.get("reason", ""))
		EventBus.toast_requested.emit(_purchase_reason(reason, skill_id), "danger")

## 为极端状态变化或连续点击的失败结果给出与灰态一致的提示。
func _purchase_reason(reason: String, skill_id: String) -> String:
	var step := SkillProgression.step(skill_id, GameState.skill_rank(skill_id) + 1)
	match reason:
		"locked": return Localization.tr_key("ui.skill_panel.reason_locked")
		"max": return Localization.tr_key("ui.skill_panel.max_rank")
		"level": return Localization.tr_key("ui.skill_panel.reason_level") % int(step.get("unlockLevel", 0))
		"gold": return Localization.tr_key("ui.skill_panel.reason_gold") % int(step.get("goldCost", 0))
	return Localization.tr_key("ui.skill_panel.reason_unknown")
