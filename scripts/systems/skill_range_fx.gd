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

const FX_COLOR := Color(0.46, 0.91, 0.88)
const LIFETIME := 0.3

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
	var alpha := 1.0 - age / LIFETIME
	var ink := Color(FX_COLOR, 0.6 * alpha)
	if shape == "cone":
		var arc := PI * 0.5
		GroundFx.sector(self, Vector2.ZERO, facing, radius, arc,
			Color(FX_COLOR, 0.14 * alpha), 16)
		GroundFx.sector_outline(self, Vector2.ZERO, facing, radius, arc, ink, 2.0, 16)
		ground_draws += 2
		return
	# 到这里只可能是 circle（`draws_ground` 已把其余形状全部滤掉）。
	# 刻意**不写 `else`**：兜底分支承担语义分派正是本次 bug 的成因。
	GroundFx.fill(self, Vector2.ZERO, radius, Color(FX_COLOR, 0.10 * alpha))
	GroundFx.outline(self, Vector2.ZERO, radius, ink, 2.0, 40)
	ground_draws += 2
