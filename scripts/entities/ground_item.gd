class_name GroundItem
extends Node2D
## 地面掉落物（产品文档 9.9 拾取交互 / 3.14 自动拾取）。
##
## 持有物品实例（Dictionary）；渲染占位图形，颜色按品质 / 品类区分。
## 拾取规则（9.9）：玩家靠近 ≤1.5 格即自动入包（无需点击，G 仅控制自动战斗顺路拾取）；
## 亦可左键点击拾取；背包满则留地并提示，不静默丢失。
## 地面存在时长 60s 后消失（避免全屏遗留物）。

const PICKUP_RANGE_PX := 1.5 * 64.0   # 1.5 格（7.1：tileW=64）
const LIFETIME := 60.0                 # 地面存在时长（s）
const BLOCK_TOAST_CD := 1.5            # 「背包已满」提示节流（s）

@export var item: Dictionary = {}

var _life: float = LIFETIME
var _blocked_cd: float = 0.0
var _phase: float = 0.0

func _ready() -> void:
	add_to_group("ground_items")
	_phase = randf() * TAU
	# 出场小跳（视觉反馈）
	scale = Vector2(0.2, 0.2)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()

func _physics_process(delta: float) -> void:
	_phase += delta * 3.0
	_blocked_cd = maxf(0.0, _blocked_cd - delta)

	# 存在时长衰减（最后 5s 闪烁提示）
	_life -= delta
	if _life <= 0.0:
		_fade_out()
		return

	# 靠近自动拾取（9.9）
	var player := _get_player()
	if player != null and player.global_position.distance_to(global_position) <= PICKUP_RANGE_PX:
		_try_pickup()

## 拾取一次。金币 → 入金币（受上限约束，不占背包）；其余 → 入背包。
## 成功 → 广播 + 提示 + 移除；背包满 / 金币满 → 留地并节流提示（不静默丢失）。
func _try_pickup() -> bool:
	if item.is_empty():
		queue_free()
		return true

	# 金币：直接入账（6.2，达上限后不再拾取并提示）
	if String(item.get("kind", "")) == "coin":
		if GameState.gold_is_capped():
			if _blocked_cd <= 0.0:
				_blocked_cd = BLOCK_TOAST_CD
				EventBus.toast_requested.emit("金币已达上限", "danger")
			return false
		var got := GameState.add_gold(int(item.get("gold", 0)))
		EventBus.item_picked.emit("coin")
		EventBus.toast_requested.emit("拾取：金币 +%d" % got, "pickup")
		queue_free()
		return true

	if Inventory.add(GameState.inventory, item):
		EventBus.item_picked.emit(String(item.get("itemId", "")))
		EventBus.inventory_changed.emit()
		EventBus.toast_requested.emit("拾取：" + ItemUtil.display_name(item), "pickup")
		queue_free()
		return true
	if _blocked_cd <= 0.0:
		_blocked_cd = BLOCK_TOAST_CD
		EventBus.toast_requested.emit("背包已满，无法拾取：" + ItemUtil.display_name(item), "danger")
	return false

func _fade_out() -> void:
	set_physics_process(false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)

func _get_player() -> Node2D:
	var p := get_tree().get_first_node_in_group("player")
	if p == null or p.get("is_dead") == true:
		return null
	return p as Node2D

## 左键点击拾取（9.9）。
func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_pickup()

func _draw() -> void:
	var kind := String(item.get("kind", "misc"))
	var col := ItemUtil.kind_color(kind)
	if kind == "equip":
		col = ItemUtil.quality_color(String(item.get("quality", "common")))
	# 地面阴影
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 物品图形（上下浮动）：金币为圆片，其余为菱形（占位素材，R5）
	var lift := sin(_phase) * 2.0
	var c := Vector2(0, -16 + lift)
	if kind == "coin":
		draw_circle(c, 8.0, col)
		draw_arc(c, 8.0, 0.0, TAU, 18, Color(0, 0, 0, 0.55), 1.5, true)
		draw_circle(c + Vector2(-2, -2), 2.0, Color(1, 1, 1, 0.7))
		return
	var pts := PackedVector2Array([
		c + Vector2(0, -11), c + Vector2(9, 0), c + Vector2(0, 11), c + Vector2(-9, 0),
	])
	draw_colored_polygon(pts, col)
	var outline := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
	draw_polyline(outline, Color(0, 0, 0, 0.55), 1.5)
	# 品质 / 品类高光点
	draw_circle(c + Vector2(0, -2), 2.5, Color(1, 1, 1, 0.75))
