extends Control
## 技能图鉴与有限升阶入口。紧凑行卡只保留扫读信息，细节由结构化悬停浮层承载。
## 金币事件只刷新五个按钮的可用状态，避免挂机拾金时重建全部技能行。

class SkillUpgradeButton extends Button:
	## 升阶按钮与技能图标共用一张详情卡，灰态时仍可查原因。
	var skill_id := ""

	## Godot 原生悬停窗口每次创建一张临时卡片，关闭后由引擎释放。
	func _make_custom_tooltip(_for_text: String) -> Object:
		return SkillDetailTooltip.for_skill(skill_id) if not skill_id.is_empty() else null

var _center: FloatingWindow
var _upgrade_buttons: Dictionary = {}
var _potion_buttons: Dictionary = {}
var _cooldown_labels: Dictionary = {}
var _basic_interval_label: Label
var _cooldown_accumulator := 0.0

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

## 面板可见时约每 0.1 秒仅刷新六个图标上的倒计时，不重建技能行。
func _process(delta: float) -> void:
	if not visible:
		return
	_cooldown_accumulator += delta
	if _cooldown_accumulator < 0.1:
		return
	_cooldown_accumulator = 0.0
	_refresh_cooldowns()

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
		_refresh_cooldowns()
		EventBus.panel_opened.emit("skill")
		_center.show_window()

## 并开集合统一由 `GameState.panels_coexist`（F-P3-1）判定，本面板不再自带名单。
func _on_panel_opened(panel_id: String) -> void:
	if visible and not GameState.panels_coexist(panel_id, "skill"):
		set_open(false)

var _list: VBoxContainer
var _tools_row: HBoxContainer

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
	content.custom_minimum_size.x = 500
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(content)
	_center.set_content_scroll(content_scroll)

	var section := Label.new()
	section.text = Localization.tr_key("ui.skill_panel.available_section")
	PanelChrome.style_section(section)
	content.add_child(section)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	content.add_child(_list)
	var tools_section := Label.new()
	tools_section.text = Localization.tr_key("ui.skill_panel.tools_section")
	PanelChrome.style_section(tools_section)
	content.add_child(tools_section)
	_tools_row = PanelSkillRow.new()
	_tools_row.custom_minimum_size.y = 60
	content.add_child(_tools_row)
	_build_potion_tools()

## 每项技能沿用同一张低对比内容卡，保留原拖动按钮作为交互源。
func _new_skill_row() -> HBoxContainer:
	var row := PanelSkillRow.new()
	_list.add_child(row)
	return row

func _refresh() -> void:
	if _list == null:
		return
	_upgrade_buttons.clear()
	_cooldown_labels.clear()
	_basic_interval_label = null
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
		row.skill_id = skill_id
		row.tooltip_text = skill_id
		row.custom_minimum_size.y = 64
		var icon := SkillDragButton.new()
		icon.custom_minimum_size = Vector2(48, 48)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.text = String(skill.get("name", Localization.tr_key("ui.skill_panel.p001"))).substr(0, 2)
		icon.skill_id = skill_id
		icon.tooltip_skill_id = skill_id
		icon.drag_label = String(skill.get("name", ""))
		SampleArt.decorate(icon, SampleArt.skill_icon(icon.skill_id))
		icon.add_theme_constant_override("icon_max_width", 42)
		icon.disabled = not unlocked or not wired
		icon.tooltip_text = skill_id
		row.add_child(icon)
		var overlay := Label.new()
		overlay.name = "CooldownOverlay"
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_theme_font_size_override("font_size", 12)
		overlay.add_theme_color_override("font_color", Color("ffcb71"))
		overlay.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		overlay.add_theme_constant_override("outline_size", 2)
		icon.add_child(overlay)
		_cooldown_labels[skill_id] = overlay
		var summary := Label.new()
		summary.name = "Summary"
		summary.text = Localization.tr_key("ui.skill_panel.compact_rank") % [String(skill.get("name", "")), rank, max_rank] if unlocked else \
			Localization.tr_key("ui.skill_panel.compact_locked") % [String(skill.get("name", "")), int(skill.get("unlockLevel", 1))]
		summary.custom_minimum_size.x = 170
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		summary.add_theme_color_override("font_color", PanelChrome.TEXT if unlocked else PanelChrome.MUTED)
		summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(summary)
		var cooldown := Label.new()
		cooldown.name = "BaseCooldown"
		cooldown.text = Localization.tr_key("ui.skill_panel.basic_interval") if skill_id == "basic_slash" else \
			Localization.tr_key("ui.skill_panel.cooldown_badge") % float(skill.get("cooldown", 0.0))
		cooldown.custom_minimum_size.x = 90
		cooldown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cooldown.add_theme_color_override("font_color", PanelChrome.MUTED)
		cooldown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(cooldown)
		if skill_id == "basic_slash":
			_basic_interval_label = cooldown
		if max_rank > 1 and rank >= max_rank:
			var completed := Label.new()
			completed.text = Localization.tr_key("ui.skill_panel.max_rank")
			completed.custom_minimum_size.x = 84
			completed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			completed.add_theme_color_override("font_color", PanelChrome.MUTED)
			completed.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(completed)
		elif max_rank > 1 and unlocked:
			var upgrade := SkillUpgradeButton.new()
			upgrade.skill_id = skill_id
			upgrade.name = "Upgrade_" + skill_id
			upgrade.text = Localization.tr_key("ui.skill_panel.upgrade")
			upgrade.custom_minimum_size.x = 84
			upgrade.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			upgrade.pressed.connect(_on_upgrade_pressed.bind(skill_id))
			PanelChrome.style_action(upgrade)
			row.add_child(upgrade)
			_upgrade_buttons[skill_id] = upgrade
	_refresh_affordability()
	_refresh_cooldowns()

## 自动红蓝药作为快捷栏工具保持可补领，但不再占用技能行与升阶按钮空间。
func _build_potion_tools() -> void:
	for kind in ["red", "blue"]:
		var button := SkillDragButton.new()
		button.custom_minimum_size = Vector2(48, 48)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.text = Localization.tr_key("ui.skill_panel.p006") if kind == "red" else Localization.tr_key("ui.skill_panel.p007")
		button.binding = {"kind": "auto_potion", "id": kind}
		SampleArt.decorate(button, SampleArt.binding_icon(button.binding))
		button.add_theme_constant_override("icon_max_width", 42)
		button.tooltip_text = Localization.tr_key("ui.skill_panel.p008")
		_tools_row.add_child(button)
		_potion_buttons[kind] = button
		var name := Label.new()
		name.text = Localization.tr_key("ui.skill_panel.auto_red" if kind == "red" else "ui.skill_panel.auto_blue")
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.add_theme_color_override("font_color", PanelChrome.TEXT)
		_tools_row.add_child(name)

## 当前倒计时从真实玩家入口读取，角色切图未出现时不显示假就绪状态。
func _refresh_cooldowns() -> void:
	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	for skill_id in _cooldown_labels.keys():
		var label := _cooldown_labels[skill_id] as Label
		if not is_instance_valid(label):
			continue
		var left := player.skill_cooldown(String(skill_id)) if player != null else 0.0
		label.text = "%.0fs" % ceilf(left) if left > 0.0 else ""
	if _basic_interval_label != null and player != null:
		_basic_interval_label.text = Localization.tr_key("ui.skill_panel.detail_basic_badge") % player.effective_attack_interval()

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
