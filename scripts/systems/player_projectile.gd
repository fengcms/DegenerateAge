extends Node2D
## 远程普攻 / 法术的**纯视觉**投射物（工程 98 §4.3，工程 106 §3.1 升级）。
##
## 🔴 这个节点**不参与伤害结算**。伤害在调用点（`player.perform_attack` / `player.cast_skill`）
## 就已结算完毕，与近战共用同一套「普攻是离散事件」的口径。把它改成「命中时再结算」会同时
## 引出三个问题（方案 R4）：怪在弹道飞行中死亡 ⇒ 本次攻击白扔、击杀反馈丢失、既有普攻用例集体失效。
##
## 因此本节点没有任何对 `GameState` / `Combat` 的引用，只负责飞一小段然后 `queue_free()`。
##
## ---- 工程 106 §3.1：火球术是全法师最高频的视觉，改前只有 6px 圆点 ----
## 改前：一颗 6px 实心圆 + 一圈细弧，固定 0.14s 飞完。
## 满射程 384px ⇒ 等效速度 2743px/s ⇒ 60fps 下每帧跳 45.7px = **球径的 7.6 倍**。
## 玩家看到的不是「一颗火球飞过去」，而是「一帧一闪的抖动」。
## 而技能 CD 是 2.8—3.8 秒，普攻间隔只有 0.20—1.7 秒 ⇒ **玩家 80% 以上的攻击动作都是它**。
##
## 改后：白芯 + 技能色主体 + 外辉光 + 彗尾，命中后原地炸开一个 0.10s 的爆点。
##
## 🔴 为什么本节点可以用逐帧 `draw_circle`：
##   104 判的是「**同时实例数 × 每帧 draw 命令数**」。本节点同时最多 **2 个**
##   （飞行时长上限 0.20s + 爆点 0.10s ≈ 攻击间隔下限 0.20s 的量级），每帧约 10 条命令
##   ⇒ 合计约 20。104 的坑是 2400 件 × 4 条抗锯齿折线 ≈ 54ms/帧，量级差两个数量级。
##   但**改这一项必须实测**（106 §六），不接受「看着还行」。

const CORE_COLOR := Color("fff3d6")
const TRAIL := 6
## 彗尾间距（× 半径）与每节缩小比例。
## 🔴 拖尾的**透明度衰减是这一项的关键参数**：首版用 `0.30 × (1-t)²`，第 4 节之后
## alpha 就掉到 0.03 以下，实机截图里尾部几乎是空的（只在近处糊成一团），
## 「看得到方向」这个唯一目的没达成。改成线性 `0.55 × (1-t)` 才有尾巴形状。
const TRAIL_GAP := 1.15
const TRAIL_SHRINK := 0.08
const GLOW_RATIO := 2.6
const CORE_RATIO := 0.55
## 命中爆点寿命。它让节点比「飞到」多活 0.10s —— 峰值同时实例数按这个算。
const IMPACT_LIFETIME := 0.10
## 时长缺省按距离算（`setup` 的第 5 参传 <= 0 时启用）：2000px/s 钳在 0.10—0.20s。
## 🔴 与 `player.gd` 的 `PROJECTILE_SPEED` 保持一致 —— 这里只是缺省值，调用点会显式传。
const AUTO_SPEED := 2000.0
const AUTO_MIN := 0.10
const AUTO_MAX := 0.20

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _color := Color("ffd479")
var _radius := 6.0
var _duration := 0.14
var _elapsed := 0.0
var _heading := Vector2.RIGHT
var _impacting := false
var _impact_t := 0.0

## 由调用方在 `add_child` **之后**调用（节点已在树内，`global_position` 才有意义）。
## `duration <= 0` ⇒ 按距离自动算（工程 106 §3.1 / R3）。
func setup(from: Vector2, to: Vector2, color: Color, radius: float, duration: float = -1.0) -> void:
	_from = from
	_to = to
	_color = color
	_radius = maxf(1.0, radius)
	if duration <= 0.0:
		duration = clampf(from.distance_to(to) / AUTO_SPEED, AUTO_MIN, AUTO_MAX)
	_duration = maxf(0.05, duration)
	_elapsed = 0.0
	_impacting = false
	_impact_t = 0.0
	var dir := from.direction_to(to)
	_heading = dir if dir != Vector2.ZERO else Vector2.RIGHT
	global_position = from

func _process(delta: float) -> void:
	if _impacting:
		_impact_t += delta
		if _impact_t >= IMPACT_LIFETIME:
			queue_free()
			return
		queue_redraw()
		return
	_elapsed += delta
	var ratio := clampf(_elapsed / _duration, 0.0, 1.0)
	global_position = _from.lerp(_to, ratio)
	if ratio >= 1.0:
		# 不在这里 `queue_free`：还要放一个命中爆点，否则「打到了」这件事没有任何画面反馈。
		_impacting = true
		_impact_t = 0.0
		global_position = _to
	queue_redraw()

func _draw() -> void:
	if _impacting:
		_draw_impact()
		return
	# 彗尾：弹道是直线、方向恒定 ⇒ 沿反方向画递减圆与「记录历史位置」等价，
	# 但不需要保存历史数组、不需要每帧 append。
	# 从远到近画：近处的圆盖住远处的，接缝才不会露出「一节一节」的边。
	for i in range(TRAIL, 0, -1):
		var t := float(i) / float(TRAIL)
		var tail_p := -_heading * (_radius * TRAIL_GAP * float(i))
		var tail_r := _radius * maxf(0.2, 1.0 - TRAIL_SHRINK * float(i))
		draw_circle(tail_p, tail_r, Color(_color, 0.55 * (1.0 - t)))
	draw_circle(Vector2.ZERO, _radius * GLOW_RATIO, Color(_color, 0.26))
	draw_circle(Vector2.ZERO, _radius, _color)
	draw_circle(Vector2.ZERO, _radius * CORE_RATIO, CORE_COLOR)

## 命中爆点：白芯快速收缩 + 一圈外扩弧。
## 🔴 半径上限压在 `_radius × 3.2`（火球 = 19px）：再大就会盖住目标身体，
##    105 就是在这里踩过「落点光斑把目标整只吞掉」。
func _draw_impact() -> void:
	var k := clampf(_impact_t / IMPACT_LIFETIME, 0.0, 1.0)
	var fade := 1.0 - k
	# 三层：外扩弧（边界）+ 外扩柔光（体积）+ 收缩白芯（亮度）。
	# 🔴 只有弧没有柔光时，实机看到的是「一圈细金线」，完全不像「打中了」（预览实测）：
	#    弧的半径上限被压到 3.2 个球半径（≈19px），线宽 2px，在 1280 宽的屏幕上占比太小。
	draw_circle(Vector2.ZERO, lerpf(_radius * 1.1, _radius * 3.0, k),
		Color(_color, 0.40 * fade))
	draw_arc(Vector2.ZERO, lerpf(_radius, _radius * 3.8, k), 0.0, TAU, 20,
		Color(_color, 0.85 * fade), 2.5, true)
	draw_circle(Vector2.ZERO, _radius * maxf(0.0, 1.30 * fade), Color(CORE_COLOR, 0.85 * fade))
