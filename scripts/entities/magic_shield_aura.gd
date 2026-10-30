class_name MagicShieldAura
extends Node2D
## 玩家魔法盾的竖向护罩画层；前后两实例夹住角色贴图，共用同一轮廓。
## 只画世界空间的身体外观，不承担地面范围、碰撞或伤害判定；隐藏后不提交绘制命令。
##
## 工程 106 §3.5：它是一个**持续 30 秒**的状态，改前却完全静止 —— 玩家只能靠 UI 图标
## 判断盾还在不在身上。现在加了「呼吸 + 能量网」两件事，让它自己证明自己活着。
##
## 🔴 `outline_bounds()` **一分不动**：`tests/magic_shield_test.gd` 用它回归「护罩上沿与
##    脚底锚点」，骑乘/站立两套尺寸是玩家判断「盾罩住了整个身体」的唯一依据。
##    这次只改 `_draw` 里的画法。
## 🔴 呼吸只调 alpha，不动几何 —— 尺寸起伏会让人误以为护罩在「缩」，读成快到期了。

const SEGMENTS := 48
const SHIELD_FILL := Color(0.23, 0.79, 0.94, 0.10)
const SHIELD_GLOW := Color(0.36, 0.90, 1.0, 0.14)
const SHIELD_EDGE := Color(0.60, 0.95, 1.0, 0.85)

## 呼吸周期与幅度：1.8 秒一个来回，alpha 在 0.55—0.85 之间起伏。
## 🔴 幅度不要超过 ±0.2：0.85 以上会盖住角色贴图，0.5 以下静态截图里几乎看不见盾。
const BREATH_PERIOD := 1.8
const BREATH_MID := 0.70
const BREATH_AMP := 0.15

## 能量网：护罩内侧的纵向经线。
## 🔴 6 条在 86px 宽的轮廓里太稀 —— 同一时刻只有 3—4 条 `|cos|` 不贴近轮廓、没被压暗，
##    实拍是「隐约几根竖线」，读不成笼子（预览实测）。8 条才有网的感觉。
const NET_LINES := 8
## 30 秒转一圈 —— 察觉不到「在转」，但静态护罩的呆板感消失。转太快会变成风扇。
const NET_PERIOD := 30.0
const NET_COLOR := Color(0.72, 0.96, 1.0)
const NET_ALPHA := 0.38
const NET_SEGMENTS := 18

@export var front_pass := false
var _mounted := false
var _t := 0.0

## 只读观测点（守门测试用）。
var draw_calls := 0
## 当前呼吸系数（0.55—0.85）与能量网相位（弧度）。测试用它断言「在动」，
## 而不是去数 draw 命令 —— 静止的护罩也能每帧重绘。
var breath := 1.0
var net_phase := 0.0

## 骑乘外观比站立外观宽高各多一档；只在骑乘状态变化时重建轮廓。
func set_mounted(value: bool) -> void:
	if _mounted == value:
		return
	_mounted = value
	queue_redraw()

## 供场景回归检查护罩上沿与脚底锚点，单位为玩家节点的本地像素。
func outline_bounds() -> Rect2:
	var center := Vector2(0.0, -43.0 if _mounted else -37.0)
	var radius := Vector2(64.0, 78.0) if _mounted else Vector2(43.0, 56.0)
	return Rect2(center - radius, radius * 2.0)

## 呼吸与能量网需要每帧重绘。**不可见时直接返回**：无盾/断蓝/死亡时这一层是隐藏的
## （`_sync_magic_shield_visual()` 只切 visible），而 Godot 的 visible 不阻止 `_process`，
## 不早退的话 30 秒常态下会白跑每秒 8 条折线。
func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	breath = BREATH_MID + BREATH_AMP * sin(TAU * _t / BREATH_PERIOD)
	net_phase = TAU * _t / NET_PERIOD
	queue_redraw()

## 后层铺极淡色罩，前层描轮廓 + 能量网；不盖住角色面部和动作帧。
func _draw() -> void:
	draw_calls += 1
	var bounds := outline_bounds()
	var center := bounds.get_center()
	var radius := bounds.size * 0.5
	var points := PackedVector2Array()
	for index in range(SEGMENTS + 1):
		var angle := TAU * float(index) / float(SEGMENTS)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	if front_pass:
		draw_polyline(points, Color(SHIELD_GLOW, SHIELD_GLOW.a * breath), 6.0, true)
		draw_polyline(points, Color(SHIELD_EDGE, SHIELD_EDGE.a * breath), 1.8, true)
		_draw_net(center, radius)
	else:
		points.resize(SEGMENTS)
		draw_colored_polygon(points, Color(SHIELD_FILL, SHIELD_FILL.a * breath))

## 纵向经线（「笼子」）：每条都是从护罩上极经侧面到下极的半椭圆，横向宽度按 `cos(相位)` 压缩。
##   相位差 60° × 6 条 + 全局相位 ⇒ 线条从正中（直立）滑向边缘（弯曲贴轮廓）并变淡，
##   另一端同时有新的线从边缘淡入 —— 读起来是「网在绕身体转」，而不是「线在左右滑」。
## 🔴 `|cos|` 接近 1 时经线与外轮廓几乎重合，必须压暗，否则看起来像轮廓被加粗了一圈。
func _draw_net(center: Vector2, radius: Vector2) -> void:
	for k in range(NET_LINES):
		var wx := cos(TAU * float(k) / float(NET_LINES) + net_phase)
		var alpha := NET_ALPHA * breath * (1.0 - absf(wx) * 0.65)
		if alpha <= 0.01:
			continue
		var pts := PackedVector2Array()
		for i in range(NET_SEGMENTS + 1):
			var ang := -PI * 0.5 + PI * float(i) / float(NET_SEGMENTS)
			pts.append(center + Vector2(cos(ang) * radius.x * wx, sin(ang) * radius.y))
		draw_polyline(pts, Color(NET_COLOR, alpha), 1.4, true)
