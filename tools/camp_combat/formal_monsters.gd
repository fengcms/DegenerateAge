extends "res://tools/camp_combat/main.gd"
## 正式两怪表现接入验收：怪物保留MonsterAppearance装配结果，禁止用隔离适配器替代。
## 实战仍复用原两怪闭环；额外检查帧格、缓存预取和原有接触/死亡接口。

## 主角暂保留样板外观，狼与甲虫必须由正式外观档案创建MonsterActorArt。
func _replace_art(actor: CharacterBody2D, kind: String) -> void:
	if kind=="hero":
		super._replace_art(actor,kind)
		return
	assert(actor.sample_art is MonsterActorArt,"正式外观未接入，不能用测试适配器兜底")
	var art := actor.sample_art as MonsterActorArt
	assert(art.frame_size==Vector2(128,96) and art.pivot==Vector2(64,80))
	assert(art.definitions.size()==5 and art.definitions.attack.contact==2)
	assert(is_equal_approx(art.death_duration(),0.9))

## 检查正式地图预取与八向帧契约后执行真实追击、反击、死亡、经验及掉落验收。
func _run_verification() -> void:
	MonsterAnimationCache.prepare_for_map("wild_trial")
	for id in ["wolf_corrupted_modular_v1","shellback_bug_modular_v1"]:
		assert(MonsterAnimationCache.cached_ids().has(id))
	for enemy in enemies:
		var art := enemy.sample_art as MonsterActorArt
		print("FORMAL_MONSTER_BODY: ",enemy.monster_id," radius=",enemy.radius," separation=",enemy.separation_radius," head_y=",enemy._head_hp_y())
		for direction in range(8):
			art.facing = direction
			for state in ["idle","walk","attack","hit","death"]:
				for frame_index in range(4):
					art._show_pose(state,frame_index)
					assert(art.frame_coords==Vector2i(frame_index,direction))
		art._show_pose("idle",0)
	print("FORMAL_MONSTER_CONTRACT_OK: map cache / eight directions / five states / contact / death")
	await super._run_verification()
