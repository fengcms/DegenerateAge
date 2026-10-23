extends Node2D
## 远程普攻 / 法术的**纯视觉**投射物（工程 98 §4.3）。
##
## 🔴 这个节点**不参与伤害结算**。伤害在调用点（`player.perform_attack` / `player.cast_skill`）
## 就已结算完毕，与近战共用同一套「普攻是离散事件」的口径。把它改成「命中时再结算」会同时
## 引出三个问题（方案 R4）：怪在弹道飞行中死亡 ⇒ 本次攻击白扔、击杀反馈丢失、既有普攻用例集体失效。
##
## 因此本节点没有任何对 `GameState` / `Combat` 的引用，只负责飞一小段然后 `queue_free()`。

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _color := Color("ffd479")
var _radius := 6.0
var _duration := 0.14
var _elapsed := 0.0

## 由调用方在 `add_child` **之后**调用（节点已在树内，`global_position` 才有意义）。
func setup(from: Vector2, to: Vector2, color: Color, radius: float, duration: float = 0.14) -> void:
	_from = from
	_to = to
	_color = color
	_radius = maxf(1.0, radius)
	_duration = maxf(0.05, duration)
	_elapsed = 0.0
	global_position = from

func _process(delta: float) -> void:
	_elapsed += delta
	var ratio := clampf(_elapsed / _duration, 0.0, 1.0)
	global_position = _from.lerp(_to, ratio)
	modulate.a = 1.0 - 0.35 * ratio
	if ratio >= 1.0:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, _radius, _color)
	draw_arc(Vector2.ZERO, _radius + 2.0, 0.0, TAU, 16, Color(_color, 0.4), 1.5, true)
