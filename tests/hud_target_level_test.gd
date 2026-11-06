extends Node
## 目标等级回归：在正式HUD中切换运行实例、NPC与空目标，检查动态等级和四位数边界。
var failures: Array[String] = []

## 验证实际目标事件链；窗口模式额外生成临时截图供视觉复核。
func _ready() -> void:
	GameState.reset_to_defaults()
	SaveManager.active_slot = -1
	SaveManager.autosave_enabled = false
	get_window().size = Vector2i(1280, 800)
	var hud := load("res://scenes/ui/Hud.tscn").instantiate() as Control
	add_child(hud)
	var badge := hud.get_node("TargetPanel/TargetLevelBadge") as Control
	var label := badge.get_node("LevelLabel") as Label
	var hp := hud.get_node("TargetPanel/TargetHp") as Control
	var monster := load("res://scenes/entities/Monster.tscn").instantiate() as Monster
	monster.monster_id = "wolf_corrupted"
	monster.spawn_level = 1234
	add_child(monster)
	monster.set_physics_process(false)
	EventBus.target_changed.emit(monster)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(label.text == "1234" and badge.is_visible_in_tree(), "显示实例等级而非模板等级")
	_check(badge.position.x + badge.size.x <= hp.position.x, "徽章不遮挡目标血条")
	_check(badge.position.y + badge.size.y <= 70.0, "徽章不遮挡下方跨级提示")
	for level in [1, 999, 1000, 9999]:
		monster.level = level
		EventBus.target_changed.emit(monster)
		await get_tree().process_frame
		await get_tree().process_frame
		var width := label.get_theme_font("font").get_string_size(str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		_check(label.text == str(level) and label.size.x >= width, "等级%d完整可读" % level)
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png("/tmp/da-target-level.png")
	var npc := load("res://scenes/entities/Npc.tscn").instantiate() as Npc
	add_child(npc)
	EventBus.target_changed.emit(npc)
	_check(not badge.visible and label.text.is_empty(), "NPC不残留怪物等级")
	EventBus.target_changed.emit(null)
	_check(not badge.visible, "取消目标隐藏等级")
	var boss := load("res://scenes/entities/Monster.tscn").instantiate() as Monster
	boss.monster_id = "c6_boss03"
	add_child(boss)
	boss.set_physics_process(false)
	EventBus.target_changed.emit(boss)
	await get_tree().process_frame
	_check(not hud.get_node("TargetPanel").visible, "Boss继续显示独立血条，不重复普通卡")
	monster.queue_free()
	npc.queue_free()
	boss.queue_free()
	hud.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("[HudTargetLevelTest] PASS")
	get_tree().quit(0 if failures.is_empty() else 1)

## 汇总行为失败，避免仅验证场景存在而漏掉显示串台。
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[HudTargetLevelTest] " + message)
