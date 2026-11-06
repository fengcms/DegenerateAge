extends Node
## Boss状态栏表现回归：真实外观、同名不同实例、四位等级、极大血量与切图释放。
var failures: Array[String] = []

## 在正式HUD旁装配3个真实Boss，窗口模式截取实际呈现供人工复核。
func _ready() -> void:
	GameState.reset_to_defaults()
	SaveManager.active_slot = -1
	SaveManager.autosave_enabled = false
	get_window().size = Vector2i(1280, 800)
	var hud := load("res://scenes/ui/Hud.tscn").instantiate() as Control
	add_child(hud)
	var bar := load("res://scenes/ui/BossHealthBar.tscn").instantiate() as Control
	add_child(bar)
	var host := Node2D.new()
	add_child(host)
	var bosses: Array[Monster] = []
	for spec in [["boss_corrupted_beast",1234],["c2_boss_iron_foreman",9999],["c6_boss03",1000]]:
		var boss := load("res://scenes/entities/Monster.tscn").instantiate() as Monster
		boss.monster_id = spec[0]
		boss.spawn_level = spec[1]
		host.add_child(boss)
		boss.set_physics_process(false)
		boss.max_hp = 9007199254740991
		boss.hp = 8007199254740991
		boss.display_name = "裂隙主宰·拥有极长称号的首领·同名目标"
		boss._announce_boss_hp()
		bosses.append(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(bar.bar_count() == 3, "三个同名Boss独立展示")
	for boss in bosses:
		var state: Dictionary = bar.bar_state(boss.get_instance_id())
		var portrait := state.get("portrait") as AtlasTexture
		_check(portrait != null and portrait.region.has_area(), "各代真实外观均有有效头像裁切")
		var row: BossStatusRow = bar._rows[boss.get_instance_id()]
		_check(row._level.text == str(boss.level), "四位等级读取运行实例")
		_check(row._level.size.x >= row._level.get_minimum_size().x, "等级文字不得被裁掉")
		_check(row._name_label.position.x + row._name_label.size.x <= row._phase.position.x, "名称与阶段不得争抢区域")
		if row._expanded:
			_check(row._numbers.size.x >= row._numbers.get_minimum_size().x, "最大合法血量完整容纳")
	var ids: Array[int] = bar.bar_ids()
	bosses[0].hp -= 1
	bosses[0]._announce_boss_hp()
	_check(bar.bar_ids() == ids, "反复更新不得重排")
	var cache: MonsterPortraitCache = bar._portraits
	_check(cache.cached_count() == 3, "每种外观仅缓存一个裁切")
	var missing := Monster.new()
	missing.template = {"appearanceId":"missing_portrait_test"}
	_check(cache.get_portrait(missing) == null and cache.cached_count() == 3, "缺图回退不污染缓存")
	missing.free()
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png("/tmp/da-boss-status.png")
	EventBus.map_changed.emit("wild_trial")
	_check(bar.bar_count() == 0 and cache.cached_count() == 0, "切图释放全部Boss条目与头像缓存")
	bar.queue_free()
	hud.queue_free()
	host.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("[BossStatusPresentationTest] PASS")
	get_tree().quit(0 if failures.is_empty() else 1)

## 累计行为断言，任何失败均以非零状态结束。
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[BossStatusPresentationTest] " + message)
