extends Node2D
## 雷电术的落雷特效（工程 105，由 `data/skills.json` 的 `fx = "thunder"` 分派）——**纯视觉**。
##
## 为什么不复用 `player_projectile`：雷电是**瞬时天降**，不是「扔一颗球」。
## 投射物是通用远程实现，对火球合适，对雷电就丢了身份。
##
## 🔴 不参与伤害结算。伤害在 `player.cast_skill` 调用点已结算完毕
##   （契约见 `player_projectile.gd` 顶端）。若把结算挂到「闪电落地」，会引出
##   目标在弹道中死亡 ⇒ 本次攻击白扔 / 击杀反馈丢失 / 既有用例集体失效。
##
## 🔴 为什么这里可以用抗锯齿折线，而工程 104 把折线判成性能坑：
##   104 的口径是「**2400 件 × 每帧** 重画折线 ≈ 54 ms/帧」。本节点：
##     · 同时最多 **1 个实例**（寿命 0.26s < 雷电术 CD 0.6s）
##     · 每帧 **3 条**折线、每条 9 点，约 3—5 µs
##   判据是「**同时实例数 × 每帧折线数**」，不是「折线本身坏」。
##   闪电的形状每帧都在变，无法预渲染 —— 这正是 104 里 `ring()` 与 `outline()`
##   分工的同一个逻辑：形状恒定走预渲染纹理，形状**算出来**的才走实时折线。
##   若将来要做「一次雷击多个目标」，**先按 104 的口径重新量再铺开**。
##
## 时间轴（总 0.26s）：
##   0.00—0.05s  头顶竖光柱预兆（越来越亮）
##   0.05—0.14s  主雷劈下 + 落点光斑 + 冲击环
##   0.14—0.26s  余电：折线渐隐，分叉甩出

const BOLT_COLOR := Color("9ad8ff")
const CORE_COLOR := Color("f2fbff")
const SPOT_COLOR := Color("e8f8ff")

const LIFETIME := 0.26
const WARN_END := 0.05
const SPOT_END := 0.12

## 落雷起点相对目标的高度。目标在屏幕中心时约覆盖上半屏的 1/3，够「从天而降」。
const BOLT_HEIGHT := 170.0
## 闪电终点 = 目标身体中心。怪物绘制中心在 `-radius * 0.6`（`monster.gd:1353`），
## radius 17—22 ⇒ 约 -10 ~ -13，取 -12 让闪电**穿过身体**而不是停在头顶。
const BODY_OFFSET := -12.0
## 落点光斑 = 脚下地面，与怪物阴影同高（不与身体中心重合，否则像贴在胸口）。
const GROUND_OFFSET := 8.0
## 预兆光柱的下端：身体上方 40px，留出「还没落下来」的空隙。
const WARN_STOP := -52.0

const SEGMENTS := 8
const JITTER := 7.0
const BRANCH_COUNT := 2
## 每帧完全随机会像噪点闪烁；2 帧重算一次更接近电弧的持续放电。
const JITTER_INTERVAL := 0.032

var _age := 0.0
var _jitter_t := 0.0
var _rng := RandomNumberGenerator.new()
var _bolt := PackedVector2Array()
var _branches: Array[PackedVector2Array] = []

## 只读观测点（守门测试用）。
var draw_calls := 0

func _ready() -> void:
	# 闪电是「从天而降」，必须盖住被击中的怪，否则怪的身体会挡住落点。
	# z_index 只改绘制顺序，不参与 y-sort 排序，不会让怪穿模。
	z_index = 1
	_rng.randomize()
	_rebuild()

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	_jitter_t -= delta
	if _jitter_t <= 0.0:
		_jitter_t = JITTER_INTERVAL
		_rebuild()
	queue_redraw()

func _draw() -> void:
	draw_calls += 1
	if _age < WARN_END:
		_draw_warning(_age / WARN_END)
		return
	var t := (_age - WARN_END) / (LIFETIME - WARN_END)
	# 前 35% 全亮，之后线性渐隐 —— 余电阶段仍在放电，不是「一键消失」。
	var alpha := 1.0 - clampf((t - 0.35) / 0.65, 0.0, 1.0)
	# 外光先画（粗、淡），白芯后画（细、亮）：顺序反了白芯会被外光糊掉。
	draw_polyline(_bolt, Color(BOLT_COLOR, 0.55 * alpha), 4.5, true)
	draw_polyline(_bolt, Color(CORE_COLOR, alpha), 1.4, true)
	for i in range(_branches.size()):
		var pts: PackedVector2Array = _branches[i]
		draw_polyline(pts, Color(BOLT_COLOR, 0.5 * alpha), 1.4, true)
	if _age < SPOT_END:
		_draw_impact((_age - WARN_END) / (SPOT_END - WARN_END))

## 预兆：一道越来越亮的细光柱，位置与主雷完全对齐（不能偏，否则落雷会「跳一下」）。
func _draw_warning(k: float) -> void:
	var a := 0.10 + 0.16 * clampf(k, 0.0, 1.0)
	draw_line(Vector2(0.0, -BOLT_HEIGHT), Vector2(0.0, WARN_STOP),
		Color(BOLT_COLOR, a), 2.0, true)

## 落点：地面光斑 + 快速外扩的冲击环。两者都是**落点标记**，不是范围提示 ——
## 半径 18px ≈ 1/4 格，与「单体技能画半径 416px 的圈」是两回事（工程 105 §1.2）。
func _draw_impact(k: float) -> void:
	var fade := 1.0 - clampf(k, 0.0, 1.0)
	var ground := Vector2(0.0, GROUND_OFFSET)
	GroundFx.fill(self, ground, 18.0, Color(SPOT_COLOR, 0.30 * fade))
	GroundFx.outline(self, ground, lerpf(18.0, 34.0, clampf(k, 0.0, 1.0)),
		Color(BOLT_COLOR, 0.55 * fade), 2.0, 32)

func _rebuild() -> void:
	_bolt = _zigzag(Vector2(0.0, -BOLT_HEIGHT), Vector2(0.0, BODY_OFFSET))
	_branches.clear()
	for i in range(BRANCH_COUNT):
		var idx := _rng.randi_range(2, SEGMENTS - 2)
		var origin: Vector2 = _bolt[idx]
		var side := 1.0 if i % 2 == 0 else -1.0
		var pts := PackedVector2Array([origin])
		var cur := origin
		# 分叉向两侧斜下方甩出，像被击穿后溢出的电弧；不是平行副路（平行会看成双闪）。
		for _step in range(3):
			cur += Vector2(side * _rng.randf_range(6.0, 14.0), _rng.randf_range(8.0, 16.0))
			pts.append(cur)
		_branches.append(pts)

## 等分取点 + 横向抖动；两端不抖，保证首尾精确贴合起点与目标身体中心。
func _zigzag(from: Vector2, to: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(SEGMENTS + 1):
		var p := from.lerp(to, float(i) / float(SEGMENTS))
		if i > 0 and i < SEGMENTS:
			p.x += _rng.randf_range(-JITTER, JITTER)
		pts.append(p)
	return pts
