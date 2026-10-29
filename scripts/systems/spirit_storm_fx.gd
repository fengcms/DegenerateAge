extends Node2D
## 灵刃风暴的「三波旋刃内收」特效（工程 107，由 `data/skills.json` 的 `fx = "spirit_storm"` 分派）
## —— **纯视觉**，不参与伤害结算。
##
## 技能语义是**半径 4 格、3 段伤害、最多 8 个目标**（`circle` / `hits 3` / `maxTargets 8`）。
## 「3 段」是最容易被特效丢掉的信息 —— 画一个圈会让玩家以为它和旋风斩是同一个东西。
## 所以这里**一波一段**：三波刃光从外缘向内收，收完一波掉一段血，节奏与结算同源。
##
## 半径 4 格 = 256px，是全武士最大的范围。用「由外向内的收束」而不是「由内向外炸开」，
## 是因为收束的终点在玩家身上 —— 一眼就能读出「围过来的都被切了」。
##
## 时间轴（总 0.72s，`< 12s` CD）：
##   0.00—0.08s  地面外环亮起（范围提示，同时交代 4 格边界）
##   0.08s 起     三波刃光，每波延后 0.13s，单波 0.26s 由 R 收到 0.28R
##   0.60—0.72s   外环与余刃一起淡出
##
## 🔴 `z_index` 不设：`move_child(fx, 0)` 压到角色之下。4 格半径要盖掉半个屏，
##    一旦盖在玩家头上就是「看不见自己在哪」（106 R4）。

## 本 fx 自己负责范围提示：外环就是 4 格边界。
const DRAWS_AREA := true

const ANCHOR := "origin"

const BLADE_COLOR := Color("cfe4ff")
const CORE_COLOR := Color("ffffff")
const RING_COLOR := Color("8fb8f0")

const LIFETIME := 0.72
const RING_IN := 0.08
## 三波与 `hits: 3` 一一对应。⚠ 改段数时必须同步改这里，否则「3 段」在画面上变成
## 「2 段」或「4 段」，玩家会以为结算次数与看到的次数不一致（`tests/mage_fx_casting_test`
## 只核对数量与数据一致，抓不到「观感对不上」）。
const WAVES := 3
## 每波起始延后。0.13 × 2 + 0.26 = 0.52 ⇒ 最后一波在 0.60 收完，正好留给淡出。
const WAVE_LEAD := 0.13
const WAVE_DUR := 0.26
## 每波刃光条数。4 条在 256px 环上间距约 0.4rad，既能读出「一圈都被切」又不糊成实心环。
const BLADES := 4
## 单条刃光的弧长（弧度）。0.55 ≈ 31°，在 256px 上约 140px 长。
const BLADE_ARC := 0.55
## 收到半径的多少。0.28 ⇒ 收进玩家身位附近才消失，太早收完会像「环缩了一下」。
const INNER := 0.28

var _age := 0.0
var _rng := RandomNumberGenerator.new()

var _radius := 256.0
## 每波的起始角偏移与抖动，`_ready()` 里定一次。
var _offsets: PackedFloat32Array = PackedFloat32Array()
## 只读观测点（守门测试用）。
var draw_calls := 0
var area_radius := 0.0

func _ready() -> void:
	_rng.randomize()
	_offsets = PackedFloat32Array()
	for i in range(WAVES):
		# 每波整体错开 2π/3，三波叠加时不会在同一角度反复叠亮（那会烧成一个白点）。
		_offsets.append(TAU * float(i) / float(WAVES) + _rng.randf_range(-0.2, 0.2))

func setup(ctx: Dictionary) -> void:
	global_position = ctx.get("origin", Vector2.ZERO)
	_radius = maxf(64.0, float(ctx.get("radius", 256.0)))
	area_radius = _radius

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	draw_calls += 1
	var tail := 1.0 - clampf((_age - (RING_IN + WAVE_LEAD * float(WAVES - 1) + WAVE_DUR))
		/ maxf(0.01, LIFETIME - (RING_IN + WAVE_LEAD * float(WAVES - 1) + WAVE_DUR)), 0.0, 1.0)
	_draw_ring(tail)
	for i in range(WAVES):
		_draw_wave(i)

## 外环：快速扩到满径后留一圈淡描边，交代「4 格到这里」。
func _draw_ring(tail: float) -> void:
	var grow := clampf(_age / RING_IN, 0.0, 1.0)
	if grow < 1.0:
		GroundFx.outline(self, Vector2.ZERO, _radius * lerpf(0.45, 1.0, grow),
			Color(RING_COLOR, 0.50), 2.4, 40)
	else:
		GroundFx.outline(self, Vector2.ZERO, _radius, Color(RING_COLOR, 0.22 * tail), 1.8, 40)

## 一波：4 条刃光同时从外缘收到内圈，边收边淡。
func _draw_wave(index: int) -> void:
	var start := RING_IN + WAVE_LEAD * float(index)
	var t := clampf((_age - start) / WAVE_DUR, 0.0, 1.0)
	if t <= 0.0 or t >= 1.0:
		return
	# 半径用 ease-in（先慢后快）：看起来像「被吸进去」，匀速会更像机械缩放。
	var radius := _radius * lerpf(1.0, INNER, t * t)
	var alpha := 1.0 - t
	var base_angle := float(_offsets[index])
	for b in range(BLADES):
		# 每波转 0.6rad，让「三波」不至于看起来是同一张图重播三次。
		var center_angle := base_angle + TAU * float(b) / float(BLADES) + 0.6 * t
		var pts := _arc_points(radius, center_angle - BLADE_ARC * 0.5, center_angle + BLADE_ARC * 0.5)
		if pts.size() < 2:
			continue
		draw_polyline(pts, Color(BLADE_COLOR, 0.18 * alpha), 12.0, true)
		draw_polyline(pts, Color(BLADE_COLOR, 0.52 * alpha), 4.8, true)
		draw_polyline(pts, Color(CORE_COLOR, 0.82 * alpha), 1.6, true)

## 地面弧 → 屏幕折线。必须走 `Iso.from_ground()`：等距投影下地面正圆在屏幕上是 2:1 椭圆。
func _arc_points(radius: float, from_a: float, to_a: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := maxi(6, GroundFx.segments_for(radius) / 4)
	for i in range(steps + 1):
		var a := lerpf(from_a, to_a, float(i) / float(steps))
		pts.append(Iso.from_ground(Vector2(cos(a), sin(a)) * radius))
	return pts
