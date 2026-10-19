extends Node
## M10-3b 契约（工程文档 44 §5）：多目标 Boss 血条（P-7）+ `current_bosses()`（P-8）。
##
## 核心底线：`boss_id` 一旦退回「按名字 / 按 monster_id 认人」，循环图同区两只同名 Boss
## 会塌成一条血条——**游戏照常能玩、日志不报错**，只是数值一直在跳。所以断言全部压在
## 「条数 / 顺序 / 逐条数值 / 逐条过期 / 逐条死亡」这些能被精确破坏的点上。

const BAR_SCENE := preload("res://scenes/ui/BossHealthBar.tscn")
const MONSTER_SCENE := preload("res://scenes/entities/Monster.tscn")
const ARENA_MAP := "c7_arena"
const EMPTY_BOSS_MAP := "ash_land"
const SINGLE_BOSS_MAP := "corruption_source"

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[BossMultiTargetTest] " + label)

func _ready() -> void:
	GameState.reset_to_defaults()
	_test_independent()
	await _test_same_monster_id()
	_test_no_reorder()
	_test_cap()
	_test_expiry()
	_test_death_isolated()
	_test_dying_flag()
	_test_current_bosses()
	_test_current_boss_shell()
	_test_audio_per_instance()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[BossMultiTargetTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[BossMultiTargetTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

func _new_bar() -> Control:
	var bar: Control = BAR_SCENE.instantiate()
	add_child(bar)
	return bar

# ---- 1) 两个实例各占一条，数值互不覆盖 ----

func _test_independent() -> void:
	var bar := _new_bar()
	check(not bar.visible and bar.bar_count() == 0, "血条初始应为空且隐藏")
	EventBus.boss_hp_changed.emit(9101, "同名首领", 900, 1000, 0)
	EventBus.boss_hp_changed.emit(9102, "同名首领", 400, 1000, 1)
	check(bar.visible and bar.bar_count() == 2,
		"同名两只应各占一条，实际 %d 条" % bar.bar_count())
	check(int(bar.bar_state(9101).get("hp", -1)) == 900, "第一条血量应独立为 900")
	check(int(bar.bar_state(9102).get("hp", -1)) == 400, "第二条血量应独立为 400")
	check(int(bar.bar_state(9102).get("phase", -1)) == 1, "第二条阶段应独立为 1")
	bar.queue_free()

# ---- 2) 同种模板的两个真实实例也必须分开 ----

func _test_same_monster_id() -> void:
	var rows: Array = Endgame.arena_bosses()
	check(not rows.is_empty(), "endgame.json 应有 arenaBosses")
	if rows.is_empty():
		return
	var monster_id := String((rows[0] as Dictionary).get("monsterId", ""))
	var host := Node2D.new()
	add_child(host)
	var ids: Array[int] = []
	for i in 2:
		var mon: Monster = MONSTER_SCENE.instantiate()
		mon.monster_id = monster_id
		mon.spawn_level = 60
		host.add_child(mon)
		ids.append(mon.get_instance_id())
	await get_tree().process_frame
	check(ids.size() == 2 and ids[0] != ids[1], "同一模板的两个实例 id 必须不同")
	var bar := _new_bar()
	for child in host.get_children():
		var mon := child as Monster
		if mon != null:
			mon._announce_boss_hp()
	check(bar.bar_count() == 2,
		"同 monster_id 的两只实例如各占一条，实际 %d 条" % bar.bar_count())
	check(int(bar.bar_state(ids[0]).get("max_hp", 0)) > 0, "第一个实例应登记血量上限")
	bar.queue_free()
	host.queue_free()
	await get_tree().process_frame

# ---- 3) 更新不重排（「首见置顶 + 原位更新」，跳位从根上消失）----

func _test_no_reorder() -> void:
	var bar := _new_bar()
	EventBus.boss_hp_changed.emit(9201, "甲", 1000, 1000, 0)
	EventBus.boss_hp_changed.emit(9202, "乙", 1000, 1000, 0)
	var newest_first: Array[int] = [9202, 9201]
	check(bar.bar_ids() == newest_first, "最新接战的应排在最上")
	EventBus.boss_hp_changed.emit(9201, "甲", 800, 1000, 1)
	check(bar.bar_ids() == newest_first, "更新已有条目不得重排（否则两只互打时血条会跳位）")
	check(int(bar.bar_state(9201).get("hp", -1)) == 800, "重排检查后数值仍应更新")
	bar.queue_free()

# ---- 4) 上限淘汰：超 3 条淘汰最久未更新的 ----

func _test_cap() -> void:
	var bar := _new_bar()
	for i in 4:
		EventBus.boss_hp_changed.emit(9300 + i, "首领%d" % i, 100, 100, 0)
	check(bar.bar_count() == 3, "同屏最多 3 条，实际 %d 条" % bar.bar_count())
	check(bar.bar_state(9300).is_empty(), "最久未更新的 9300 应被淘汰")
	check(not bar.bar_state(9303).is_empty(), "刚更新的 9303 必须保留")
	bar.queue_free()

# ---- 5) 逐条过期：一条过期不带走另一条 ----

func _test_expiry() -> void:
	var bar := _new_bar()
	EventBus.boss_hp_changed.emit(9401, "甲", 500, 1000, 0)
	bar._process(2.0)
	EventBus.boss_hp_changed.emit(9402, "乙", 500, 1000, 0)
	bar._process(1.5)
	check(bar.bar_state(9401).is_empty(), "脱战 3s 的 9401 应过期移除")
	check(not bar.bar_state(9402).is_empty(), "刚更新的 9402 不得被连坐移除")
	bar._process(2.0)
	check(bar.bar_count() == 0 and not bar.visible, "全部过期后血条应隐藏")
	bar.queue_free()

# ---- 6) 死亡逐条：打死一只不影响旁边那只 ----

func _test_death_isolated() -> void:
	var bar := _new_bar()
	EventBus.boss_hp_changed.emit(9501, "甲", 1000, 1000, 0)
	EventBus.boss_hp_changed.emit(9502, "乙", 1000, 1000, 0)
	EventBus.boss_hp_changed.emit(9501, "甲", 0, 1000, 2)
	check(int(bar.bar_state(9501).get("hp", -1)) == 0, "死亡的 9501 血量应为 0")
	check(float(bar.bar_state(9501).get("dying_left", 0.0)) > 0.0, "死亡的 9501 应进入淡出")
	check(is_equal_approx(float(bar.bar_state(9502).get("alpha", 0.0)), 1.0),
		"旁边的 9502 不得跟着变淡")
	check(int(bar.bar_state(9502).get("hp", -1)) == 1000, "旁边的 9502 血量不得变化")
	bar._process(0.95)
	check(bar.bar_state(9501).is_empty(), "淡出结束后 9501 应移除")
	check(not bar.bar_state(9502).is_empty(), "9501 移除后 9502 必须仍在")
	bar.queue_free()

# ---- 7) `_dying` 语义：只有全部在死亡淡出才为真 ----

func _test_dying_flag() -> void:
	var bar := _new_bar()
	EventBus.boss_hp_changed.emit(9601, "甲", 1000, 1000, 0)
	EventBus.boss_hp_changed.emit(9602, "乙", 1000, 1000, 0)
	EventBus.boss_hp_changed.emit(9601, "甲", 0, 1000, 2)
	check(not bar._dying, "一条死亡 + 一条存活时 _dying 应为假")
	EventBus.boss_hp_changed.emit(9602, "乙", 0, 1000, 2)
	check(bar._dying, "全部死亡时 _dying 应为真")
	bar.queue_free()

# ---- 8) `current_bosses()`：数组配置 ----

func _test_current_bosses() -> void:
	GameState.current_map = ARENA_MAP
	var arena: Array = MapService.current_bosses()
	check(arena.size() == 10, "循环图应有 10 个 Boss 点，实际 %d" % arena.size())
	GameState.current_map = SINGLE_BOSS_MAP
	var single: Array = MapService.current_bosses()
	check(single.size() == 1, "单点 Boss 图应返回 1 条，实际 %d" % single.size())
	check(String((single[0] as Dictionary).get("monsterId", "")) != "",
		"单点图返回的规格应带 monsterId")
	GameState.current_map = EMPTY_BOSS_MAP
	check(MapService.current_bosses().is_empty(), "无 Boss 图应返回空数组")

# ---- 9) `current_boss()` 兼容壳（既有断言零改动）----

func _test_current_boss_shell() -> void:
	GameState.current_map = ARENA_MAP
	var arena: Array = MapService.current_bosses()
	var first: Dictionary = MapService.current_boss()
	check(first == arena[0], "多 Boss 图上 current_boss() 必须等于 current_bosses()[0]")
	GameState.current_map = EMPTY_BOSS_MAP
	check(MapService.current_boss().is_empty(), "灰烬之地不应有 Boss 点")
	GameState.current_map = SINGLE_BOSS_MAP
	check(bool(MapService.current_boss().get("tombstone", false)),
		"腐化源头 Boss 点应启用墓碑（既有断言）")

# ---- 10) 音频按实例记状态，不再被多目标顶掉 ----

func _test_audio_per_instance() -> void:
	AudioCues.cue_counts["boss"] = 0
	AudioCues._last_played.erase("boss")
	EventBus.boss_hp_changed.emit(9701, "甲", 1000, 1000, 0)
	AudioCues._last_played.erase("boss")
	EventBus.boss_hp_changed.emit(9702, "乙", 1000, 1000, 0)
	check(int(AudioCues.cue_counts.get("boss", 0)) == 2,
		"两只不同实例各应响一次，实际 %d" % int(AudioCues.cue_counts.get("boss", 0)))
	# 两只交替心跳（循环图同区实况）：单游标会把「换人」判成新 Boss，每秒响一次。
	AudioCues._last_played.erase("boss")
	EventBus.boss_hp_changed.emit(9701, "甲", 900, 1000, 0)
	check(int(AudioCues.cue_counts.get("boss", 0)) == 2,
		"两只交替心跳不应再响，实际 %d" % int(AudioCues.cue_counts.get("boss", 0)))
	# 同一只重复心跳（同名同阶段）不得反复响。
	AudioCues._last_played.erase("boss")
	EventBus.boss_hp_changed.emit(9702, "乙", 900, 1000, 0)
	check(int(AudioCues.cue_counts.get("boss", 0)) == 2,
		"同一只重复心跳不应再响，实际 %d" % int(AudioCues.cue_counts.get("boss", 0)))
	# 升阶段要响。
	AudioCues._last_played.erase("boss")
	EventBus.boss_hp_changed.emit(9702, "乙", 500, 1000, 1)
	check(int(AudioCues.cue_counts.get("boss", 0)) == 3,
		"升阶段应再响一次，实际 %d" % int(AudioCues.cue_counts.get("boss", 0)))
	# 死亡清状态：同 id 再接战视为新敌人。
	EventBus.boss_hp_changed.emit(9702, "乙", 0, 1000, 1)
	AudioCues._last_played.erase("boss")
	EventBus.boss_hp_changed.emit(9702, "乙", 1000, 1000, 0)
	check(int(AudioCues.cue_counts.get("boss", 0)) == 4,
		"死亡后同 id 再接战应重新响，实际 %d" % int(AudioCues.cue_counts.get("boss", 0)))
	AudioCues.cue_counts["boss"] = 0
