extends Node2D
## 冰咆哮的「三段推进寒潮 + 冰晶」特效（工程 106 §3.3，由 `data/skills.json` 的
## `fx = "frost_roar"` 分派）——**纯视觉**，不参与伤害结算（契约同 `thunder_fx.gd`）。
##
## 为什么必须重做：改前是「一个平面扇形楔子（288px / 90°）+ 一颗球飞向首个目标」。
## 楔子本身画法没错（`cone` 的形状语义是对的），但它是一块**静止的半透明色块**，
## 看不出「寒潮向前轰出去」；而那颗球又和楔子互不相干。
##
## 时间轴（总 0.58s，`< 2.8s` CD，连按不堆叠）：
##   0.00—0.08s  预兆：扇形边缘亮起
##   0.08—0.30s  推进：3 道断续冰棱弧从近到远依次铺开（96 / 176 / 288）
##   0.12—0.55s  冰晶：18 片菱形碎冰沿扇形向外飘、自旋、渐隐
##   0.30—0.58s  余韵：地面残留一层薄霜
##
## 🔴 **朝向必须由调用点传入**（`ctx.facing`，即 `player.gd` 用「到锁定目标的方向」算出的
##    那一份）。这里若自己取 `Vector2.RIGHT` 或自己找最近怪，就会出现「冰往左喷、右边怪掉血」。
##    守门测试用两个相反方向的敌人各打一次来抓这件事 —— 只测一个方向会假绿。
##
## 🔴 冰棱用抗锯齿折线，火舌用多边形：前者要**尖锐的断口**（折线的抗锯齿笔触），
##    后者要**柔和体积**。不为了「统一」把两者混用 —— 104 立的判据是
##    「同时实例数 × 每帧折线数」，本 fx 峰值 1 实例 × 35 条短折线，远在预算内。

## 该 fx 自己负责「技能范围提示」（工程 106 §4.2 规矩 2）。
## 冰咆哮是 `cone`（真扇形 AoE）⇒ 扇形描边 + 薄霜就是它的范围提示 ⇒ true。
const DRAWS_AREA := true

## 挂在**施法者脚下**：扇形从脚下起、朝锁定目标方向展开。
const ANCHOR := "origin"

## 扇形张角，与 `skill_range_fx` 的 cone 分支同口径（90°）。
## 🔴 不要改这里：命中判据 `player.skill_targets()` 用的是 `cos(PI / 4)`，即 ±45°。
##    两处一旦不一致，玩家会看到「冰扫过的怪没掉血」或「扇形外的怪掉了血」。
const ARC := PI * 0.5

const EDGE_COLOR := Color("cfefff")
const CORE_COLOR := Color("eaf9ff")
const FROST_COLOR := Color("a8d8ff")

const LIFETIME := 0.58
const WAVE_START := 0.08
const WAVE_END := 0.30
## 每道波从出现到淡完的时长（与相邻波的起点间隔重叠 ⇒ 读起来是「连续推进」而不是三下闪）。
const WAVE_DUR := 0.11
const WAVES := 3
## 三道波的目标半径比例（× 满半径）。等距排会像三圈靶纸，越往后跨度越大才有「轰出去」的速度感。
const WAVE_RATIOS := [0.34, 0.62, 1.0]

## 每道弧切成多少段冰棱。段与段之间留白（GLINT_FILL），连续弧会退回「一块色块」的观感。
const GLINTS := 9
const GLINT_FILL := 0.64
## 冰棱段中点向外顶出的距离（px）：让每段成为外凸的尖，而不是贴着圆弧的短直线。
const GLINT_JAG := 5.0

const SHARD_START := 0.12
const SHARD_END := 0.55
const SHARDS := 14

var _age := 0.0
## 地面半径（= `range × TILE_W` = 288），由 `setup()` 传入，**不写死**。
var _radius := 288.0
## 扇形中线朝向（屏幕方向，来自 `ctx.facing`）。
var _facing := Vector2.RIGHT
var _rng := RandomNumberGenerator.new()
var _shards: Array[Dictionary] = []

## 只读观测点（守门测试用）。
var draw_calls := 0
## 实际使用的朝向。守门测试把它与被锁定的那只怪的方向对照 ——
## 「冰往左喷、右边怪掉血」这类错位只能靠这条兜住。
var facing_used := Vector2.RIGHT
var area_radius := 0.0

## 统一施法特效接口（工程 106 §4.2）。`ctx` 键：`origin` / `target` / `facing` / `radius`。
func setup(ctx: Dictionary) -> void:
	_radius = maxf(32.0, float(ctx.get("radius", 288.0)))
	area_radius = _radius
	var dir: Vector2 = ctx.get("facing", Vector2.RIGHT)
	if dir.length() < 0.0001:
		dir = Vector2.RIGHT
	_facing = dir.normalized()
	facing_used = _facing
	global_position = ctx.get("origin", Vector2.ZERO)

func _ready() -> void:
	_rng.randomize()
	var half := ARC * 0.5
	for _i in range(SHARDS):
		_shards.append({
			"angle": _rng.randf_range(-half, half),
			# 起始距离压在 0.15—0.90 倍满半径内：都在最外沿会挤成一条线，都在脚下会糊成一团。
			"dist": _rng.randf_range(0.15, 0.90),
			"size": _rng.randf_range(5.0, 9.0),
			"spin": _rng.randf_range(0.0, TAU),
			"speed": _rng.randf_range(0.9, 1.6),
		})

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	draw_calls += 1
	# 余韵期线性渐隐；推进期与预兆期恒为 1.0。
	var fade := clampf((LIFETIME - _age) / (LIFETIME - WAVE_END), 0.0, 1.0)
	# 范围边界。预兆期更亮（此时还没有别的可看的东西），进入推进后压暗让冰棱成为主角。
	var edge := (0.58 if _age < WAVE_START else 0.38) * fade
	GroundFx.sector_outline(self, Vector2.ZERO, _facing, _radius, ARC,
		Color(EDGE_COLOR, edge), 2.0, 24)
	if _age < WAVE_START:
		return
	# 🔴 不铺扇形填充。方案 §3.3 原本写「余韵留一层薄霜（alpha ≤ 0.06）」，
	#    实测 0.06 与 0.03 都会在深色地面上糊成一块**灰面**，比冰棱本身还抢眼 ——
	#    正是火焰/陨石两条线里极力避免的「地上摊了一块颜色」。范围语义由边界弧承担，
	#    地面保持干净，冰棱与冰晶才是主角。
	_draw_waves()
	if _age > SHARD_START:
		_draw_shards(fade)

## 三道断续冰棱弧。每道在自己的窗口内 `sin` 包络进出（0→1→0），并轻微外扩。
func _draw_waves() -> void:
	var step := (WAVE_END - WAVE_START) / float(WAVES)
	for i in range(WAVES):
		var t := (_age - WAVE_START - float(i) * step) / WAVE_DUR
		if t <= 0.0 or t >= 1.0:
			continue
		_draw_wave(_radius * float(WAVE_RATIOS[i]) + 10.0 * t, sin(PI * t), i)

## 一道弧 = `GLINTS` 个外凸短折线，段间留白。
## `seed_i` 让三道波的锯齿彼此错开 —— 三波完全同形会看成同一道弧在闪三次。
func _draw_wave(radius: float, alpha: float, seed_i: int) -> void:
	var half := ARC * 0.5
	var gdir := Iso.ground_dir(_facing)
	var width := 2.4 + 2.2 * alpha
	for i in range(GLINTS):
		var t0 := -half + ARC * (float(i) + 0.06) / float(GLINTS)
		var t1 := -half + ARC * (float(i) + GLINT_FILL) / float(GLINTS)
		# 交错一半段做外凸、一半段做内凹：全部外凸会像一圈花瓣。
		var jag := GLINT_JAG * (1.0 if (i + seed_i) % 2 == 0 else -0.45)
		var p0 := Iso.from_ground(gdir.rotated(t0) * radius)
		var pm := Iso.from_ground(gdir.rotated((t0 + t1) * 0.5) * (radius + jag))
		var p1 := Iso.from_ground(gdir.rotated(t1) * radius)
		draw_polyline(PackedVector2Array([p0, pm, p1]),
			Color(EDGE_COLOR, 0.95 * alpha), width, true)
		# 每段左端加一个亮白点，模拟冰棱的折光；只在外圈那一道加满，内侧两道稀疏。
		if (i + seed_i) % 3 == 0:
			draw_circle(p0, 2.0 + 1.6 * alpha, Color(CORE_COLOR, 0.95 * alpha))

## 菱形碎冰：沿扇形向外飘、上浮、自旋、渐隐。
func _draw_shards(fade: float) -> void:
	var t := clampf((_age - SHARD_START) / (SHARD_END - SHARD_START), 0.0, 1.0)
	if t >= 1.0:
		return
	var gdir := Iso.ground_dir(_facing)
	for spec in _shards:
		var speed := float(spec["speed"])
		var dist := _radius * float(spec["dist"]) * (1.0 + 0.55 * t * speed)
		var center := Iso.from_ground(gdir.rotated(float(spec["angle"])) * dist) \
			+ Vector2(0.0, -26.0 * t * speed)
		var alpha := fade * (1.0 - t)
		if alpha <= 0.01:
			continue
		draw_colored_polygon(
			_shard_points(center, float(spec["size"]), float(spec["spin"]) + t * 4.0),
			Color(FROST_COLOR, 0.92 * alpha))

## 4 点菱形（纵向压 0.62 —— 碎冰是被风带着斜飘的，正菱形看起来像静止的贴纸）。
func _shard_points(center: Vector2, size: float, spin: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in range(4):
		var a := spin + TAU * float(k) * 0.25
		pts.append(center + Vector2(cos(a) * size, sin(a) * size * 0.62))
	return pts
