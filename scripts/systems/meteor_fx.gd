extends Node2D
## 陨石术的「天降陨石 + 冲击波」特效（工程 106 §3.4，由 `data/skills.json` 的 `fx = "meteor"` 分派）
## ——**纯视觉**，不参与伤害结算（契约与 `thunder_fx.gd` 相同）。
##
## 为什么必须重做：改前 `skill_range_fx` 给陨石术画的是 **896 × 448** 的静态半透明椭圆
## （`range = 7` 格 × 64 = 448px 地面半径），横向占视口 70%、纵向 56%，淡入淡出 0.3 秒。
## 这和 105 里玩家报障的雷电术大椭圆是同一块画面 —— 区别只在于**陨石术的范围语义是对的**
## （它确实是半径 7 格的真 AoE），所以不能删，只能换成「砸下来」把它演出来。
##
## 核心设计：**用冲击波扫过表达 7 格半径**，而不是用一块静态盘。
## 静态盘是「地上有一块颜色」，玩家要靠想象补上「陨石砸下来」；
## 冲击波是**把「7 格内全部命中」这件事本身演出来** —— 环扫到哪里，哪里就该掉血。
##
## 时间轴（总 0.95s，`< 3.8s` CD，连按不会堆积）：
##   0.00—0.45s  预警：金环 + 收缩内环 + 中心十字（"正在锁定"，`0.45s` 是设计决策，见 WARN_END）
##   0.45—0.60s  陨石斜落 + 熔岩拖尾
##   0.60—0.70s  冲击环 0 → 448px 扫完（0.10s）
##   0.70—0.95s  冲击环继续外扩到 1.16R 并淡出
##
## 🔴 `z_index` 刻意**不设**：`player._spawn_cast_node()` 用 `move_child(fx, 0)` 把它压到
##   所有角色之下。冲击波要扫过半个屏幕，一旦盖在玩家身上就变成「看不见自己在哪」（106 R4）。
##   需要「盖住目标」的是雷电那种从天而降的瞬时特效，它自己设 `z_index = 1`。

## 该 fx 自己负责「技能范围提示」（工程 106 §4.2 规矩 2）。
## 陨石术是 `circle`（真 AoE）⇒ 预警环 + 冲击波就是它的范围提示 ⇒ true。
const DRAWS_AREA := true

## 本 fx 挂在上下文的哪个锚点上（工程 106 §4.2）。合法值只有 `"target"` / `"origin"`。
## 陨石落在**目标**位置，不是施法者脚下 —— 守门测试会拿这个常量与节点实际位置对照。
const ANCHOR := "target"

const WARN_COLOR := Color("ffcf8a")
const METEOR_COLOR := Color("ff9b6b")
const ROCK_COLOR := Color("6b3226")
const FLASH_COLOR := Color("fff1d6")

const LIFETIME := 0.95
## 预警时长 0.45s 是**设计决策，不是配错**：它是给玩家看的节奏，不是给敌人躲避用的
## （敌人不会躲）。🔴 不要压到 0.2s 以下 —— 那样预警环会与雷电的「一闪而落」撞成同一种节奏，
## 玩家会分不清「我要挨打」和「我在打人」。风格上必须拉开：雷电是瞬发低伤，陨石是延迟高伤。
const WARN_END := 0.45
const FALL_END := 0.60
## 冲击环 0 → 满半径用时。太快（<0.06s）会看成「闪一下」，太慢（>0.16s）会与陨石落地脱节。
const RING_GROW := 0.10
## 冲击环外扩到满半径后继续涨/淡出的时长。
const RING_DECAY := 0.25
const RING_OVERSHOOT := 1.16

## 陨石起点高度。比雷电的 320 略高：它还要砸出一个平面冲击波，起点矮了会看不出「从天而降」。
const FALL_HEIGHT := 360.0
## 斜落角度（弧度，约 15°）：垂直落下看着像「电梯」，斜一点才有抛物线感。
const FALL_TILT := 0.26
## 陨石落点在目标身体中心上方 —— 与雷电同口径（`thunder_fx.BODY_OFFSET`）。
const LAND_OFFSET := -18.0
const TRAIL := 6

var _age := 0.0
## 地面半径（= `range × TILE_W`），由 `setup()` 从调用点传入。**不在这里写死 448**。
var _radius := 448.0

## 只读观测点（守门测试用）。
var draw_calls := 0
## 实际使用的地面半径。`DRAWS_AREA` 为 true 的 fx 必须自报半径，
## 守门测试拿它与 `skills.json` 的 `range × TILE_W` 对照，抓「脚本里写死 448」这类静默错位。
var area_radius := 0.0

## 统一施法特效接口（工程 106 §4.2）。`ctx` 键：`origin` / `target` / `facing` / `radius`。
## 陨石挂在**落点**（目标位置），不是施法者脚下。
func setup(ctx: Dictionary) -> void:
	_radius = maxf(64.0, float(ctx.get("radius", 448.0)))
	area_radius = _radius
	global_position = ctx.get("target", Vector2.ZERO)

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
	if _age < FALL_END:
		# 落下阶段预警环仍在（只是不再继续收缩）：地面标记提前消失会让玩家
		# 在陨石还在天上的 0.15 秒里失去「会砸这里」的唯一依据。
		_draw_warning(1.0)
		_draw_meteor((_age - WARN_END) / (FALL_END - WARN_END))
		return
	_draw_impact(_age - FALL_END)

## 预警：金环（范围边界）+ 收缩内环（"正在锁定"）+ 中心十字（落点）。
## 🔴 填充压到 0.045 以下：448px 半径的盘一旦有点颜色就变回「地上摊了一块」，
##    本次重做的全部意义就是把那块盘替掉。
func _draw_warning(k: float) -> void:
	var a := 0.20 + 0.45 * clampf(k, 0.0, 1.0)
	GroundFx.fill(self, Vector2.ZERO, _radius, Color(WARN_COLOR, 0.045 * a))
	GroundFx.outline(self, Vector2.ZERO, _radius, Color(WARN_COLOR, 0.80 * a), 2.5, 48)
	# 内环从 1.0R 收到 0.55R：玩家能读出「快了」。
	var inner := lerpf(1.0, 0.55, clampf(k, 0.0, 1.0))
	GroundFx.outline(self, Vector2.ZERO, _radius * inner, Color(WARN_COLOR, 0.45 * a), 1.5, 40)
	# 沿外环流动的高亮段：与 `skill_range_fx` 同语汇，提示「技能正在发生」。
	var lit := PI * 0.18
	var a0 := -PI * 0.5 + TAU * clampf(k, 0.0, 1.0)
	draw_polyline(Iso.ground_arc(Vector2.ZERO, _radius, a0, a0 + lit, 12),
		Color(WARN_COLOR, 0.95 * a), 3.5, true)
	# 🔴 不再画中心十字：落点永远有一只怪，十字正好被它的身体挡掉，画了等于没画，
	#    还额外占 2 条 draw call（预览实测「看不见的装饰」）。
	#    「落点在哪」由内环收缩 + 陨石本体指示，已经足够。

## 陨石本体：熔岩球 + 沿飞行反方向的拖尾。
## 拖尾用「反方向画圆」而不是记录历史位置 —— 弹道是直线，两者等价但不需要保存数组
## （与 `player_projectile.gd` 同一口径）。
func _draw_meteor(k: float) -> void:
	var start := Vector2(-sin(FALL_TILT), -cos(FALL_TILT)) * FALL_HEIGHT
	var land := Vector2(0.0, LAND_OFFSET)
	var pos := start.lerp(land, clampf(k, 0.0, 1.0))
	var dir := (land - start).normalized()
	# 🔴 陨石本体按「7 格半径、2.1 倍伤害的终极技」定尺寸（26px ≈ 怪身体半径 18 的 1.4 倍）。
	#    首版 16px 实机看起来像一颗弹珠砸进一个 448px 的圈里，完全不匹配量级（预览实测）。
	for i in range(TRAIL, 0, -1):
		var t := float(i) / float(TRAIL)
		var p := pos - dir * (float(i) * 26.0)
		draw_circle(p, lerpf(22.0, 6.0, t), Color(METEOR_COLOR, 0.52 * (1.0 - t)))
	draw_circle(pos, 26.0, Color(ROCK_COLOR, 0.95))
	draw_circle(pos + Vector2(-4.0, -6.0), 17.0, Color(METEOR_COLOR, 0.90))
	draw_circle(pos + Vector2(-6.0, -8.0), 9.0, Color(FLASH_COLOR, 0.95))

## 命中：中心白光一闪 + 三层冲击环外扩。
## 🔴 三层线宽从外到内 10 / 5 / 2.5，顺序不能反 —— 反了白芯会被粗线糊掉（105 §3.5 踩过）。
func _draw_impact(t: float) -> void:
	var grow := clampf(t / RING_GROW, 0.0, 1.0)
	var tail := clampf((t - RING_GROW) / RING_DECAY, 0.0, 1.0)
	var r := _radius * grow * lerpf(1.0, RING_OVERSHOOT, tail)
	var fade := 1.0 - tail
	# 中心白光只在前半段：它表达的是「砸中的那一瞬」，不是持续光源。
	var flash := clampf(1.0 - t / (RING_GROW * 1.6), 0.0, 1.0)
	# 🔴 白光必须**小而短**：本节点会被 `move_child(fx, 0)` 压到角色之下，但一个 72px 半径、
	#    0.45 alpha 的米色圆仍会在怪脚下摊成一块「地砖」，玩家会看成「地上有块颜色」——
	#    那正是本次重做要消灭的观感（105 §3.5 落点光斑吞目标的同款教训）。
	if flash > 0.0:
		GroundFx.fill(self, Vector2(0.0, 6.0), 44.0 * (1.0 - flash * 0.5),
			Color(FLASH_COLOR, 0.30 * flash))
		draw_circle(Vector2(0.0, LAND_OFFSET), 16.0 * flash + 8.0, Color(FLASH_COLOR, 0.75 * flash))
	GroundFx.outline(self, Vector2.ZERO, r, Color(METEOR_COLOR, 0.22 * fade), 10.0, 48)
	GroundFx.outline(self, Vector2.ZERO, r, Color(WARN_COLOR, 0.55 * fade), 5.0, 48)
	GroundFx.outline(self, Vector2.ZERO, r, Color(FLASH_COLOR, 0.90 * fade), 2.5, 48)
