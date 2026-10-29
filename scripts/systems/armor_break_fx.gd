extends Node2D
## 破甲重击的「甲片崩飞」特效（工程 107，由 `data/skills.json` 的 `fx = "armor_break"` 分派）
## —— **纯视觉**，不参与伤害结算。
##
## 技能语义是**单体穿透重击 + 6 秒破甲**（`single` / `range 1.5` / `defensePierce 0.3`）。
## 单体技能最容易做错的地方是「画一个圈」——那会让玩家以为它是 AoE（工程 105 的原始报障）。
## 所以这里**不画任何地面范围**，只画「打在一个点上」：
## 中心白闪 + 甲片四散 + 一条从施法者方向砸过来的冲击线。
##
## 时间轴（总 0.45s，`< 6s` CD）：
##   0.00—0.05s  蓄力：中心一点白，快速变大
##   0.05—0.16s  爆开：白闪 + 冲击线 + 甲片同时甩出
##   0.16—0.45s  甲片减速飘落、渐隐
##
## 🔴 `z_index` 不设：`move_child(fx, 0)` 压到角色之下。甲片是「掉在地上的东西」，
##    盖在怪身上会挡住玩家判断这只怪还活着没有。

## 单体技能没有范围可提示 ⇒ false（标 true 会让守门测试要求它自报与 `range` 一致的半径，
## 而一旦真去画那个半径，它就会变回一个「看着像 AoE」的圈 —— 正是 105 要修的问题）。
const DRAWS_AREA := false

## 挂在**被击中目标**身上，不是施法者脚下。
const ANCHOR := "target"

const SHARD_COLOR := Color("ffd479")
const EDGE_COLOR := Color("a8732a")
const FLASH_COLOR := Color("fffdf0")

const LIFETIME := 0.45
const CHARGE_END := 0.05
const BURST_END := 0.16

## 甲片数量。6 片能铺满一圈又不至于挤成金团；再多就得靠更小的尺寸才分得开。
const SHARDS := 6
## 每片顶点数。⚠ 必须**绕一圈**给（坑 74：自交多边形的三角化结果不可靠，整片会静默消失）。
const SHARD_SIDES := 4
## 甲片飞出的最远距离（px）。目标身宽约 34px，飞出 ~2 个身位就有「崩开」感。
const SHARD_REACH := 46.0
## 冲击线长度（px）：从施法者方向砸过来的那道白线。
const IMPACT_LEN := 40.0

var _age := 0.0
var _rng := RandomNumberGenerator.new()

## 从施法者指向本节点的方向（单位向量）。`ctx` 里只有两个点，方向在这里算，
## 不在调用点算 —— 调用点不该知道「这个 fx 要往哪甩」。
var _hit_dir := Vector2.RIGHT
## 每片甲片的 [起始角(rad), 飞出距离系数, 尺寸系数, 旋转相位]
var _specs: Array[PackedFloat32Array] = []

## 只读观测点（守门测试用）。
var draw_calls := 0

## 🔴 `z_index = 1`，与雷电同理：甲片是从**被击中的怪身上**崩出来的，必须在怪之上，
##    否则 `move_child(fx, 0)` 会把它压到怪下面，只剩几粒碎片从圆的边缘漏出来
##    （预览 t=0.11 实测：整片碎片都被目标挡住，看着像「什么都没发生」）。
##    这是「地面系压到底层」规则的一个显式例外，必须自己声明，不能靠调用点特判。
func _ready() -> void:
	z_index = 1
	_rng.randomize()
	_specs.clear()
	for i in range(SHARDS):
		# 均匀分布 + 小幅抖动：完全均匀看着像烟花，完全随机会有扎堆。
		var angle := TAU * (float(i) + 0.5) / float(SHARDS) + _rng.randf_range(-0.25, 0.25)
		_specs.append(PackedFloat32Array([
			angle,
			_rng.randf_range(0.65, 1.0),
			_rng.randf_range(0.75, 1.15),
			_rng.randf_range(0.0, TAU),
		]))

func setup(ctx: Dictionary) -> void:
	global_position = ctx.get("target", Vector2.ZERO)
	var origin: Variant = ctx.get("origin", Vector2.ZERO)
	if origin is Vector2:
		var dir := global_position - (origin as Vector2)
		if dir.length_squared() > 0.0001:
			_hit_dir = dir.normalized()

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	draw_calls += 1
	if _age < CHARGE_END:
		_draw_charge(_age / CHARGE_END)
		return
	var burst := clampf((_age - CHARGE_END) / (BURST_END - CHARGE_END), 0.0, 1.0)
	var fade := 1.0 - clampf((_age - BURST_END) / (LIFETIME - BURST_END), 0.0, 1.0)
	_draw_impact(burst, fade)
	_draw_shards(burst, fade)

## 蓄力：一个很小的亮点。刻意极小 —— 0.05s 内它就会被白闪取代，做大反而像卡了一帧。
func _draw_charge(k: float) -> void:
	draw_circle(Vector2.ZERO, 2.0 + 4.0 * clampf(k, 0.0, 1.0), Color(FLASH_COLOR, 0.55 * k))

## 爆开：中心由亮变淡的白闪 + 一条逆向砸来的冲击线。
## 🔴 冲击线只在 burst < 1 时画：它表达「刚刚被砸中」，拖长会变成持续的连接线。
func _draw_impact(burst: float, fade: float) -> void:
	if burst < 1.0:
		var flash := 1.0 - burst
		draw_circle(Vector2.ZERO, lerpf(6.0, 20.0, burst), Color(FLASH_COLOR, 0.72 * flash))
		var from := -_hit_dir * IMPACT_LEN * (1.0 - burst * 0.5)
		draw_line(from, Vector2.ZERO, Color(FLASH_COLOR, 0.85 * flash), 3.2, true)
		draw_line(from, Vector2.ZERO, Color(SHARD_COLOR, 0.45 * flash), 7.0, true)

## 甲片：向外甩出后轻微下坠（+y 是屏幕下方，等距投影里就是「落地」）。
func _draw_shards(burst: float, fade: float) -> void:
	for spec in _specs:
		var angle := float(spec[0])
		var reach := SHARD_REACH * float(spec[1])
		# ease-out：一上来就快，之后减速 —— 「被崩开」而不是「匀速飞走」。
		var travel := reach * (1.0 - pow(1.0 - burst, 2.4))
		var center := Vector2(cos(angle), sin(angle) * 0.8) * travel
		center.y += 9.0 * burst * burst
		var size := 5.4 * float(spec[2]) * lerpf(1.0, 0.55, burst)
		var spin := float(spec[3]) + burst * 3.2
		var poly := PackedVector2Array()
		for i in range(SHARD_SIDES):
			var a := TAU * float(i) / float(SHARD_SIDES) + spin
			poly.append(center + Vector2(cos(a), sin(a)) * size)
		draw_colored_polygon(poly, Color(EDGE_COLOR, 0.85 * fade))
		# 内侧再叠一片更小更亮的，做出「甲片有厚度」的错觉 —— 比描边便宜得多。
		var inner := PackedVector2Array()
		for i in range(SHARD_SIDES):
			var a := TAU * float(i) / float(SHARD_SIDES) + spin
			inner.append(center + Vector2(cos(a), sin(a)) * size * 0.55)
		draw_colored_polygon(inner, Color(SHARD_COLOR, 0.92 * fade))
