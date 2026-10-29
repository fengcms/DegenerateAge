extends Node2D
## 战意觉醒的「战意升腾」特效（工程 107，由 `data/skills.json` 的 `fx = "battle_focus"` 分派）
## —— **纯视觉**，不参与伤害结算，也不代表任何范围。
##
## 技能语义是**自身增益**（`shape = self`，减伤 20% + 攻速 15%，8 秒），
## 所以没有「打到谁」要表达。特效只需回答一个问题：**我现在进入状态了吗？**
## 做法：脚下红环亮起 + 三道气浪从脚底向上冲 —— 向上是唯一不暗示范围的运动方向。
##
## 🔴 这条 fx 是「增益类技能也能有施放特效」的第一个使用者。在此之前
##    `player.cast_skill()` 的 buff 分支直接 `return true`，**根本没有调用点**
##    （工程 106 只接了攻击技能的 `_spawn_cast_fx`）。数据里写 `fx` 也不会出特效，
##    属于「配了等于没配」的静默失效 —— 所以接线和脚本必须一起做。
##
## 时间轴（总 0.65s，`< 24s` CD，绝不堆积）：
##   0.00—0.10s  脚下红环由内向外亮起
##   0.06—0.42s  三道气浪依次上升并淡出
##   0.42—0.65s  红环最后一亮后散去
##
## 🔴 `z_index` 不设：`move_child(fx, 0)` 压到角色之下，气浪从脚底「冒出来」，
##    被自己身体挡住反而更对。设成盖住玩家会让整段 8 秒的增益看起来像被火包住。

## 本 fx **不**负责范围提示：`shape = self` 本来就没有范围可提示。
## 标 true 会让守门测试要求它自报与 `range` 一致的半径，而 self 技能没有 `range`。
const DRAWS_AREA := false

const ANCHOR := "origin"

const RING_COLOR := Color("ff5a3c")
const WAVE_COLOR := Color("ff7a24")
## 内芯用偏白的黄：火苗的「亮」全靠它，主体橙一压暗就变成褐色枯草。
const CORE_COLOR := Color("ffedb8")

const LIFETIME := 0.65
const RING_END := 0.10
const WAVE_START := 0.06
const WAVE_END := 0.42

## 气浪道数。4 道两两对称地起（左内 / 右内 / 左外 / 右外），能读出「连续涌起」；
## 3 道按奇偶分边必然一边两根一边一根，预览里偏心得厉害。
const WAVES := 4
## 气浪起点到终点的屏幕高度（px）。
## 🔴 这里用**固定像素**而不是乘 `radius`：self 技能传进来的 `radius` 是 0，
##    乘出来整段特效高度为零（这正是坑 75「随机参数只能存比例」的例外 —— 该比例
##    的分母在本技能里不存在）。76px 略高于角色身高（约 62px），气浪才会「冒出头顶」；
##    58px 只能到腰（预览实测：看着像两根小棍）。
const WAVE_RISE := 92.0
## 气浪底部的半宽（px）。角色长袍半宽约 16px，7px 刚好「比身体窄一截」，
## 太宽会让整段特效看起来像被火包住（那是持续燃烧，不是起手式）。
const WAVE_HALF_W := 7.0
## 气浪的横向摆幅（px）：完全竖直像柱子，加一点左右漂移更像气流。
const WAVE_SWAY := 9.0
## 火苗骨架的取样段数：左右各采样 `FLAME_STEPS + 1` 个点。
## 6 段已经能读出弧线，再多只是徒增顶点（每个 fx 生命周期内要重画约 40 帧）。
const FLAME_STEPS := 6
## 脚下红环的横向半径（px）。地面椭圆由 `GroundFx` 自动压成 2:1。
## 34 是「比角色脚底略宽」：太窄会被角色自己的阴影盖住，太宽会被误读成范围提示。
const RING_RADIUS := 34.0

var _age := 0.0
var _rng := RandomNumberGenerator.new()
## 每道气浪的相位偏移（0—1），`_ready()` 里定一次，避免每帧抖动。
var _phases: PackedFloat32Array = PackedFloat32Array()
var _sways: PackedFloat32Array = PackedFloat32Array()

## 只读观测点（守门测试用）。
var draw_calls := 0

func _ready() -> void:
	_rng.randomize()
	_phases = PackedFloat32Array()
	_sways = PackedFloat32Array()
	for i in range(WAVES):
		_phases.append(float(i) / float(WAVES) * 0.55)
		_sways.append(_rng.randf_range(-1.0, 1.0))

func setup(ctx: Dictionary) -> void:
	global_position = ctx.get("origin", Vector2.ZERO)

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	draw_calls += 1
	_draw_ring()
	if _age < WAVE_START or _age > WAVE_END:
		return
	var fade := 1.0 - smoothstep(0.45, 1.0,
			clampf((_age - WAVE_START) / (WAVE_END - WAVE_START), 0.0, 1.0))
	for i in range(_phases.size()):
		_draw_wave(i, fade)

## 脚下红环：先亮起再收束。用 `GroundFx` 保证等距投影正确（直接 `draw_circle` 会画成正圆）。
func _draw_ring() -> void:
	var k := clampf(_age / RING_END, 0.0, 1.0)
	var fade := 1.0 - clampf((_age - RING_END) / (LIFETIME - RING_END), 0.0, 1.0)
	var r := RING_RADIUS * lerpf(0.55, 1.0, k)
	GroundFx.fill(self, Vector2.ZERO, r, Color(RING_COLOR, 0.20 * fade))
	GroundFx.outline(self, Vector2.ZERO, r, Color(RING_COLOR, 0.70 * fade), 2.2, 24)

## 一道气浪：从**身体两侧**起、向上冲的火苗，**沿骨架收尖**，越往上越细越淡。
##
## 🔴 出发点必须在身体**两侧**，不能从脚下正中心往上冲：`move_child(fx, 0)` 把本节点压到
## 角色之下，正中心起的气浪会被长袍（±16px、高 56px）整条吃掉 —— 预览 t=0.18 实测只剩
## 一个红环、三道气浪全没了，而测试是绿的（因为它只数 draw_calls）。
##
## 🔴 必须画**多边形**，不能画 `draw_polyline`：折线笔画是**等宽**的，宽度不随长度变化，
##    顶端于是被切成一条平口 —— 预览里三道气浪看着就是三块橙色的板子（像木条），
##    中间加多少拐点都救不回来。火苗的辨识度来自「底部粗、顶端收成一个尖」的剪影。
func _draw_wave(index: int, fade: float) -> void:
	var phase := float(_phases[index])
	var t := clampf((_age - WAVE_START) / (WAVE_END - WAVE_START) - phase, 0.0, 1.0)
	if t <= 0.0:
		return
	var side := -1.0 if index % 2 == 0 else 1.0
	var height := WAVE_RISE * (0.50 + 0.62 * t)
	var sway := float(_sways[index]) * WAVE_SWAY * sin(t * PI)
	# 两两对称：0/1 是内圈一对，2/3 是外圈一对。同 x 会叠成一条粗线，看不出「几股」。
	var base := Vector2(side * (12.0 + 7.0 * float(index / 2)), 3.0)
	var half := WAVE_HALF_W * (1.0 - 0.22 * t)
	var alpha := fade
	# 只画两层：亮橙主体 + 淡黄内芯。
	# 🔴 不加第三层「柔光」：半透明橙在深色地面上会与主体分离成几根更细的尖，
	#    整组读起来是「枯草」（预览 t=0.30 实测），而它带来的立体感由地面红环已能给到。
	_flame_polygon(base, height, sway, side, half, Color(WAVE_COLOR, 0.88 * alpha))
	_flame_polygon(base, height, sway, side, half * 0.45, Color(CORE_COLOR, 0.95 * alpha))

## 火苗骨架上的采样点：从脚底向上，横向带一次 S 形摆动。
func _flame_axis(base: Vector2, height: float, sway: float, side: float, u: float) -> Vector2:
	var drift := side * (4.0 + 7.0 * u * u)
	return base + Vector2(drift + sway * sin(u * PI), -height * u)

## 沿骨架左右各取样一次再回来，围成一片「底宽尖细」的火苗。
## 🔴 顶点必须**绕一圈**给（左侧上行 → 右侧下行），顺序错乱会画出自交多边形，
##    Godot 会整片静默丢弃（坑 74）。
func _flame_polygon(base: Vector2, height: float, sway: float, side: float,
		half: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(FLAME_STEPS + 1):
		var u := float(i) / float(FLAME_STEPS)
		pts.append(_flame_axis(base, height, sway, side, u) + Vector2(-_flame_half(half, u), 0.0))
	for i in range(FLAME_STEPS, -1, -1):
		var u := float(i) / float(FLAME_STEPS)
		pts.append(_flame_axis(base, height, sway, side, u) + Vector2(_flame_half(half, u), 0.0))
	draw_colored_polygon(pts, color)

## 半宽随高度收缩：底部最粗，顶端收成 0（尖）。指数 0.8 让「收」集中在上半段，
## 看起来像被气流拉长，而不是一个三角形。
func _flame_half(half: float, u: float) -> float:
	return half * pow(1.0 - u, 0.8)
