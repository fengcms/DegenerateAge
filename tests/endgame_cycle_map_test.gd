extends Node
## 双循环图数据、入口与奖励契约测试；在隔离项目中运行，结束时恢复运行态。

var failures: Array[String] = []

## 记录失败条件，以便一次运行报告全部地图契约问题。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[EndgameCycleMapTest] " + label)

## 验证等级与 14 槽紫装边界，不依赖真实玩家存档。
func _test_entry() -> void:
	GameState.current_map = "c7_arena"
	GameState.unlocks["campaign_complete"] = true
	GameState.player["level"] = 79
	check(not MapService.entry_gate_reason("c7_gold_field").is_empty(), "79 级无法进入金币图")
	GameState.player["level"] = 80
	check(MapService.entry_gate_reason("c7_gold_field").is_empty(), "80 级可从回廊进入金币图")
	check(not MapService.entry_gate_reason("c7_gold_field", "carter").is_empty(), "快捷旅行无法进入金币图")
	GameState.player["level"] = 99
	check(MapService.entry_gate_reason("c7_boss_field").contains("100"), "99 级不可进入百 Boss 图")
	GameState.player["level"] = 100
	check(MapService.entry_gate_reason("c7_boss_field").contains("全身"), "缺少紫装不能进入百 Boss 图")
	for slot in Equipment.SLOT_DEFS:
		GameState.equipment[String(slot.id)] = {"quality": "legendary"}
	check(MapService.entry_gate_reason("c7_boss_field").is_empty(), "14 槽紫装可入图")
	GameState.equipment["ring_2"] = {"quality": "epic"}
	check(MapService.entry_gate_reason("c7_boss_field").contains("戒指"), "双戒指任一非紫装应阻挡")
	check(not MapService.entry_gate_reason("c7_boss_field", "walk", "c6_map00").is_empty(), "不可从其他地图绕入")

## 固定刷新点数量、坐标、重生、掉落与连通布局必须和产品规则一致。
func _test_maps() -> void:
	var gold: Dictionary = DataLoader.get_entry("maps", "c7_gold_field")
	var boss: Dictionary = DataLoader.get_entry("maps", "c7_boss_field")
	var count := 0
	for group in gold.get("spawnPoints", []):
		count += int(group.get("count", 0))
		check(int(group.get("respawnTime", 0)) == 15, "金币怪 15 秒重生")
		check(Endgame.has_norm(String(group.get("monsterId", ""))), "金币怪需有归一化数值")
	check(count == 96 and int(gold.get("normalCap", 0)) == 28, "金币图 96 席、同屏上限 28")
	var seats: Array = boss.get("bossSpawns", [])
	check(seats.size() == 100 and int(boss.get("bossCap", 0)) == 18, "百 Boss 图 100 席、同屏上限 18")
	for seat in seats:
		check(int(seat.get("respawnTime", 0)) == 600, "Boss 每席 600 秒重生")
	check(BossToken.keys_of("c7_boss_field").size() == 100, "100 席序号可追踪")
	var gold_drop: Dictionary = DataLoader.get_entry("dropTables", "DT_C7_Gold_Normal")
	var gold_range: Array = (gold_drop.get("entries", [])[0] as Dictionary).get("goldRange", [])
	check(gold_range.size() == 2 and int(gold_range[0]) == 176 and int(gold_range[1]) == 224, "金币范围 176–224")
	var boss_drop: Dictionary = DataLoader.get_entry("dropTables", "DT_C7_Boss_Field")
	var equip_rows := 0
	for row in boss_drop.get("entries", []):
		if String(row.get("kind", "")) == "equip":
			equip_rows += 1
	check(equip_rows == 6, "Boss 装备三组各独立尝试两次")
	check(DataLoader.validate_all().is_empty(), "地图和掉落引用通过全量校验")

## 隔离测试入口，所有失败均以非零退出码传给运行器。
func _ready() -> void:
	GameState.reset_to_defaults()
	_test_entry()
	_test_maps()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[EndgameCycleMapTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[EndgameCycleMapTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)
