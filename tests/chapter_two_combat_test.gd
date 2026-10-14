extends Node
## Validate visible boss warning, dodge window and summon reward suppression.

class TestPlayer extends Node2D:
	var is_dead := false
	var total_damage := 0
	func apply_damage(amount: int) -> int:
		total_damage += amount
		return amount

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterTwoCombatTest] " + message)

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "c2_old_well"
	var arena := Node2D.new()
	add_child(arena)
	var player := TestPlayer.new()
	player.add_to_group("player")
	player.global_position = Vector2(100, 0)
	add_child(player)
	var boss := preload("res://scenes/entities/Monster.tscn").instantiate() as Monster
	boss.monster_id = "c2_boss_iron_foreman"
	boss.spawn_level = 15
	boss.ai_enabled = false
	arena.add_child(boss)
	boss.global_position = Vector2.ZERO
	boss.spawn_position = Vector2.ZERO
	boss.state = Monster.State.CHASE
	boss._chapter_boss_skill_cd = 0.0
	check(boss._update_chapter_boss(0.05) and boss._chapter_boss_warn == "sweep", "铁臂先显示横扫预警")
	player.global_position = Vector2(300, 0)
	boss._update_chapter_boss(1.1)
	check(player.total_damage == 0 and boss._chapter_boss_warn.is_empty(), "离开预警区可以躲避")
	player.global_position = Vector2(100, 0)
	boss._chapter_boss_skill_cd = 0.0
	boss._update_chapter_boss(0.05)
	boss._update_chapter_boss(1.3)
	check(player.total_damage > 0, "预警结束后在范围内才命中")
	boss.hp = int(boss.max_hp * 0.2)
	boss._update_chapter_boss(0.1)
	await get_tree().process_frame
	var summon_count := 0
	for child in arena.get_children():
		if child is Monster and child != boss:
			summon_count += 1
			check(child.suppress_rewards, "召唤守卫无经验/掉落/任务收益")
	check(summon_count == 2, "铁臂低血只召唤两名守卫")
	boss._die()
	await get_tree().process_frame
	var live_summons := 0
	for child in arena.get_children():
		if child is Monster and child != boss and not child.is_queued_for_deletion():
			live_summons += 1
	check(live_summons == 0, "Boss 倒下清理无收益召唤物")
	for spec in [
		["c2_boss_slag_devourer", "c2_ember_furnace", "line", "blasts"],
		["c2_boss_hundred_arm_extractor", "c2_well_core", "circle", "line"],
	]:
		GameState.current_map = String(spec[1])
		var other := preload("res://scenes/entities/Monster.tscn").instantiate() as Monster
		other.monster_id = String(spec[0])
		other.ai_enabled = false
		arena.add_child(other)
		other.state = Monster.State.CHASE
		other._chapter_boss_skill_cd = 0.0
		player.global_position = Vector2(100, 0)
		other._update_chapter_boss(0.05)
		check(other._chapter_boss_warn == String(spec[2]), "%s 初期预警" % spec[0])
		other._chapter_boss_warn = ""
		other.hp = int(other.max_hp * 0.5)
		if String(spec[0]) == "c2_boss_hundred_arm_extractor":
			other._chapter_boss_casts = 2
		other._chapter_boss_skill_cd = 0.0
		other._update_chapter_boss(0.05)
		check(other._chapter_boss_warn == String(spec[3]), "%s 中期预警" % spec[0])
		other.queue_free()
	print("[ChapterTwoCombatTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
