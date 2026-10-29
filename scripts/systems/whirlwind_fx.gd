extends Node2D
## 旋风斩的「绕身旋刃」特效（工程 107，由 `data/skills.json` 的 `fx = "whirlwind"` 分派）
## —— **纯视觉**，不参与伤害结算（契约与 `thunder_fx.gd` 相同）。
##
## 技能语义是**以自身为中心、半径 2.2 格内的环周攻击**（`circle` / 无 `maxTargets`），
## 所以特效要表达的是「一圈都砍到了」，而不是「朝前砍一刀」。
## 做法：两道错开 180° 的弧形刀光绕自身转满一整圈 —— 转向本身就是「环周」的证据，
## 转完一圈时，围绕玩家的每一只怪都至少被刀光扫过一次。
##
## 时间轴（总 0.36s，`< 4.5s` CD）：
##   0.00—0.06s  地面环快速扩到满径（范围提示）
##   0.00—0.30s  两道刀光从 -90° 转到 270°（正好一圈），带 3 段拖尾
##   0.30—0.36s  刀光与地面环一起淡出
##
## 🔴 `z_index` 不设：`move_child(fx, 0)` 会把本节点压到角色之下。
##    刀光要「看得见在转」就不能盖住玩家 —— 压在地面层正好读作「贴地扫过」。

## 本 fx 自己负责范围提示：地面环就是 2.2 格的边界。
const DRAWS_AREA := true

## 圆形技能以自身为中心 ⇒ 挂在脚下。
const ANCHOR := "origin"

const BLADE_COLOR := Color("d8f0ff")
const CORE_COLOR := Color("ffffff")
const RING_COLOR := Color("9fd0ff")

const LIFETIME := 0.36
const RING_IN := 0.06
const SPIN_END := 0.30

## 刀光条数：2 条（对角）比 1 条更能读出「环周」，比 4 条更不容易糊成一圈白。
const BLADES := 2
## 每条刀光的弧长（弧度）。0.9 ≈ 52°，在 141px 半径上约 127px 长。
## 🔴 不要超过 PI：到半圈就会与另一条接上，变成「一整圈同时亮」，转速感消失。
const BLADE_ARC := 0.9
## 拖尾段数。3 段已经能读出方向；再加就是纯发光，且折线条数翻倍。
const TRAILS := 3
## 刀光轨道半径占技能半径的比例：略微内收（0.86），让它落在怪的脚下而不是飘在头顶。
const ORBIT := 0.86

var _age := 0.0
var _rng := RandomNumberGenerator.new()

var _radius := 140.8
## 起始角：让刀光从「施法者正上方」起转，看起来像从肩后抡出。
var _spin0 := -PI * 0.5
## 只读观测点（守门测试用）。
var draw_calls := 0
var area_radius := 0.0

func _ready() -> void:
	_rng.randomize()
	_spin0 = -PI * 0.5 + _rng.randf_range(-0.12, 0.12)

func setup(ctx: Dictionary) -> void:
	global_position = ctx.get("origin", Vector2.ZERO)
	_radius = maxf(48.0, float(ctx.get("radius", 140.8)))
	area_radius = _radius

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	draw_calls += 1
	var fade := 1.0 - clampf((_age - SPIN_END) / (LIFETIME - SPIN_END), 0.0, 1.0)
	_draw_ring(fade)
	if _age > SPIN_END:
		return
	# 转动进度 0 → 1 对应整整一圈（TAU）。用 ease-out 更接近「抡出去后收力」。
	var k := clampf(_age / SPIN_END, 0.0, 1.0)
	var spin := TAU * (1.0 - pow(1.0 - k, 2.0))
	_draw_blades(spin, fade)

## 地面环：0 → 满径的快速外扩，之后留一圈淡描边交代边界。
func _draw_ring(fade: float) -> void:
	var grow := clampf(_age / RING_IN, 0.0, 1.0)
	if grow < 1.0:
		GroundFx.outline(self, Vector2.ZERO, _radius * lerpf(0.4, 1.0, grow),
			Color(RING_COLOR, 0.55 * fade), 2.2, 32)
	else:
		GroundFx.outline(self, Vector2.ZERO, _radius, Color(RING_COLOR, 0.24 * fade), 1.8, 32)

## 两道刀光。每道画 1 条主线 + 3 段逐级变淡的拖尾（拖尾 = 角度上略微落后）。
## 🔴 三层粗细由外到内（辉光 → 外光 → 白芯）：顺序反了白芯会被粗线糊掉。
func _draw_blades(spin: float, fade: float) -> void:
	var orbit := _radius * ORBIT
	for b in range(BLADES):
		var head := _spin0 + spin + TAU * float(b) / float(BLADES)
		for t in range(TRAILS + 1):
			var back := float(t) * 0.10
			var a := 1.0 - float(t) / float(TRAILS + 1)
			var pts := _arc_points(orbit, head - BLADE_ARC - back, head - back)
			if pts.size() < 2:
				continue
			draw_polyline(pts, Color(BLADE_COLOR, 0.20 * a * fade), 11.0, true)
			draw_polyline(pts, Color(BLADE_COLOR, 0.58 * a * fade), 4.6, true)
			if t == 0:
				draw_polyline(pts, Color(CORE_COLOR, 0.92 * fade), 1.8, true)

## 地面弧 → 屏幕折线。走 `Iso.from_ground()` 是硬约束：等距投影下地面正圆在屏幕上
## 必须是 2:1 椭圆，直接用 `draw_arc` 画出的是正对镜头的正圆（工程 104 的老问题）。
func _arc_points(radius: float, from_a: float, to_a: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := maxi(6, GroundFx.segments_for(radius) / 3)
	for i in range(steps + 1):
		var a := lerpf(from_a, to_a, float(i) / float(steps))
		pts.append(Iso.from_ground(Vector2(cos(a), sin(a)) * radius))
	return pts
