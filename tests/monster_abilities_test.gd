extends Node
## 能力配置回归：不同身份复用双发行为，非法参数在数据边界拒绝；仅运行于隔离项目。

## 用真实怪物发射入口检验克隆模板，避免只检查配置表相等。
func _ready() -> void:
	var original: Dictionary = DataLoader.get_entry("monsters", "c2_elite_gray_scribe")
	var clone := original.duplicate(true)
	clone.id = "probe_other_chapter_archer"
	DataLoader.tables.monsters.append(clone)
	var monster := preload("res://scenes/entities/Monster.tscn").instantiate() as Monster
	monster.monster_id = clone.id
	add_child(monster)
	monster.set_physics_process(false)
	monster._ranged_target = monster.global_position + Vector2(100, 0)
	monster._fire_projectile()
	var bolts := 0
	for child in get_children():
		if child is MonsterProjectile:
			bolts += 1
	assert(bolts == 2, "克隆怪物应双发，实际 %d，能力 %s" % [bolts, str(monster.template.get("abilities"))])
	assert(MonsterAbilities.validate([clone]).is_empty(), "合法克隆能力未通过校验")
	clone.abilities.projectiles = 3
	assert(not MonsterAbilities.validate([clone]).is_empty())
	clone.abilities = {"heal": {"group": "well", "interval": 0, "range": 180, "fraction": 0.1}}
	assert(not MonsterAbilities.validate([clone]).is_empty())
	clone.abilities = {"summon": "missing", "summonCount": 2}
	assert(not MonsterAbilities.validate([clone]).is_empty())
	DataLoader.load_all()
	print("[MonsterAbilitiesTest] PASS")
	get_tree().quit()
