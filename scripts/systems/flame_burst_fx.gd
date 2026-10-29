extends Node2D
## 火焰喷发的「以自身为中心向外喷火苗」特效（工程 106 §3.2，由 `data/skills.json` 的
## `fx = "flame_burst"` 分派）——**纯视觉**，不参与伤害结算（契约同 `thunder_fx.gd`）。
##
## 为什么必须重做：改前它是「脚下 448×224 半透明椭圆 + **一颗球飞向首个目标**」。
## 球飞出去这件事本身就在撒谎 —— 火焰喷发是以自身为中心的圆形 AoE（`shape = circle`），
## 场上却没有任何东西从脚下向外扩散。玩家看到的是「法师扔了个火球」，而伤害打的是
## 半径 3.5 格内的所有怪（工程 106 §1.3）。
##
## 时间轴（总 0.50s，`< 3.2s` CD，连按不堆叠）：
##   0.00—0.10s  预兆：脚下细橙环从 1.06R 收到 1.0R
##   0.10—0.22s  爆发：18 道火苗在地面半径 0.30—1.0 R 处向上冒出
##   0.22—0.50s  余韵：火苗上飘 + 渐隐
##   爆发期叠加 3 次亮度脉冲（`hits: 3` 是同一帧瞬时结算，见 PULSE_GAP）
##
## 🔴 **火苗是向上升的，不是沿半径射出去的** —— 这是本特效最重要的一条。
##    预览第一版把火舌画成「从脚下沿径向拉长到边界」的锥形，实拍是 18 根金色星芒
##    （像爆炸特效，不像火焰）。火焰的物理方向永远是向上（屏幕 -y）；
##    径向只负责「烧在哪一段地面上」。`_draw_tongue()` 因此分成两个量：
##    `dist`（贴地点离脚下多远）× `height`（向上冒多高）。
##
## 🔴 用 `draw_colored_polygon` 而不是抗锯齿折线：火焰要柔和体积，多边形填充比折线便宜
##    一个数量级；18 道 × 2 层若都走折线就是 36 条/帧 —— 按 104 的口径是无谓开销。
##    冰棱才用折线（它要尖锐断口）。
##
## 🔴 不设 `z_index`：`player._spawn_cast_node()` 已用 `move_child(fx, 0)` 把它压到所有
##    角色之下。近战怪会站在 3.5 格内，火苗若盖在怪身上就变成「怪在火里看不见」。

## 该 fx 自己负责「技能范围提示」（工程 106 §4.2 规矩 2）。
## 火焰喷发是 `circle`（真 AoE）⇒ 外圈描边就是它的范围提示 ⇒ true。
const DRAWS_AREA := true

## 本 fx 挂在上下文的哪个锚点上（工程 106 §4.2）。合法值只有 `"target"` / `"origin"`。
## 火焰喷发以**自身**为中心 ⇒ origin。守门测试拿它与节点实际位置对照。
const ANCHOR := "origin"

const WARN_COLOR := Color("ffb066")
const AREA_COLOR := Color("ff9a4d")
## 三层火焰：外梢偏暗红 → 中段橙 → 根芯亮黄。见 `_draw_tongue()`。
const OUTER_COLOR := Color("c2450e")
const MID_COLOR := Color("ff8226")
const CORE_COLOR := Color("ffe9a8")

const LIFETIME := 0.50
const WARN_END := 0.10
const BURST_END := 0.22

## `hits: 3` 在 `player.cast_skill` 内层循环里是**同一帧瞬时结算**，视觉上做 3 次亮度脉冲。
## 窗口刻意收在 `PULSE_GAP × 2`（= 第 3 个峰）：窗口结束时包络正好回到 1.0，
## 不会在余韵起点出现一次亮度跳变。
const PULSE_GAP := 0.09
const PULSE_WINDOW := PULSE_GAP * 2.0

## 火苗数量。少于 12 道围不成一圈；多于 24 道在 224px 半径上会挤成一片糊。
const TONGUES := 20
## 其中**中心**那几簇的数量：它们贴地更近（`dist` 0.05—0.28）但更高。
## 🔴 光有一圈外沿火苗时，中心是空的 —— 看起来像「地上画了个火圈」，不像「从脚下喷发」。
const INNER_TONGUES := 5
## 每道火苗相对均分角的最大抖动（弧度，≈12°）。均匀分布会像齿轮。
const SHAPE_JITTER := 0.21
## 火苗贴地点的最小半径比例（× 满半径），其余用 `sqrt` 采样到 1.0。
## 🔴 偏外采样：均匀分布会让内圈也堆满火苗，整片地面烧起来像「火海」，
##    而「以自身为中心喷发」要读成**一圈**往外烧。
const DIST_MIN := 0.45
## 外沿火苗高度比例（× 满半径）：0.12—0.26 × 224 ≈ 27—58px。
## 首版 0.16—0.30 配 18—34 的宽度，比例接近 1:2，实拍是一圈尖顶帐篷（预览实测）。
const HEIGHT_MIN := 0.12
const HEIGHT_MAX := 0.26
## 中心火苗更高：它是「喷发」的源头，高度必须压过外沿那一圈才算爆发。
const HEIGHT_INNER_MIN := 0.24
const HEIGHT_INNER_MAX := 0.38
## 火苗左右摇摆的频率与幅度（幅度是高度的比例）。
## 🔴 没有摇摆就是一圈静止的三角锥 —— 火焰靠「在动」才成立，这是观感的分水岭。
const SWAY_SPEED := 13.0
const SWAY_RATIO := 0.16

var _age := 0.0
## 地面半径（= `range × TILE_W` = 224），由 `setup()` 从调用点传入。**不在这里写死 224**。
var _radius := 224.0
var _rng := RandomNumberGenerator.new()
## 每道火苗的固定随机参数（`_ready` 生成一次）。**不能每帧重算** —— 那样火苗会逐帧抖动成噪点。
var _tongues: Array[Dictionary] = []

## 只读观测点（守门测试用）。
var draw_calls := 0
## 实际使用的地面半径。`DRAWS_AREA` 为 true 的 fx 必须自报半径，
## 守门测试拿它与 `skills.json` 的 `range × TILE_W` 对照，抓「脚本里写死半径」这类静默错位。
var area_radius := 0.0

## 统一施法特效接口（工程 106 §4.2）。`ctx` 键：`origin` / `target` / `facing` / `radius`。
func setup(ctx: Dictionary) -> void:
	_radius = maxf(32.0, float(ctx.get("radius", 224.0)))
	area_radius = _radius
	global_position = ctx.get("origin", Vector2.ZERO)

func _ready() -> void:
	_rng.randomize()
	for i in range(TONGUES):
		var inner := i < INNER_TONGUES
		# 🔴 内圈与外圈**各自均分**，不是拿同一个均分角的前 5 个 ——
		#    那样 5 簇高火会挤在同一个扇区（预览实测：中心烧成一坨，其余方向是空的）。
		var angle := TAU * (float(i) + 0.5) / float(INNER_TONGUES) if inner \
			else TAU * float(i - INNER_TONGUES) / float(TONGUES - INNER_TONGUES)
		_tongues.append({
			"angle": angle + _rng.randf_range(-SHAPE_JITTER, SHAPE_JITTER),
			"dist": _rng.randf_range(0.05, 0.28) if inner
				else DIST_MIN + (1.0 - DIST_MIN) * sqrt(_rng.randf()),
			"height": _rng.randf_range(HEIGHT_INNER_MIN, HEIGHT_INNER_MAX) if inner
				else _rng.randf_range(HEIGHT_MIN, HEIGHT_MAX),
			"wide": _rng.randf_range(26.0, 44.0) if inner else _rng.randf_range(22.0, 40.0),
			# 摇摆相位：20 道同相位会整体左右平移，看着像整片被风吹，而不是各自跳动。
			"phase": _rng.randf_range(0.0, TAU),
		})

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	draw_calls += 1
	var burst_k := clampf((_age - WARN_END) / (BURST_END - WARN_END), 0.0, 1.0)
	# 余韵期线性渐隐；爆发期与预兆期恒为 1.0（分母为正，clamp 到 1）。
	var fade := clampf((LIFETIME - _age) / (LIFETIME - BURST_END), 0.0, 1.0)
	# 上飘量压到 16：首版 30 会把火苗顶端顶出范围环，读成「打到圈外去了」（预览实测）。
	var lift := clampf((_age - BURST_END) / (LIFETIME - BURST_END), 0.0, 1.0) * 16.0
	if _age < WARN_END:
		var k := _age / WARN_END
		GroundFx.outline(self, Vector2.ZERO, _radius * lerpf(1.06, 1.0, k),
			Color(WARN_COLOR, 0.35 + 0.45 * k), 2.0, 48)
	# 范围边界：半径恒等于命中半径，全程可见并随余韵淡出。
	# 🔴 不做地表填充 —— 224px 的盘一旦有颜色就变回「地上摊了一块」，正是本次要替掉的东西。
	GroundFx.outline(self, Vector2.ZERO, _radius, Color(AREA_COLOR, 0.55 * fade), 2.5, 48)
	if burst_k <= 0.0:
		return
	var grown := ease(burst_k, 0.35)
	var alpha := fade * _pulse()
	for spec in _tongues:
		_draw_tongue(spec, grown, lift, alpha)

## 单道火苗 = 三层火焰从外到内、从梢到根逐层变亮变短。
##
## 🔴 两个独立量：`dist` 决定**烧在哪里**（贴地点，走地面投影），`height` 决定**冒多高**
##    （屏幕向上）。首版只有一个「长度」量、沿径向拉长，画出来是星芒。
## 🔴 必须分层：单层等亮度的多边形实拍是「一片发光的三角锥」，不像火。
##    真实火焰是**根部白热、越往上越暗越红**，所以三层的高度是 1.0 / 0.82 / 0.44 递减，
##    亮度是暗红橙 → 橙 → 亮黄递增。
func _draw_tongue(spec: Dictionary, grown: float, lift: float, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var d := Vector2(cos(float(spec["angle"])), sin(float(spec["angle"])))
	# 贴地点（地面）→ 屏幕。这是火苗「烧在哪里」的唯一依据，必须走 `Iso.from_ground`。
	var base := Iso.from_ground(d * (_radius * float(spec["dist"])))
	var height := _radius * float(spec["height"]) * grown
	if height <= 1.0:
		return
	var half := float(spec["wide"]) * 0.5 * (0.45 + 0.55 * grown)
	# 火苗被"喷"的方向带歪一点点（纯向上的 20 根会像一圈蜡烛），
	# 再加上**各自相位**的左右摇摆 —— 火焰靠「在动」才成立。
	var sway := sin(_age * SWAY_SPEED + float(spec["phase"])) * height * SWAY_RATIO
	var lean := Iso.from_ground(d * (height * 0.16)) + Vector2(sway, 0.0)
	var side := Vector2(half, 0.0)
	# 着火点：贴地一小片白热。没有它，火苗像是「浮在地面上方」，有它才「从地里烧起来」。
	# 走 `GroundFx.fill` 而不是 `draw_circle`：地面光斑必须是 2:1 的椭圆，
	# 正圆在等距视角里读成「一个球落在砖上」（见 `ground_fx.gd` 文件头）。
	GroundFx.fill(self, base, half * 0.9, Color(CORE_COLOR, 0.30 * alpha))
	_flame_layer(base, side, height, lift, lean, Color(OUTER_COLOR, 0.58 * alpha), 1.0, 1.0)
	_flame_layer(base, side, height, lift, lean, Color(MID_COLOR, 0.80 * alpha), 0.82, 0.72)
	_flame_layer(base, side, height, lift, lean, Color(CORE_COLOR, 0.95 * alpha), 0.44, 0.42)

## 一层火焰多边形。`scale_h` / `scale_w` 是相对最高/最宽层的缩放。
## 6 点：左下 → 右下 → 右腰 → 右尖 → 左尖 → 左腰（绕一圈，**不要跨着首尾**）。
## 🔴 尖端不是一个点、而是两个错位点：单点必然画成等腰三角（尖顶帐篷），
##    错位才像被风吹斜的火舌。首版 5 点自交多边形整片消失（三角化失败、不报错），是同一类坑。
func _flame_layer(base: Vector2, side: Vector2, height: float, lift: float,
		lean: Vector2, color: Color, scale_h: float, scale_w: float) -> void:
	var h := height * scale_h
	var w := side * scale_w
	var mid := base + Vector2(0.0, -h * 0.44 - lift * 0.5) + lean * 0.55
	var tip := base + Vector2(0.0, -h - lift) + lean
	var tip_r := tip + w * 0.20
	var tip_l := tip - w * 0.42 + Vector2(0.0, h * 0.06)
	draw_colored_polygon(PackedVector2Array([
		base - w, base + w, mid + w * 0.95, tip_r, tip_l, mid - w * 0.95,
	]), color)

## 三段亮度脉冲：`|cos(π·t/0.09)|` 在 t = 0 / 0.09 / 0.18 处各出一峰。
func _pulse() -> float:
	var t := _age - WARN_END
	if t < 0.0 or t > PULSE_WINDOW:
		return 1.0
	return 0.62 + 0.38 * absf(cos(PI * t / PULSE_GAP))
