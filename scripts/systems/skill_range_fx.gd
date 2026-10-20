extends Node2D
## 主动技能的短暂程序范围提示；与伤害结算解耦，不改变实际命中范围。
##
## 🔴 刻意不一致（工程 53 §4.3）：本 FX 画的是**地面椭圆**，而施法门控与命中筛选
## （`player.gd` 的 `range × TILE_W`）仍是屏幕度量 —— 所以提示范围**小于**实际命中范围
## （横向等宽、纵向只有一半）。方向与 Boss 预警相反：Boss 预警画小了玩家会白挨打，
## 这里画小了只是「以为打不到、其实打到了」，属于可容忍的保守提示。
## 不要为了「看着一致」补成 ×√2 —— 那会让玩家以为打得到的位置其实打不到。

var shape := "circle"
var radius := Iso.TILE_W   # 默认 1 格（7.1：tileW=64，单一来源 Iso.TILE_W）
var facing := Vector2.RIGHT
var age := 0.0

func _process(delta: float) -> void:
	age += delta
	if age >= 0.3:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	var alpha := 1.0 - age / 0.3
	var ink := Color(0.46, 0.91, 0.88, 0.6 * alpha)
	if shape == "cone":
		var arc := PI * 0.5
		GroundFx.sector(self, Vector2.ZERO, facing, radius, arc,
			Color(0.46, 0.91, 0.88, 0.14 * alpha), 16)
		GroundFx.sector_outline(self, Vector2.ZERO, facing, radius, arc, ink, 2.0, 16)
	else:
		GroundFx.fill(self, Vector2.ZERO, radius, Color(0.46, 0.91, 0.88, 0.10 * alpha))
		GroundFx.outline(self, Vector2.ZERO, radius, ink, 2.0, 40)
