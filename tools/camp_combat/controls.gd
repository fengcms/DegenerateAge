extends "res://tools/camp_combat/main.gd"
## 隔离实战控制回归：正式玩家绕实体障碍、动作中断及死亡复活，不改变正式存档。

## 关闭怪物干扰后检验真实路径和动作生命周期；任何断言失败不打印成功标记。
func _run_verification() -> void:
	for enemy in enemies:
		enemy.free()
	GameState.set_auto_battle(false)
	GameState.set_auto_pickup(false)
	await get_tree().physics_frame
	for cell in camp.collision_cells:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = Iso.grid_to_world(cell)
		var found := false
		for hit in get_world_2d().direct_space_state.intersect_point(query):
			found = found or hit.collider==camp.collision_cells[cell]
		assert(found,"共享轮廓的实际碰撞缺失："+str(cell))
	var ground := get_node("Ground") as IsoGround
	var target := Iso.grid_to_world(Vector2i(5,3))
	assert(not ground.is_walkable_cell(Vector2i(4,3)))
	var route := ground.route(hero.position,target)
	assert(route.size()>1,"测试路线没有绕开箱子")
	assert(hero.request_map_move(target))
	var deadline := Time.get_ticks_msec()+15000
	var walked := false
	while hero.position.distance_to(target)>10 and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
		walked = walked or hero.sample_art.pose=="walk"
	assert(hero.position.distance_to(target)<=10 and walked,"正式点击移动未绕过箱子")
	hero.sample_art.attack(Vector2.RIGHT,1)
	assert(hero.sample_art.pose=="attack" and hero.sample_art.phase==2)
	await get_tree().create_timer(0.10).timeout
	hero.request_map_move(Iso.grid_to_world(Vector2i(7,3)))
	await get_tree().create_timer(0.10).timeout
	assert(hero.sample_art.pose=="walk","手动接管仍滑行播放攻击")
	hero.sample_art.hit()
	assert(hero.sample_art.pose=="hit")
	await get_tree().create_timer(0.25).timeout
	assert(hero.sample_art.pose!="hit")
	hero.apply_damage(100000)
	await get_tree().create_timer(1.0).timeout
	assert(hero.is_dead and hero.sample_art.pose=="death" and hero.sample_art.phase==3)
	hero._revive()
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not hero.is_dead and hero.sample_art.pose!="death","复活仍保持倒地")
	print("CAMP_CONTROLS_OK: real obstacle route / attack cancel / hit / death / revive")
	get_tree().quit()
