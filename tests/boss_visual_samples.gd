extends Node2D
## 实际Monster场景与技能几何的表现验收；截图/动效帧仅输出/tmp。
var _label: Label
## 以固定玩法步长输出三类技能动效帧，不执行伤害。
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("[BossVisualSamples] 需要窗口模式")
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1280, 800))
	RenderingServer.set_default_clear_color(Color("111b20"))
	_label = Label.new()
	_label.position = Vector2(36, 22)
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color("e8d8ae"))
	add_child(_label)
	DirAccess.make_dir_recursive_absolute("/tmp/boss_visual_frames")
	for sample in ["stomp", "line", "ring"]:
		var boss := preload("res://scenes/entities/Monster.tscn").instantiate()
		boss.monster_id = "boss_corrupted_beast" if sample == "stomp" else "c3_boss01"
		boss.ai_enabled = false
		boss.position = Vector2(210, 390) if sample == "line" else Vector2(640, 400)
		add_child(boss)
		boss.set_physics_process(false)
		var action: BossAction = boss.boss_action
		if sample == "stomp":
			boss._stomp_pending = true
			boss._stomp_center = boss.position
			boss._stomp_radius = 120.0
			boss._stomp_total = 0.8
		else:
			action._start(boss.position, Vector2.RIGHT, BossAction.Move.B if sample == "ring" else BossAction.Move.A)
		_label.text = {"stomp": "腐化巨兽 · 践踏", "line": "闸印守卫 · 双线分段", "ring": "闸印守卫 · 环击（中心安全）"}[sample]
		var frames := 42 if sample == "stomp" else (108 if sample == "line" else 60)
		for frame in range(frames):
			if sample == "stomp":
				boss._stomp_remaining = maxf(0.0, 0.8 - frame / 30.0)
				if boss._stomp_pending and boss._stomp_remaining <= 0.0:
					boss._stomp_pending = false
					boss._boss_visual_impact(boss._stomp_geometry())
			else:
				action.update(1.0 / 30.0, boss.position, Vector2.RIGHT, true, 0.4 if sample == "ring" else 1.0, func(_coeff: float) -> void: pass)
			boss._boss_visual.tick(1.0 / 30.0)
			boss.queue_redraw()
			boss._boss_ground.queue_redraw()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/tmp/boss_visual_frames/%s_%03d.png" % [sample, frame])
		boss.queue_free()
		await get_tree().process_frame
	print("[BossVisualSamples] 全部通过 ✅")
	get_tree().quit()
## 绘制中性等距参考背景供动效复核。
func _draw() -> void:
	for x in range(-1000, 2000, 64):
		draw_line(Vector2(x, 0), Vector2(x + 1600, 800), Color("253239"), 1)
		draw_line(Vector2(x, 0), Vector2(x - 1600, 800), Color("253239"), 1)
