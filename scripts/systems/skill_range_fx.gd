extends Node2D
## 主动技能的短暂程序范围提示；与伤害结算解耦，不改变实际命中范围。
##
## 🔴 刻意不一致（工程 53 §4.3）：本 FX 画的是**地面椭圆**，而施法门控与命中筛选
## （`player.gd` 的 `range × TILE_W`）仍是屏幕度量 —— 所以提示范围**小于**实际命中范围
## （横向等宽、纵向只有一半）。方向与 Boss 预警相反：Boss 预警画小了玩家会白挨打，
## 这里画小了只是「以为打不到、其实打到了」，属于可容忍的保守提示。
## 不要为了「看着一致」补成 ×√2 —— 那会让玩家以为打得到的位置其实打不到。
##
## 🔴 工程 105：**单体技能（`shape = "single"`）不绘制任何范围提示。**
## `range` 字段在两类技能上的含义根本不同：
##   - `circle` / `cone`：`range` 是 AoE 半径 / 扇形半径 ⇒ 画成几何是对的；
##   - `single`：`range` 是**到目标的距离上限**，不是半径。当成半径画等于告诉玩家
##     「这一片都会被打」，而实际只打一只 —— 这是**误导性提示**，不是「画得不够好看」。
##     雷电术（6.5 格）曾因此被画成半径 416px、横向占屏幕 65% 的大椭圆（工程 105 §1.2）。
## 单体也不缺「打谁」的提示：被锁定的怪脚下本就有 `monster.gd` 的青色选中环。
##
## 🔴 未识别的 `shape` **不绘制 + 报警**，不得再靠 `else` 兜底。让兜底分支承担语义分派，
## 会让以后新增的形状（如 `line`）静默变成圆盘 —— 与坑清单第 64 条「过宽防线在前提
## 消失后静默变成新 bug」同构。
##
## 工程 106 §4.3：本文件的绘制从「静态半透明盘 + 线性淡出」升级为「亮度包络 + 填充生长
## + 沿边流动高亮」。这是**一处改动、全部 AoE 受益**（武士的裂地斩 / 旋风斩 / 灵刃风暴同吃）。
## 🔴 只有**填充**可以生长，**描边半径恒定** —— 见 `FILL_START` 处的注释。
## 🔴 带 `fx` 字段的技能不再 spawn 本节点（`player.gd` §4.2 规矩 2），范围提示由专属 fx 承担。

const FX_COLOR := Color(0.46, 0.91, 0.88)
const LIFETIME := 0.3

## ---- 亮度包络与生长（工程 106 §4.3）----
## 包络：前 `RISE` 份时长「亮起来」，之后按 `pow(1-k, FALLOFF)` 收尾。
## 🔴 不用 `1 - k` 线性淡出：线性尾巴在最后一帧还留一层淡影，看着像「没散干净」。
const RISE := 0.2
const FALLOFF := 1.4
## 填充 / 描边的峰值透明度（再乘包络）。填充从 0.10 提到 0.20×env≈0.14 —— 比原来略亮，
## 但仍然远低于「看着像地上摊了一块颜色」的阈值。
const FILL_ALPHA := 0.20
const INK_ALPHA := 0.75
## 填充半径从 `FILL_START × R` 生长到 `1.0 × R`（爆发感），占用前 `GROW_END` 份时长。
## 🔴 **描边半径恒定**：外圈是玩家判断「站这里会不会被打」的唯一依据。
##    任何「生长 / 呼吸」都只能作用在填充上 —— 提示的几何正确性优先于好看（105 §1.3 的教训）。
const FILL_START := 0.92
const GROW_END := 0.35
## 沿边缘流动的高亮段长度（弧度）：圆 1/4 圈，扇形 1/8 圈。
const SWEEP_CIRCLE := PI * 0.5
const SWEEP_CONE := PI * 0.25

var shape := "circle"
var radius := Iso.TILE_W   # 默认 1 格（7.1：tileW=64，单一来源 Iso.TILE_W）
var facing := Vector2.RIGHT
var age := 0.0

## 只读观测点（守门测试用）。
## `draw_calls` 统计 `_draw` 被调用次数（含早退）；`ground_draws` 统计**真正发出**的
## 地面几何绘制次数。只断言前者会被「函数里有个 return」骗过，必须两者配合。
var draw_calls := 0
var ground_draws := 0

## 该形状是否应该画地面几何 —— **唯一判据**，`_draw` 与守门测试共用同一份。
## 分成两个函数是为了把「合法的无绘制（single）」和「未识别的 shape」区分开：
## 前者静默早退，后者必须报警，否则新增形状会被兜底成圆盘（坑清单第 64 条同构）。
static func draws_ground(shape_id: String) -> bool:
	return shape_id == "circle" or shape_id == "cone"

static func is_known(shape_id: String) -> bool:
	return shape_id == "single" or draws_ground(shape_id)

func _process(delta: float) -> void:
	age += delta
	if age >= LIFETIME:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	draw_calls += 1
	if not draws_ground(shape):
		if not is_known(shape):
			# 未识别：显式报警。新增 shape 必须同时更新 draws_ground / is_known。
			push_warning("SkillRangeFx: 未识别的 shape「%s」，不绘制范围提示（工程 105）" % shape)
		# 工程 105：单体（single）没有「范围」可提示。**不要**为了「给点反馈」补一个小圈 ——
		# 那会把「误导性范围」缩水成「迷惑性光斑」，语义仍然是错的。
		# 落点反馈由 `thunder_fx.gd` 之类的施法特效负责，与本提示无关。
		return
	var k := clampf(age / LIFETIME, 0.0, 1.0)
	var env := clampf(k / RISE, 0.0, 1.0) * pow(1.0 - k, FALLOFF)
	if shape == "cone":
		_draw_cone(k, env)
		return
	# 到这里只可能是 circle（`draws_ground` 已把其余形状全部滤掉）。
	# 刻意**不写 `else`**：兜底分支承担语义分派正是 105 那个 bug 的成因。
	_draw_circle(k, env)

func _draw_circle(k: float, env: float) -> void:
	var grow := lerpf(FILL_START, 1.0, clampf(k / GROW_END, 0.0, 1.0))
	GroundFx.fill(self, Vector2.ZERO, radius * grow, Color(FX_COLOR, FILL_ALPHA * env))
	GroundFx.outline(self, Vector2.ZERO, radius, Color(FX_COLOR, INK_ALPHA * env), 2.0, 40)
	ground_draws += 2
	_draw_sweep(k, -PI * 0.5, -PI * 0.5 + TAU, SWEEP_CIRCLE, env)

func _draw_cone(k: float, env: float) -> void:
	var arc := PI * 0.5
	var grow := lerpf(FILL_START, 1.0, clampf(k / GROW_END, 0.0, 1.0))
	GroundFx.sector(self, Vector2.ZERO, facing, radius * grow, arc,
		Color(FX_COLOR, FILL_ALPHA * 0.7 * env), 16)
	GroundFx.sector_outline(self, Vector2.ZERO, facing, radius, arc,
		Color(FX_COLOR, INK_ALPHA * env), 2.0, 16)
	ground_draws += 2
	var mid := Iso.ground_dir(facing).angle()
	_draw_sweep(k, mid - arc * 0.5, mid + arc * 0.5, SWEEP_CONE, env)

## 沿边缘流动的高亮段：这是「技能正在发生」的唯一动态证据。
## 🔴 半径**恒定**、只动角度 —— 绝不拿它表达范围大小，那一律由描边负责。
## `a_start` / `a_end` 是**地面角**（`Iso.ground_arc` 同口径），`highlight` 是高亮段长度。
func _draw_sweep(k: float, a_start: float, a_end: float, highlight: float, env: float) -> void:
	var span := a_end - a_start
	if span <= 0.0:
		return
	var lit := minf(highlight, span)
	var a0 := a_start + (span - lit) * k
	var ink := Color(FX_COLOR.lightened(0.35), INK_ALPHA * env)
	draw_polyline(Iso.ground_arc(Vector2.ZERO, radius, a0, a0 + lit, 10), ink, 2.0, true)
	ground_draws += 1
