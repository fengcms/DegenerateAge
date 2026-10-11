class_name Npc
extends Node2D
## 功能性 NPC 占位实体（产品文档 6.3 安全区与通用交互；M1-8 先实现货郎 6.4）。
##
## 占位素材（R5）：程序化绘制斗篷人形；头顶名称 / 提示用 Label（走项目主题的
## SystemFont CJK 字体，避免 draw_string 用引擎内置字体导致中文方框）。
## 交互派发：由 scripts/world/game.gd 统一处理 interact 键（E），本节点只暴露
## shop_id 与近距判定，不自己抢输入（保持单一输入出口，便于 9.8 对话系统接管）。
## 碰撞：MVP 不加碰撞体（避免把玩家卡住）；M3 补静态碰撞与逐句对话推进。

## 交互半径 2 格（6.3 安全区交互距离）
const INTERACT_RANGE := 2.0 * 64.0

const COLOR_CLOAK := Color("7d6ac8")
const COLOR_CLOAK_EDGE := Color("3b3268")
const COLOR_SKIN := Color("e8c9a0")

## 对应 shops.json 的 npcId；为空表示纯对话 NPC（M2 任务官等）。
@export var shop_id: String = ""
## 头顶名称；为空时从配置表取名。
@export var npc_name: String = ""

var _near: bool = false
var _phase: float = 0.0
var _player: Node2D = null

@onready var _name_label: Label = $NameLabel
@onready var _hint_label: Label = $HintLabel

func _ready() -> void:
	add_to_group("npcs")
	if npc_name.is_empty() and not shop_id.is_empty():
		npc_name = Shop.display_name(shop_id)
	if npc_name.is_empty():
		npc_name = "NPC"
	_name_label.text = npc_name
	_hint_label.text = "[E] 交谈"
	_hint_label.visible = false
	queue_redraw()

func _process(delta: float) -> void:
	_phase += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	var near := is_player_in_range()
	if near != _near:
		_near = near
		_hint_label.visible = _near
		queue_redraw()
	if _near:
		_hint_label.modulate.a = 0.7 + 0.3 * absf(sin(_phase * 3.0))

## 玩家是否处于交互范围内（6.3）。
func is_player_in_range() -> bool:
	var p := get_tree().get_first_node_in_group("player")
	if not (p is Node2D):
		return false
	return (p as Node2D).global_position.distance_to(global_position) <= INTERACT_RANGE

func _draw() -> void:
	# 脚下阴影
	draw_set_transform(Vector2(0.0, 8.0), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 斗篷（梯形）+ 描边
	var cloak := PackedVector2Array([
		Vector2(-12.0, 10.0), Vector2(12.0, 10.0), Vector2(7.0, -6.0), Vector2(-7.0, -6.0),
	])
	draw_colored_polygon(cloak, COLOR_CLOAK)
	draw_polyline(PackedVector2Array([
		Vector2(-12.0, 10.0), Vector2(12.0, 10.0), Vector2(7.0, -6.0),
		Vector2(-7.0, -6.0), Vector2(-12.0, 10.0),
	]), COLOR_CLOAK_EDGE, 1.5)

	# 头部
	draw_circle(Vector2(0.0, -13.0), 6.5, COLOR_SKIN)
	draw_arc(Vector2(0.0, -13.0), 6.5, 0.0, TAU, 20, COLOR_CLOAK_EDGE, 1.5, true)
	# 兜帽（上半圆弧加粗）
	draw_arc(Vector2(0.0, -13.0), 8.0, PI, TAU, 18, COLOR_CLOAK, 5.0, true)

	# 靠近时脚下高亮圈（9.5 目标选中指示的简化版）
	if _near:
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 32, Color(0.95, 0.85, 0.4, 0.55), 2.0, true)
