extends Node2D
## 全主题真实Monster渲染复核，不执行伤害结算，不进入正式游戏流程。
## 依次拍摄全部主题的锁定预警与命中，不执行战斗。
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	RenderingServer.set_default_clear_color(Color("111b20"))
	DirAccess.make_dir_recursive_absolute("/tmp/boss_visual_gallery")
	var label := Label.new()
	label.position = Vector2(35, 22)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", PanelChrome.TEXT)
	add_child(label)
	for id in DataLoader.get_table("bossVisuals").bosses:
		var boss := preload("res://scenes/entities/Monster.tscn").instantiate()
		boss.monster_id = id
		boss.ai_enabled = false
		boss.position = Vector2(640, 370)
		add_child(boss)
		boss.set_physics_process(false)
		label.text = boss.display_name + " · 技能主题预览"
		var geos: Array = []
		if boss.boss_action != null:
			if boss.boss_action.shape == "line":
				boss.position = Vector2(220, 370)
			boss.boss_action._start(boss.position, Vector2.RIGHT, BossAction.Move.A)
			boss.boss_action._t = boss.boss_action.warn_t * 0.12
			geos.append(boss.boss_action.geometry())
		elif id == "boss_corrupted_beast":
			boss._stomp_center = boss.position
			boss._stomp_radius = 120.0
			boss._stomp_total = 0.8
			boss._stomp_remaining = 0.08
			boss._stomp_pending = true
			geos.append(boss._stomp_geometry())
		else:
			boss._chapter_boss_origin = boss.position
			boss._chapter_boss_target = boss.position + Vector2(200, 30)
			boss._chapter_boss_warn = "sweep" if id == "c2_boss_iron_foreman" else ("blasts" if id == "c2_boss_slag_devourer" else "circle")
			boss._chapter_boss_centers.assign([boss.position + Vector2(-180, 0), boss.position, boss.position + Vector2(180, 0)])
			boss._chapter_boss_warn_total = 1.0
			boss._chapter_boss_warn_left = 0.1
			geos = boss._chapter_boss_geometries()
		boss.queue_redraw()
		boss._boss_ground.queue_redraw()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/boss_visual_gallery/%s_warning.png" % id)
		boss._stomp_pending = false
		boss._chapter_boss_warn = ""
		if boss.boss_action != null:
			boss.boss_action.cancel()
		for geo in geos:
			boss._boss_visual_impact(geo)
		boss._boss_visual.tick(0.07)
		boss.queue_redraw()
		boss._boss_ground.queue_redraw()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/boss_visual_gallery/%s_impact.png" % id)
		boss.queue_free()
		await get_tree().process_frame
	print("[BossVisualGallery] 全部通过 ✅")
	get_tree().quit()
## 绘制中性等距参考网格，便于检查投影。
func _draw() -> void:
	for x in range(-2000, 3500, 64):
		draw_line(Vector2(x, 0), Vector2(x + 2000, 1000), Color("253239"), 1)
		draw_line(Vector2(x, 0), Vector2(x - 2000, 1000), Color("253239"), 1)
