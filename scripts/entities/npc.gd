class_name Npc
extends Node2D
## 功能性 NPC 占位实体（产品文档 6.3 安全区与通用交互；M1-8 先实现货郎 6.4）。
##
## 占位素材（R5）：程序化绘制斗篷人形；头顶名称 / 提示用 Label（走项目主题的
## SystemFont CJK 字体，避免 draw_string 用引擎内置字体导致中文方框）。
## 交互派发：由 scripts/world/game.gd 统一处理 E / 鼠标点击；本节点暴露
## shop_id、近距和命中判定，不自己抢输入。
## 碰撞：MVP 不加碰撞体（避免把玩家卡住）；M3 补静态碰撞与逐句对话推进。

## 交互半径 2 格（6.3 安全区交互距离）
const INTERACT_RANGE := 2.0 * 64.0

const COLOR_CLOAK := Color("7d6ac8")
const COLOR_CLOAK_EDGE := Color("3b3268")
const COLOR_SKIN := Color("e8c9a0")

## 对应 shops.json 的 npcId；为空表示纯对话 NPC（M2 任务官等）。
@export var shop_id: String = ""
## 功能角色（M2）：shop = 货郎（开交易面板）；quest = 任务官（开任务面板）。
## 交互派发见 scripts/world/game.gd::_try_interact。
@export var role: String = "shop"
## 头顶名称；为空时从配置表取名。
@export var npc_name: String = ""
## 文本配置的自我介绍，功能面板打开时显示。
@export var greeting: String = ""

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

## 屏幕点击命中：覆盖人物与头顶名称；由世界统一决定接近和交互。
func contains_screen_point(point: Vector2) -> bool:
	var local := get_global_transform_with_canvas().affine_inverse() * point
	return Rect2(-38.0, -52.0, 76.0, 68.0).has_point(local)

func _draw() -> void:
	var cloak_color := Color("956b4b") if role == "blacksmith" else (Color("547784") if role == "warehouse" else COLOR_CLOAK)
	var edge := Color("463226") if role == "blacksmith" else (Color("273c44") if role == "warehouse" else COLOR_CLOAK_EDGE)
	# 脚下阴影
	draw_set_transform(Vector2(0.0, 8.0), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 斗篷（梯形）+ 描边
	var cloak := PackedVector2Array([
		Vector2(-12.0, 10.0), Vector2(12.0, 10.0), Vector2(7.0, -6.0), Vector2(-7.0, -6.0),
	])
	draw_colored_polygon(cloak, cloak_color)
	draw_polyline(PackedVector2Array([
		Vector2(-12.0, 10.0), Vector2(12.0, 10.0), Vector2(7.0, -6.0),
		Vector2(-7.0, -6.0), Vector2(-12.0, 10.0),
	]), edge, 1.5)

	# 头部
	draw_circle(Vector2(0.0, -13.0), 6.5, COLOR_SKIN)
	draw_arc(Vector2(0.0, -13.0), 6.5, 0.0, TAU, 20, edge, 1.5, true)
	# 兜帽（上半圆弧加粗）
	draw_arc(Vector2(0.0, -13.0), 8.0, PI, TAU, 18, cloak_color, 5.0, true)
	if role == "blacksmith":
		draw_rect(Rect2(-7.0, -2.0, 14.0, 11.0), Color("55585d"))

	# 靠近时脚下高亮圈（9.5 目标选中指示的简化版）
	if _near:
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 32, Color(0.95, 0.85, 0.4, 0.55), 2.0, true)
