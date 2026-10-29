extends Node2D
## 裂地斩的「地面裂开」特效（工程 107，由 `data/skills.json` 的 `fx = "earth_cleave"` 分派）
## —— **纯视觉**，不参与伤害结算（契约与 `thunder_fx.gd` 相同）。
##
## 为什么是「裂缝」而不是「一道斩击光弧」：
## 技能语义是**扇形范围内最多 3 个目标**（`cone` / `range 3.0` / `maxTargets 3`），
## 光弧会让人以为只能打一条线；裂缝从脚下向前裂开、越远越宽，正好覆盖整个扇形，
## 而且「地面被砸开」天然解释了「为什么站在那里的怪都受伤了」。
##
## 时间轴（总 0.42s，`< 3.0s` CD，连按不堆积）：
##   0.00—0.08s  预兆：扇形描边亮一下 + 主裂缝在地下「透光」
##   0.08—0.22s  裂缝张开：主裂缝由近到远推进，两侧分叉同时张开，碎石弹起
##   0.22—0.42s  缝内余烬淡出，碎石落回
##
## 🔴 `z_index` 不设：`player._spawn_cast_node()` 会 `move_child(fx, 0)` 把它压到所有角色之下。
##    裂缝是地面细节，盖在玩家身上就变成「看不见自己在哪」（106 R4）。

## 本 fx 自己负责技能范围提示（工程 106 §4.2 规矩 2）。
## 裂地斩是 `cone` ⇒ 扇形描边 + 裂缝张开就是它的范围提示 ⇒ true。
const DRAWS_AREA := true

## 挂在施法者脚下（`cone` 以自身为原点向前展开），守门测试会核对这个常量。
const ANCHOR := "origin"

## 扇形张角（弧度）。🔴 必须与 `player.skill_targets()` 里 cone 分支的命中判据
## `facing.dot(offset.normalized()) >= cos(PI / 4)` **同源** —— 两者不一致会变成
## 「怪站在描边外却掉血」或「站在描边内却没事」。守门测试逐值核对这个常量。
const ARC := PI * 0.5

const CRACK_COLOR := Color("3e2417")
const GLOW_COLOR := Color("ff7a2e")
const EMBER_COLOR := Color("ffc46b")
const DUST_COLOR := Color("c9b08a")

const LIFETIME := 0.42
const WARN_END := 0.08
const OPEN_END := 0.22

## 主裂缝的折点数。太少是一根锯齿直线，太多会糊成一团。
const MAIN_POINTS := 9
## 主裂缝横向摆动的最大幅度（占半径比例）。0.11 ≈ 21px，足够看出「歪」但不至于裂到扇形外。
const MAIN_WOBBLE := 0.11
## 分叉条数：2 条最稳（3 条以上在 192px 长的缝上会挤成蜈蚣）。
const FORKS := 2
## 每颗碎石的顶点数：五边形。⚠ 必须**绕一圈**给顶点（坑 74：自交多边形会被 Godot
## 三角化成空，整片静默消失，连报错都没有）。
const DEBRIS_SIDES := 5
const DEBRIS := 7

var _age := 0.0
var _rng := RandomNumberGenerator.new()

## 地面半径（= `range × TILE_W`），由 `setup()` 传入，**不在这里写死 192**。
var _radius := 192.0
var _facing := Vector2.RIGHT

## 只读观测点（守门测试用）。
var draw_calls := 0
## 实际使用的地面半径与朝向。`DRAWS_AREA` 为 true 的 fx 必须自报半径，
## 守门测试拿它与 `skills.json` 的 `range × TILE_W` 对照。
var area_radius := 0.0
var facing_used := Vector2.RIGHT

## 裂缝形状：主缝 + 分叉。**在 `_ready()` 里只存比例**（0—1），像素量在 `_draw()` 里乘 `_radius`。
## 🔴 `_ready()` 早于 `setup(ctx)`，此时 `_radius` 还是缺省值；直接存像素会让
##    「数据改了半径」时裂缝长度纹丝不动（坑 75）。
var _main: PackedVector2Array = []
var _main_offsets: PackedFloat32Array = PackedFloat32Array()
var _forks: Array[PackedVector2Array] = []
## 碎石：每颗 = [贴地距离比例, 横向偏移比例, 弹起高度比例, 相位]
var _debris: Array[PackedFloat32Array] = []

func _ready() -> void:
	_rng.randomize()
	_build_shape()

## 统一施法特效接口（工程 106 §4.2）。`ctx` 键：`origin` / `target` / `facing` / `radius`。
func setup(ctx: Dictionary) -> void:
	global_position = ctx.get("origin", Vector2.ZERO)
	_radius = maxf(64.0, float(ctx.get("radius", 192.0)))
	area_radius = _radius
	var aim: Variant = ctx.get("facing", Vector2.RIGHT)
	if aim is Vector2 and (aim as Vector2) != Vector2.ZERO:
		_facing = (aim as Vector2).normalized()
	facing_used = _facing

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	draw_calls += 1
	if _age < WARN_END:
		_draw_warning(_age / WARN_END)
		return
	# 张开进度：0 → 1 于 OPEN_END，之后保持不变，只做整体淡出。
	var open := clampf((_age - WARN_END) / (OPEN_END - WARN_END), 0.0, 1.0)
	var fade := 1.0 - clampf((_age - OPEN_END) / (LIFETIME - OPEN_END), 0.0, 1.0)
	_draw_fan(open, fade)
	_draw_cracks(open, fade)
	_draw_debris(open, fade)

## 预兆：只画扇形描边，且刻意压淡 —— 它表达的是「这里马上要裂」，不是范围宣告。
func _draw_warning(k: float) -> void:
	var a := 0.10 + 0.22 * clampf(k, 0.0, 1.0)
	GroundFx.sector_outline(self, Vector2.ZERO, _facing, _radius, ARC,
		Color(GLOW_COLOR, a), 2.0, 28)

## 扇形内部的极淡地面暖光：由内向外铺开，把「伤害范围」说清楚。
## 🔴 不填满整个扇形：3.0 格的扇形已是 192px 见方，实心填充会盖掉地面纹理与掉落物。
func _draw_fan(open: float, fade: float) -> void:
	var r := _radius * lerpf(0.35, 1.0, open)
	GroundFx.sector(self, Vector2.ZERO, _facing, r, ARC, Color(GLOW_COLOR, 0.10 * fade))
	GroundFx.sector_outline(self, Vector2.ZERO, _facing, _radius, ARC,
		Color(GLOW_COLOR, 0.34 * fade * (1.0 - 0.5 * open)), 2.0, 28)

## 主裂缝 + 分叉。三层由外到内：焦土暗边 → 橙红裂缝 → 亮黄内芯。
## 🔴 顺序不能反：先画亮芯再画暗边，亮芯会被糊掉，裂缝看起来像一条灰线。
func _draw_cracks(open: float, fade: float) -> void:
	var pts := _crack_points(_main, _main_offsets, open)
	if pts.size() >= 2:
		draw_polyline(pts, Color(CRACK_COLOR, 0.62 * fade), 9.0, true)
		draw_polyline(pts, Color(GLOW_COLOR, 0.72 * fade), 4.6, true)
		draw_polyline(pts, Color(EMBER_COLOR, 0.88 * fade), 1.8, true)
	for fork in _forks:
		var fp := _crack_points(fork, PackedFloat32Array(), open)
		if fp.size() < 2:
			continue
		draw_polyline(fp, Color(CRACK_COLOR, 0.55 * fade), 6.0, true)
		draw_polyline(fp, Color(GLOW_COLOR, 0.55 * fade), 2.6, true)

## 碎石：沿裂缝两侧弹起再落回。用凸多边形（便宜），不用折线。
## 🔴 顶点必须绕一圈给（坑 74）。
func _draw_debris(open: float, fade: float) -> void:
	for spec in _debris:
		var dist := float(spec[0]) * _radius * open
		var side := float(spec[1]) * _radius * 0.5
		var lift := float(spec[2]) * _radius * 0.42
		var phase := float(spec[3])
		# 抛物线：0 → 1 表示「飞起到落回」，落回时间按相位错开，看起来才不是一个整体。
		var t := clampf((open - phase * 0.35) / maxf(0.01, 1.0 - phase * 0.35), 0.0, 1.0)
		var height := lift * 4.0 * t * (1.0 - t)
		var base := Iso.from_ground(_facing * dist + _facing.orthogonal() * side)
		var center := base - Vector2(0.0, height)
		var size := _radius * 0.022 * (1.0 + 0.5 * phase)
		var poly := PackedVector2Array()
		for i in range(DEBRIS_SIDES):
			var angle := TAU * float(i) / float(DEBRIS_SIDES)
			poly.append(center + Vector2(cos(angle), sin(angle) * 0.8) * size)
		draw_colored_polygon(poly, Color(DUST_COLOR, 0.78 * fade))

## 把「比例形状」展开成屏幕折线。`offsets` 为空表示不带横向摆动（分叉用它自己的形状）。
func _crack_points(shape: PackedVector2Array, offsets: PackedFloat32Array, open: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(shape.size()):
		var p := shape[i]
		# p.y 是「推进到半径的百分之几」，乘 open 得到「裂到这里了」。
		var along := p.y * open
		if along <= 0.001:
			break
		var lateral := p.x
		if i < offsets.size():
			lateral += float(offsets[i])
		out.append(Iso.from_ground(_facing * (along * _radius) + _facing.orthogonal() * (lateral * _radius)))
	if out.size() == 1:
		out.append(out[0])
	return out

## 生成裂缝形状（全部是比例值，不含像素）。
func _build_shape() -> void:
	_main = PackedVector2Array()
	_main_offsets = PackedFloat32Array()
	# 主缝从脚下（0.02）裂到扇形边缘（1.0），横向小幅摆动 —— 完全笔直看着像贴图。
	for i in range(MAIN_POINTS):
		var along := lerpf(0.02, 1.0, float(i) / float(MAIN_POINTS - 1))
		_main.append(Vector2(0.0, along))
		_main_offsets.append(_rng.randf_range(-MAIN_WOBBLE, MAIN_WOBBLE) * along)
	_forks.clear()
	for k in range(FORKS):
		# 分叉从主缝中段向两侧斜甩，且**不到边缘**：到边缘会和扇形描边绞在一起。
		var start := 0.32 + 0.18 * float(k)
		var side := 1.0 if k % 2 == 0 else -1.0
		var pts := PackedVector2Array()
		var lateral := 0.0
		for i in range(5):
			var t := float(i) / 4.0
			lateral = side * (0.06 + 0.30 * t) * (0.8 + 0.4 * _rng.randf())
			pts.append(Vector2(lateral, start + (1.0 - start) * 0.55 * t))
		_forks.append(pts)
	_debris.clear()
	for i in range(DEBRIS):
		_debris.append(PackedFloat32Array([
			_rng.randf_range(0.15, 0.95),
			_rng.randf_range(-0.85, 0.85),
			_rng.randf_range(0.35, 1.0),
			float(i) / float(DEBRIS),
		]))
