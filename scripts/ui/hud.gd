extends Control
## HUD（M1-3 最小版，依据产品文档 9.1）。
## 玩家状态区（头像 / 名称 / 等级 / 血蓝槽）+ 金币 + 目标状态区 + 地图信息 + 16 格快捷栏占位。
## 全部数值经 EventBus 广播驱动刷新，不做轮询（内存与事件卫生）。

const HOTBAR_SLOTS := 16

@onready var _name_label: Label = %NameLabel
@onready var _level_label: Label = %LevelLabel
@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp_text: Label = %HpText
@onready var _mp_bar: ProgressBar = %MpBar
@onready var _mp_text: Label = %MpText
@onready var _exp_bar: ProgressBar = %ExpBar
@onready var _gold_label: Label = %GoldLabel
@onready var _bag_label: Label = %BagLabel
@onready var _toast_box: VBoxContainer = %ToastBox
@onready var _map_name: Label = %MapName
@onready var _map_coords: Label = %MapCoords
@onready var _target_name: Label = %TargetName
@onready var _target_hp: ProgressBar = %TargetHp
@onready var _hotbar: HBoxContainer = %Hotbar

var _target: Node = null

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
	_build_hotbar()
	_refresh_all()

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
