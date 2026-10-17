extends Control
## 死亡选择；运行在 UI 的 ALWAYS CanvasLayer 下，世界暂停时仍可操作。

var _revive_here: Button
var _hint: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false
	EventBus.player_died.connect(func() -> void: _show_after_death.call_deferred())

func _build() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.05, 0.82)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelChrome.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	var title := Label.new()
	title.text = Localization.tr_key("ui.death_panel.p001")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	PanelChrome.style_title(title)
	box.add_child(PanelChrome.make_title_gap())
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", PanelChrome.MUTED)
	box.add_child(_hint)
	_revive_here = Button.new()
	_revive_here.pressed.connect(revive_here)
	box.add_child(_revive_here)
	PanelChrome.style_action(_revive_here, true)
	var camp := Button.new()
	camp.text = Localization.tr_key("ui.death_panel.p002")
	camp.pressed.connect(revive_camp)
	box.add_child(camp)
	PanelChrome.style_action(camp)

func _show_after_death() -> void:
	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	if player == null or not player.is_dead:
		return
	if _try_auto_revive(player):
		return
	visible = true
	GameState.set_panel_open("death", true)
	_refresh()
	get_tree().paused = true

## 自动原地复活（设置项 `autoReviveOnDeath`）：开关开启且背包有复活卷时，死亡不弹面板、不暂停世界，
## 直接消耗 1 张复活卷原地复活；若死亡前处于自动战斗，复活后按原样恢复挂机。
## 任一条件不满足（开关关 / 无复活卷 / 复活失败）返回 false，交由下方手动死亡面板处理。
## 复活与存档沿用 `revive_here()` 的既有入口，不新增第二条结算路径。
func _try_auto_revive(player: PlayerCharacter) -> bool:
	if not bool(GameState.settings.get("autoReviveOnDeath", false)):
		return false
	if _revive_scroll_count() <= 0:
		return false
	var resume_auto := player.auto_battle_before_death
	if not revive_here():
		return false
	# 必须在 `_revive()`（is_dead=false）之后才能开启挂机，否则 AutoBattle 会立刻再次关掉。
	if resume_auto:
		GameState.set_auto_battle(true)
	EventBus.toast_requested.emit(Localization.tr_key("msg.death_auto.p001"), "info")
	return true

## 背包中复活卷总数（`_refresh()` 显示与自动复活判定共用同一口径）。
func _revive_scroll_count() -> int:
	var count := 0
	for item in GameState.inventory:
		if item is Dictionary and String(item.get("itemId", "")) == "misc_revive_scroll":
			count += int(item.get("count", 1))
	return count

func _refresh() -> void:
	var count := _revive_scroll_count()
	_revive_here.text = Localization.tr_key("ui.death_panel.p003") % count
	_revive_here.disabled = count <= 0
	_hint.text = Localization.tr_key("ui.death_panel.p004")

func revive_here() -> bool:
	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	if player == null or not player.is_dead:
		return false
	for i in range(GameState.inventory.size()):
		var item = GameState.inventory[i]
		if not item is Dictionary or String(item.get("itemId", "")) != "misc_revive_scroll":
			continue
		if int(item.get("count", 1)) > 1:
			item.count = int(item.get("count", 1)) - 1
			EventBus.inventory_changed.emit()
		else:
			GameState.remove_item_at(i)
		player._revive()
		_close()
		# A-P3-6：此调用是复活后唯一的存档触发点，不可删除——`inventory_changed` 并非
		# SaveManager 的自动存档订阅源，`player._revive()` 自身也不触发存档。
		SaveManager.request_autosave()
		return true
	_refresh()
	return false

func revive_camp() -> bool:
	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	if player == null or not player.is_dead:
		return false
	var town_id := MapService.safe_town_for(GameState.current_map)
	if town_id.is_empty():
		EventBus.toast_requested.emit(Localization.tr_key("ui.death_panel.p005"), "danger")
		return false
	if GameState.current_map != town_id and (get_tree().current_scene == null or not get_tree().current_scene.has_node("Game")):
		# A-P2-3：跨图复活但世界场景未就绪时无法切图，明确反馈而非静默失败。
		EventBus.toast_requested.emit(Localization.tr_key("ui.death_panel.p005"), "danger")
		return false
	if GameState.current_map == town_id:
		player.global_position = MapService.entry_point(town_id)
		player._revive()
		_close()
		SaveManager.request_autosave()
		return true
	var result := MapService._prepare_travel(town_id, "revive", 0, MapService.entry_point(town_id))
	if not bool(result.get("ok", false)):
		# A-P2-3：切图准备失败（目标图不可达等）时明确反馈，避免玩家点了没反应。
		EventBus.toast_requested.emit(Localization.tr_key("ui.death_panel.p005"), "danger")
		return false
	player._revive()
	_close()
	MapService.reload_world()
	return true

func _close() -> void:
	visible = false
	GameState.set_panel_open("death", false)
	get_tree().paused = false
