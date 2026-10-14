extends Control
## HUD（M1-3 最小版，依据产品文档 9.1）。
## 玩家状态区（头像 / 名称 / 等级 / 细血蓝槽 / 自动状态图标）+ 目标状态区 + 地图信息 + 16 格快捷栏。
## 全部数值经 EventBus 广播驱动刷新，不做轮询（内存与事件卫生）。

const HOTBAR_SLOTS := 16
## 任务列表最多显示条数（08 §8.4 同时接取上限 5）；超出折叠为「还有 N 条」。
const QUEST_LIST_MAX := 5

## 自动状态指示配色（4.6：界面明显显示「自动中 / 手动接管 / 暂停中」）
const COL_AUTO_OFF := Color("8c9199")
const COL_AUTO_ON := Color("f0a44a")
const COL_AUTO_OVERRIDE := Color("8fd07a")

@onready var _name_label: Label = %NameLabel
@onready var _level_label: Label = %LevelLabel
@onready var _hp_bar: HudStatusBar = %HpBar
@onready var _hp_text: Label = %HpText
@onready var _mp_bar: HudStatusBar = %MpBar
@onready var _mp_text: Label = %MpText
@onready var _exp_bar: ProgressBar = %ExpBar
@onready var _gold_label: Label = %GoldLabel
@onready var _bag_label: Label = %BagLabel
@onready var _auto_label: Label = %AutoLabel
@onready var _buff_label: Label = %BuffLabel
@onready var _battle_icon: HudStatusIcon = %AutoBattleIcon
@onready var _pickup_icon: HudStatusIcon = %AutoPickupIcon
@onready var _focus_icon: HudStatusIcon = %BattleFocusIcon
@onready var _toast_box: VBoxContainer = %ToastBox
@onready var _map_name: Label = %MapName
@onready var _map_coords: Label = %MapCoords
@onready var _target_name: Label = %TargetName
@onready var _target_hp: HudStatusBar = %TargetHp
@onready var _target_portrait: TextureRect = %TargetPortraitImage
@onready var _hotbar: HBoxContainer = %Hotbar
@onready var _quest_tracker: PanelContainer = %QuestTracker
@onready var _quest_list: VBoxContainer = %QuestList

var _target: Node = null
var _target_hint: Label
var _auto_battle: bool = false
var _auto_pickup: bool = false
var _auto_phase: String = ""
var _hotbar_buttons: Array[HotbarSlot] = []

func _ready() -> void:
	_build_target_hint()
	EventBus.player_hp_changed.connect(_on_hp)
	EventBus.player_mp_changed.connect(_on_mp)
	EventBus.player_xp_changed.connect(_on_xp)
	EventBus.gold_changed.connect(_on_gold)
	EventBus.player_leveled.connect(_on_level)
	EventBus.target_changed.connect(_on_target)
	EventBus.map_changed.connect(_on_map_changed)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.hotbar_changed.connect(_refresh_hotbar)
	EventBus.toast_requested.connect(_on_toast)
	EventBus.auto_state_changed.connect(_on_auto_state)
	EventBus.auto_phase_changed.connect(_on_auto_phase)
	EventBus.player_sitting_changed.connect(_on_sitting_changed)
	EventBus.quest_accepted.connect(_on_quest_changed)
	EventBus.quest_completed.connect(_on_quest_changed)
	EventBus.quest_rewarded.connect(_on_quest_changed)
	EventBus.quest_progressed.connect(_on_quest_progressed)
	_build_hotbar()
	$MapPanel/SettingsButton.pressed.connect(func() -> void: get_node("../SettingsPanel").set_open(true))
	_refresh_all()
	_auto_battle = GameState.auto_battle_on
	_auto_pickup = GameState.auto_pickup_on
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		var pilot := player.get_node_or_null("AutoPilot") as AutoBattle
		if pilot != null:
			_auto_phase = pilot.current_phase()
	_refresh_auto()
	_refresh_quests()
	_update_target()

func _process(_delta: float) -> void:
	_update_coords()
	_update_target()
	var remaining := GameState.buff_remaining("battle_focus")
	_buff_label.text = Localization.tr_key("ui.hud.p001") % remaining if remaining > 0.0 else ""
	_focus_icon.visible = remaining > 0.0
	if remaining > 0.0:
		_focus_icon.tooltip_text = _buff_label.text

# ---- 事件回调 ----

func _on_hp(current: int, maximum: int) -> void:
	_hp_bar.max_value = maxi(1, maximum)
	_hp_bar.value = current
	_hp_bar.tooltip_text = "%s  %d / %d" % [Localization.tr_key("ui.hud.hp"), current, maximum]
	_hp_text.text = "%d / %d" % [current, maximum]

func _on_mp(current: int, maximum: int) -> void:
	_mp_bar.max_value = maxi(1, maximum)
	_mp_bar.value = current
	_mp_bar.tooltip_text = "%s  %d / %d" % [Localization.tr_key("ui.hud.mp"), current, maximum]
	_mp_text.text = "%d / %d" % [current, maximum]

func _on_xp(current: int, maximum: int) -> void:
	_exp_bar.max_value = maxi(1, maximum)
	_exp_bar.value = current

func _on_gold(amount: int) -> void:
	_gold_label.text = Localization.tr_key("ui.hud.p002") % amount

func _on_level(level: int) -> void:
	_level_label.text = "%d" % level
	_level_label.tooltip_text = "%s %d" % [Localization.tr_key("ui.hud.level"), level]

func _on_target(target: Node) -> void:
	_target = target
	_update_target_portrait()
	_update_npc_portrait()
	_update_target()

func _on_map_changed(_map_id: String) -> void:
	_map_name.text = _current_map_name()

func _on_inventory_changed() -> void:
	_bag_label.text = Localization.tr_key("ui.hud.p003") % [GameState.inventory_used(), GameState.inventory.size()]
	_refresh_hotbar()

# ---- 自动战斗状态指示（M1-9；4.6「界面明显显示自动中 / 手动接管 / 暂停中」）----

func _on_auto_state(battle: bool, pickup: bool) -> void:
	_auto_battle = battle
	_auto_pickup = pickup
	_refresh_auto()

func _on_auto_phase(phase: String) -> void:
	_auto_phase = phase
	_refresh_auto()

func _on_sitting_changed(_sitting: bool) -> void:
	_refresh_auto()

func _refresh_auto() -> void:
	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	var sitting := player != null and player.is_sitting
	if sitting:
		_auto_label.text = Localization.tr_key("ui.hud.p004") if not _auto_battle else Localization.tr_key("ui.hud.p005")
		_auto_label.add_theme_color_override("font_color", COL_AUTO_OVERRIDE)
	elif not _auto_battle:
		_auto_label.text = Localization.tr_key("ui.hud.p006")
		_auto_label.add_theme_color_override("font_color", COL_AUTO_OFF)
	else:
		var tail := ""
		if _auto_pickup and not _auto_phase.begins_with(Localization.tr_key("ui.auto.manual")):
			tail = Localization.tr_key("ui.hud.pickup_on")
		_auto_label.text = Localization.tr_key("ui.hud.p007") % [_auto_phase if not _auto_phase.is_empty() else Localization.tr_key("ui.hud.p008"), tail]
		var col := COL_AUTO_OVERRIDE if _auto_phase.begins_with(Localization.tr_key("ui.auto.manual")) else COL_AUTO_ON
		_auto_label.add_theme_color_override("font_color", col)
	var paused := sitting or _auto_phase.begins_with(Localization.tr_key("ui.auto.manual")) or _auto_phase == Localization.tr_key("ui.auto.paused")
	_battle_icon.active = _auto_battle
	_battle_icon.paused = _auto_battle and paused
	_battle_icon.tooltip_text = "%s · F" % _auto_label.text
	_pickup_icon.active = _auto_pickup
	_pickup_icon.paused = _auto_pickup and sitting
	_pickup_icon.tooltip_text = "%s · G" % Localization.tr_key("ui.hud.pickup_icon_on" if _auto_pickup else "ui.hud.pickup_icon_off")

## 系统提示 Toast（9.6，最小版；完整样式在 M5-5 完善）。
## M6-0e（创意 07 §10）：`legendary` 提示停留更久（合计 3s）并放大字号。
func _on_toast(text: String, kind: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 17 if kind == "legendary" else 15)
	lbl.add_theme_color_override("font_color", _toast_color(kind))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 4)
	_toast_box.add_child(lbl)
	var hold := 2.4 if kind == "legendary" else 1.4   # + 0.6s 淡出 = 3.0s / 2.0s
	var tw := lbl.create_tween()
	tw.tween_interval(hold)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.tween_callback(lbl.queue_free)

func _toast_color(kind: String) -> Color:
	match kind:
		"danger":
			return Color("e0655a")
		"levelup":
			return Color("f0d060")
		"pickup":
			return Color("8fd07a")
		"drop":
			return Color("e8b46a")
		"legendary":
			return Color("b46ae0")
		_:
			return Color("e8e8e8")

# ---- 刷新 ----

func _refresh_all() -> void:
	_name_label.text = String(GameState.player.get("name", Localization.tr_key("ui.hud.p009")))
	_on_level(int(GameState.player.get("level", 1)))
	_on_hp(int(GameState.player.hp), GameState.max_hp())
	_on_mp(int(GameState.player.mp), GameState.max_mp())
	_on_xp(int(GameState.player.xp), GameState.xp_to_next(int(GameState.player.level)))
	_on_gold(GameState.gold)
	_on_inventory_changed()
	_map_name.text = _current_map_name()

# ---- 任务列表（M2-4；9.1 第 6 条「小地图下方」）----

func _on_quest_changed(_quest_id: String) -> void:
	_refresh_quests()

func _on_quest_progressed(_quest_id: String, _cur: int, _need: int) -> void:
	_refresh_quests()

## 重建进行中任务列表（事件驱动刷新，不轮询）。无进行中任务时整块隐藏。
func _refresh_quests() -> void:
	if _quest_list == null:
		return
	for c in _quest_list.get_children():
		_quest_list.remove_child(c)
		c.queue_free()
	var items: Array[Dictionary] = Quest.ongoing_list()
	_quest_tracker.visible = not items.is_empty()
	if items.is_empty():
		return
	var shown := 0
	for e in items:
		if shown >= QUEST_LIST_MAX:
			break
		_quest_list.add_child(_make_quest_row(e))
		shown += 1
	if items.size() > QUEST_LIST_MAX:
		var more := Label.new()
		more.text = Localization.tr_key("ui.hud.p010") % (items.size() - QUEST_LIST_MAX)
		more.add_theme_font_size_override("font_size", 11)
		more.add_theme_color_override("font_color", COL_AUTO_OFF)
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_quest_list.add_child(more)

## 单条任务行：「· 初战试炼 3/5」；completed 显示「⚑ 名 可交付」高亮（9.1）。
func _make_quest_row(e: Dictionary) -> Control:
	var state := String(e.get("state", ""))
	var done := state == Quest.STATE_COMPLETED
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := "%s%s" % ["⚑ " if done else "· ", String(e.get("name", ""))]
	if done:
		text += Localization.tr_key("ui.hud.p011")
		lbl.add_theme_color_override("font_color", COL_AUTO_OVERRIDE)
	else:
		var need := int(e.get("need", 0))
		if need > 1:
			text += " %d/%d" % [int(e.get("cur", 0)), need]
		lbl.add_theme_color_override("font_color", Color(0.86, 0.88, 0.91))
	lbl.text = text
	var objective: Dictionary = e.get("objective", {})
	if done or String(objective.get("kind", "")) != "kill":
		return lbl
	var row := VBoxContainer.new()
	row.add_child(lbl)
	var target := QuestTargetLink.new()
	target.text = "→ " + Quest._target_name("kill", String(objective.get("targetId", "")))
	target.alignment = HORIZONTAL_ALIGNMENT_LEFT
	target.add_theme_font_size_override("font_size", 11)
	target.pressed.connect(func() -> void:
		var result := Quest.start_target_navigation(String(e.get("id", "")))
		if not bool(result.get("ok", false)):
			EventBus.toast_requested.emit(String(result.get("reason", Localization.tr_key("ui.hud.p012"))), "danger"))
	row.add_child(target)
	return row

func _update_coords() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p is Node2D:
		var g := Iso.world_to_grid((p as Node2D).global_position)
		_map_coords.text = "(%d,%d)" % [int(round(g.x)), int(round(g.y))]

func _update_target() -> void:
	var valid: bool = is_instance_valid(_target) and not _target.is_queued_for_deletion() and _target.get("is_dead") != true
	# Boss 由顶部专用血条展示，同一目标无需再占用普通目标卡。
	$TargetPanel.visible = valid and not _target_is_boss(_target)
	_target_hint.visible = valid and _target is Npc
	_target_hp.visible = valid and not _target is Npc
	if valid and _target is Npc:
		_target_name.text = (_target as Npc).npc_name
		return
	if valid:
		_target_name.text = String(_target.get("display_name"))
		_target_name.tooltip_text = _target_name.text
		_target_hp.max_value = maxi(1, int(_target.get("max_hp")))
		_target_hp.value = int(_target.get("hp"))
		_target_hp.tooltip_text = "%d / %d" % [int(_target.get("hp")), int(_target.get("max_hp"))]
	else:
		_target_name.text = Localization.tr_key("ui.hud.p013")
		_target_hp.value = 0

func _build_target_hint() -> void:
	_target_hint = Label.new()
	_target_hint.position = Vector2(_target_name.position.x, _target_name.position.y + _target_name.size.y + 2.0)
	_target_hint.size = Vector2(_target_name.size.x, 25.0)
	_target_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_hint.add_theme_font_size_override("font_size", 12)
	_target_hint.add_theme_color_override("font_color", Color("8fd7c8"))
	_target_hint.text = Localization.tr_key("ui.hud.npc_interact")
	_target_hint.visible = false
	$TargetPanel.add_child(_target_hint)

func _update_npc_portrait() -> void:
	var portrait := get_node_or_null("TargetPanel/TargetPortrait/TargetPortraitImage") as TextureRect
	if portrait == null or not _target is Npc:
		return
	var npc := _target as Npc
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/sprites/npcs/%s/idle_atlas.png" % npc.role) as Texture2D
	atlas.region = Rect2(0.0, 0.0, 64.0, 64.0)
	portrait.texture = atlas

func _update_target_portrait() -> void:
	_target_portrait.texture = null
	if not is_instance_valid(_target) or not _target is Monster:
		return
	var monster := _target as Monster
	var path := ""
	var frame_width := 80
	match monster.monster_id:
		"wolf_corrupted", "elite_wolf_king":
			path = "res://assets/sprites/monsters/wolf_corrupted/wolf_atlas.png"
		"shellback_bug", "elite_shellback_bug":
			path = "res://assets/sprites/monsters/shellback_bug/actor_atlas.png"
		"ash_wraith", "elite_ash_wraith":
			path = "res://assets/sprites/monsters/ash_wraith/actor_atlas.png"
			frame_width = 64
		"training_dummy":
			path = "res://assets/sprites/monsters/training_dummy/dummy_atlas.png"
			frame_width = 64
	if path.is_empty():
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = load(path) as Texture2D
	atlas.region = Rect2(frame_width * 0.2, 13.0, frame_width * 0.6, 62.0)
	_target_portrait.texture = atlas

func _target_is_boss(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var template: Variant = target.get("template")
	return template is Dictionary and String((template as Dictionary).get("kind", "")) == "boss"

func _current_map_name() -> String:
	var m = DataLoader.get_entry("maps", GameState.current_map)
	if m == null:
		return String(GameState.current_map)
	return String(m.get("name", GameState.current_map))

# ---- 快捷栏：前 12 格放已接通操作，后 4 格打开面板 ----

func _unhandled_input(event: InputEvent) -> void:
	if GameState.panel_open or not event is InputEventKey or not event.pressed or event.echo:
		return
	for i in range(12):
		if InputMap.has_action("hotbar_%d" % (i + 1)) and event.is_action_pressed("hotbar_%d" % (i + 1)):
			_activate_hotbar(i)
			get_viewport().set_input_as_handled()
			return

func _build_hotbar() -> void:
	for i in range(HOTBAR_SLOTS):
		if i >= 12:
			var button := Button.new()
			button.custom_minimum_size = Vector2(32, 32)
			var names := [Localization.tr_key("ui.hud.character_short"), Localization.tr_key("ui.hud.inventory_short"), Localization.tr_key("ui.hud.skill_short"), Localization.tr_key("ui.hud.mount_short")]
			var keys := ["C", "I", "K", "N"]
			button.text = names[i - 12]
			button.tooltip_text = Localization.tr_key("ui.hud.p014") % [names[i - 12], keys[i - 12]]
			button.pressed.connect(_open_panel.bind(i))
			_hotbar.add_child(button)
			continue
		var slot := HotbarSlot.new()
		slot.index = i
		slot.custom_minimum_size = Vector2(32, 32)
		slot.pressed.connect(_activate_hotbar.bind(i))
		slot.binding_dropped.connect(_on_binding_dropped)
		slot.clear_requested.connect(func(clear_index: int) -> void: GameState.set_hotbar_entry(clear_index, null))
		_hotbar.add_child(slot)
		_hotbar_buttons.append(slot)
	_refresh_hotbar()

func _refresh_hotbar() -> void:
	for i in range(_hotbar_buttons.size()):
		var binding = GameState.hotbar[i]
		var name := _binding_name(binding)
		var slot := _hotbar_buttons[i]
		slot.entry = binding
		slot.text = name.substr(0, 1) if binding != null else ""
		slot.tooltip_text = Localization.tr_key("ui.hud.p015") % [name, i + 1]
		slot.set_count(_binding_count(binding))
		SampleArt.decorate(slot, SampleArt.binding_icon(binding))

func _binding_name(binding: Variant) -> String:
	if not binding is Dictionary:
		return Localization.tr_key("ui.hud.p016")
	match String(binding.kind):
		"auto_potion": return Localization.tr_key("ui.hud.auto_red") if binding.id == "red" else Localization.tr_key("ui.hud.auto_blue")
		"skill":
			var skill = DataLoader.get_entry("skills", String(binding.id))
			return String(skill.get("name", binding.id)) if skill is Dictionary else String(binding.id)
		"potion", "item":
			var table := "potions" if binding.kind == "potion" else "miscItems"
			var template = DataLoader.get_entry(table, String(binding.id))
			return String(template.get("name", binding.id)) if template is Dictionary else String(binding.id)
	return Localization.tr_key("ui.hud.p016")

func _binding_count(binding: Variant) -> int:
	if not binding is Dictionary or binding.kind == "skill":
		return -1
	var total := 0
	for raw in GameState.inventory:
		if not raw is Dictionary:
			continue
		var item: Dictionary = raw
		if binding.kind == "auto_potion":
			if item.get("kind") != "potion":
				continue
			var template = DataLoader.get_entry("potions", String(item.get("itemId", "")))
			if not template is Dictionary or template.get("kind") != binding.id:
				continue
		elif String(item.get("itemId", "")) != String(binding.id):
			continue
		total += int(item.get("count", 1))
	return total

func set_hotbar_drop_mode(active: bool) -> void:
	var inventory := get_node_or_null("../InventoryPanel") as Control
	var skills := get_node_or_null("../SkillPanel") as Control
	_hotbar.z_index = 100 if active or (inventory != null and inventory.visible) or (skills != null and skills.visible) else 0

func _on_binding_dropped(index: int, payload: Dictionary) -> void:
	var kind := String(payload.get("kind", ""))
	if kind == "hotbar_slot":
		GameState.swap_hotbar_entries(int(payload.get("index", -1)), index)
	elif kind == "hotbar_skill":
		GameState.set_hotbar_entry(index, {"kind": "skill", "id": payload.get("id")})
	elif kind == "hotbar_binding":
		GameState.set_hotbar_entry(index, payload.get("entry"))
	elif int(payload.get("from", -1)) == ItemSlot.ROLE_BAG:
		var source := int(payload.get("index", -1))
		if source >= 0 and source < GameState.inventory.size() and GameState.inventory[source] is Dictionary:
			var item: Dictionary = GameState.inventory[source]
			if Warehouse.token_matches(item, String(payload.get("token", ""))):
				GameState.set_hotbar_entry(index, HotbarConfig.entry_for_item(item))

func _activate_hotbar(index: int) -> void:
	if index < 0 or index >= 12 or GameState.panel_open:
		return
	var binding = GameState.hotbar[index]
	if not binding is Dictionary:
		return
	match String(binding.kind):
		"auto_potion": _use_potion(String(binding.id))
		"potion", "item":
			var source := _first_item_index(String(binding.id))
			if source >= 0:
				GameState.use_item(source)
			else:
				EventBus.toast_requested.emit(Localization.tr_key("ui.hud.p017") % _binding_name(binding), "danger")
		"skill":
			var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
			if player != null:
				player.request_skill(String(binding.id))

func _first_item_index(item_id: String) -> int:
	for i in range(GameState.inventory.size()):
		var item = GameState.inventory[i]
		if item is Dictionary and item.get("itemId") == item_id:
			return i
	return -1

func _use_potion(kind: String) -> void:
	var idx := Consumable.pick_index(kind)
	if idx < 0:
		idx = Consumable.first_index_of_kind(kind)
	if idx >= 0:
		GameState.use_item(idx)
	else:
		EventBus.toast_requested.emit(Localization.tr_key("ui.hud.p017") % (Localization.tr_key("ui.hud.p018") if kind == Consumable.KIND_RED else Localization.tr_key("ui.hud.p019")), "danger")

func _open_panel(index: int) -> void:
	var nodes := ["CharacterPanel", "InventoryPanel", "SkillPanel", "MountPanel"]
	var panel := get_node_or_null("../" + nodes[index - 12])
	if panel != null:
		panel.set_open(true)

func _slot_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.16, 0.85)
	sb.border_color = Color(0.35, 0.38, 0.42)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	return sb
