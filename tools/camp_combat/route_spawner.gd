extends MonsterSpawner
## 外围样板刷新适配器：生成、预算、死亡计时和退场复用正式Spawner，仅在生成成功后换装。
var scene: Node2D
var created := 0

## 让正式刷新器完整装配实体，再绑定样板外观和统计信号；不改数值或刷新规则。
func _spawn(point: Dictionary, active: Variant = null) -> bool:
	if not super._spawn(point,active):
		return false
	var enemy := point.entry as Monster
	enemy.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	enemy.safe_margin = 0.001
	scene._replace_art(enemy,"wolf" if enemy.monster_id=="wolf_corrupted" else "beetle")
	enemy.appearance_head_hp_y = -78.0
	enemy.died.connect(scene._on_kill)
	enemy.died.connect(scene._on_point_killed.bind(String(point.monster_id)+"#"+str(point.ordinal)))
	created += 1
	return true
