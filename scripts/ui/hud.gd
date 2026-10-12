extends Control
## HUD（M1-3 最小版，依据产品文档 9.1）。
## 玩家状态区（头像 / 名称 / 等级 / 血蓝槽）+ 金币 + 目标状态区 + 地图信息 + 16 格快捷栏占位。
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
@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp_text: Label = %HpText
@onready var _mp_bar: ProgressBar = %MpBar
@onready var _mp_text: Label = %MpText
@onready var _exp_bar: ProgressBar = %ExpBar
@onready var _gold_label: Label = %GoldLabel
@onready var _bag_label: Label = %BagLabel
@onready var _auto_label: Label = %AutoLabel
@onready var _toast_box: VBoxContainer = %ToastBox
@onready var _map_name: Label = %MapName
@onready var _map_coords: Label = %MapCoords
@onready var _target_name: Label = %TargetName
@onready var _target_hp: ProgressBar = %TargetHp
@onready var _hotbar: HBoxContainer = %Hotbar
@onready var _quest_tracker: PanelContainer = %QuestTracker
@onready var _quest_list: VBoxContainer = %QuestList

var _target: Node = null
var _auto_battle: bool = false
var _auto_pickup: bool = false
var _auto_phase: String = ""

func _ready() -> void:
	EventBus.player_hp_changed.connect(_on_hp)
	EventBus.player_mp_changed.connect(_on_mp)
	EventBus.player_xp_changed.connect(_on_xp)
	EventBus.gold_changed.connect(_on_gold)
	EventBus.player_leveled.connect(_on_level)
	EventBus.target_changed.connect(_on_target)
	EventBus.map_changed.connect(_on_map_changed)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.toast_requested.connect(_on_toast)
	EventBus.auto_state_changed.connect(_on_auto_state)
	EventBus.auto_phase_changed.connect(_on_auto_phase)
	EventBus.quest_accepted.connect(_on_quest_changed)
	EventBus.quest_completed.connect(_on_quest_changed)
	EventBus.quest_rewarded.connect(_on_quest_changed)
	EventBus.quest_progressed.connect(_on_quest_progressed)
	_build_hotbar()
	_refresh_all()
	_refresh_auto()
	_refresh_quests()

func _process(_delta: float) -> void:
	_update_coords()
	_update_target()

# ---- 事件回调 ----

func _on_hp(current: int, maximum: int) -> void:
	_hp_bar.max_value = maxi(1, maximum)
	_hp_bar.value = current
	_hp_text.text = "%d / %d" % [current, maximum]

func _on_mp(current: int, maximum: int) -> void:
	_mp_bar.max_value = maxi(1, maximum)
	_mp_bar.value = current
	_mp_text.text = "%d / %d" % [current, maximum]

func _on_xp(current: int, maximum: int) -> void:
	_exp_bar.max_value = maxi(1, maximum)
	_exp_bar.value = current

func _on_gold(amount: int) -> void:
	_gold_label.text = "金币  %d" % amount

func _on_level(level: int) -> void:
	_level_label.text = "Lv%d" % level

func _on_target(target: Node) -> void:
	_target = target
	_update_target()

func _on_map_changed(_map_id: String) -> void:
	_map_name.text = _current_map_name()

func _on_inventory_changed() -> void:
	_bag_label.text = "背包  %d / %d" % [GameState.inventory_used(), GameState.inventory.size()]

# ---- 自动战斗状态指示（M1-9；4.6「界面明显显示自动中 / 手动接管 / 暂停中」）----

func _on_auto_state(battle: bool, pickup: bool) -> void:
	_auto_battle = battle
	_auto_pickup = pickup
	_refresh_auto()

func _on_auto_phase(phase: String) -> void:
	_auto_phase = phase
	_refresh_auto()

func _refresh_auto() -> void:
	if not _auto_battle:
		_auto_label.text = "自动  关（F 开启）"
		_auto_label.add_theme_color_override("font_color", COL_AUTO_OFF)
		return
	var tail := ""
	if _auto_phase == "手动接管":
		tail = " · 3 秒后恢复"
	elif _auto_pickup:
		tail = " · 拾取 G 开"
	_auto_label.text = "自动  %s%s" % [_auto_phase if not _auto_phase.is_empty() else "启动中", tail]
	var col := COL_AUTO_OVERRIDE if _auto_phase == "手动接管" else COL_AUTO_ON
	_auto_label.add_theme_color_override("font_color", col)

## 系统提示 Toast（9.6，最小版；完整样式在 M5-5 完善）。
func _on_toast(text: String, kind: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", _toast_color(kind))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 4)
	_toast_box.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_interval(1.4)
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
		_:
			return Color("e8e8e8")

# ---- 刷新 ----

func _refresh_all() -> void:
	_name_label.text = String(GameState.player.get("name", "守护者"))
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
		more.text = "…还有 %d 条" % (items.size() - QUEST_LIST_MAX)
		more.add_theme_font_size_override("font_size", 11)
		more.add_theme_color_override("font_color", COL_AUTO_OFF)
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_quest_list.add_child(more)

## 单条任务行：「· 初战试炼 3/5」；completed 显示「⚑ 名 可交付」高亮（9.1）。
func _make_quest_row(e: Dictionary) -> Label:
	var state := String(e.get("state", ""))
	var done := state == Quest.STATE_COMPLETED
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := "%s%s" % ["⚑ " if done else "· ", String(e.get("name", ""))]
	if done:
		text += "　可交付"
		lbl.add_theme_color_override("font_color", COL_AUTO_OVERRIDE)
	else:
		var need := int(e.get("need", 0))
		if need > 1:
			text += " %d/%d" % [int(e.get("cur", 0)), need]
		lbl.add_theme_color_override("font_color", Color(0.86, 0.88, 0.91))
	lbl.text = text
	return lbl

func _update_coords() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p is Node2D:
		var g := Iso.world_to_grid((p as Node2D).global_position)
		_map_coords.text = "(%d, %d)" % [int(round(g.x)), int(round(g.y))]

func _update_target() -> void:
	if _target != null and is_instance_valid(_target) and _target.get("is_dead") != true:
		_target_name.text = String(_target.get("display_name"))
		_target_hp.max_value = maxi(1, int(_target.get("max_hp")))
		_target_hp.value = int(_target.get("hp"))
	else:
		_target_name.text = "无目标"
		_target_hp.value = 0

func _current_map_name() -> String:
	var m = DataLoader.get_entry("maps", GameState.current_map)
	if m == null:
		return String(GameState.current_map)
	return String(m.get("name", GameState.current_map))

# ---- 快捷栏占位（16 格，技能 / 药品槽位在 M4-6 完善）----

func _build_hotbar() -> void:
	for _i in range(HOTBAR_SLOTS):
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(28, 28)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_stylebox_override("panel", _slot_style())
		_hotbar.add_child(slot)

func _slot_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.16, 0.85)
	sb.border_color = Color(0.35, 0.38, 0.42)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	return sb
